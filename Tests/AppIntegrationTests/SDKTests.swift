import XCTest
import AcquisitionCore
import ZcashLightClientKit
@testable import ZECBuyingPrice

final class SDKTests: XCTestCase {
    // This exact key is an already-public SDK test fixture, not a user credential.
    // Source: https://github.com/zcash/zcash-swift-wallet-sdk/blob/055145a4b2b8e57eb8673d16708dd8c3f0dbb13e/Tests/OfflineTests/DerivationToolTests/DerivationToolMainnetTests.swift
    static let fixtureKey = "uview17fme6ux853km45g9ep07djpfzeydxxgm22xpmr7arzxyutlusalgpqlx7suga4ahzywfuwz4jclm00u7g8u65qvvdt45kttnfunvschssg3h3g06txs9ja32vx3xa8dej3unnatgzjvd0vumk37t8es3ludldrtse3q6226ws7eq4q0ywz78nudwpepgdn7jmxz8yvp7k6gxkeynkam0f8aqf9qpeaej55zhkw39x7epayhndul0j4xjttdxxlnwcd09nr8svyx8j0zng0w6scx3m5unpkaqxcm3hslhlfg4caz7r8d4xy9wm7klkg79w7j0uyzec5s3yje20eg946r6rmkf532nfydu26s8q9ua7mwxw2j2ag7hfcuu652gw6uta03vlm05zju3a9rwc4h367kqzfqrcz35pdwdk2a7yqnk850un3ujxcvve45ueajgvtr6dj4ufszgqwdy0aedgmkalx2p7qed2suarwkr35dl0c8dnqp3"
    func testOfficialMainnetFixtureValidates() throws {
        XCTAssertNoThrow(try UnifiedFullViewingKey(encoding: Self.fixtureKey, network: .mainnet))
        XCTAssertThrowsError(try UnifiedFullViewingKey(encoding: Self.fixtureKey, network: .testnet))
        XCTAssertThrowsError(try UnifiedFullViewingKey(encoding: "invalid", network: .mainnet))
    }
    func testBirthdayUsesEarlierRealCheckpoint() {
        for checkpoint in BirthdayResolver.checkpoints {
            let date = Date(timeIntervalSince1970: checkpoint.time + 172800)
            XCTAssertLessThanOrEqual(BirthdayResolver.height(for: date), checkpoint.height)
        }
    }
    @MainActor func testManualPriceValidationPreservesMovement() {
        let model = WalletModel()
        model.movements = [Movement(id: "receipt", date: Date(), height: 1,
            zatoshis: 100_000_000, direction: .received, included: false, price: 30)]
        for text in ["", "0", "-1", "NaN", "invalid"] {
            model.error = nil
            model.setManualPrice("receipt", text: text)
            XCTAssertEqual(model.error, "Enter a positive USD price.")
            XCTAssertEqual(model.movements[0].price, 30)
        }
        model.error = nil
        model.setManualPrice("receipt", text: "42.50")
        XCTAssertNil(model.error)
        XCTAssertEqual(model.movements[0].price, Decimal(string: "42.50"))
        XCTAssertFalse(model.movements[0].included)
    }
    @MainActor func testWatchOnlyImport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = WalletScanner()
        try await scanner.configure(key: Self.fixtureKey, birthday: 3_470_000,
            directory: root, host: "zec.rocks", port: 443)
        let accounts = try await scanner.synchronizer!.listAccounts()
        XCTAssertEqual(accounts.count, 1)
        scanner.pause()
    }

    @MainActor func testLiveScanReportsProgressAndPauses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = WalletScanner()
        let advanced = expectation(description: "scan reports progress")
        let paused = expectation(description: "scan pauses")
        var didAdvance = false
        var didPause = false
        var lastState = "No state received"
        scanner.onState = { state in
            switch state.syncStatus {
            case .error(let error): lastState = "SDK error: \(error.localizedDescription)"
            case .syncing(let progress, _): lastState = "Syncing \(progress); durable \(state.fullyScannedHeight); tip \(state.latestBlockHeight)"
            case .upToDate: lastState = "Up to date at \(state.fullyScannedHeight)"
            case .stopped: break
            case .unprepared: lastState = "Unprepared"
            }
            if case .syncing(let progress, _) = state.syncStatus, progress > 0 && !didAdvance {
                didAdvance = true
                advanced.fulfill()
            }
            if case .stopped = state.syncStatus, !didPause {
                didPause = true
                paused.fulfill()
            }
        }
        try await scanner.configure(key: Self.fixtureKey, birthday: 3_470_000,
            directory: root, host: "zec.rocks", port: 443)
        try await scanner.start()
        await fulfillment(of: [advanced], timeout: 60)
        XCTAssertTrue(didAdvance, lastState)
        scanner.pause()
        await fulfillment(of: [paused], timeout: 15)
        scanner.close()
    }
}
