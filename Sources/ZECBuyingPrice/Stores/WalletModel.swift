import Foundation
import Observation
import CryptoKit
import AcquisitionCore
import ZcashLightClientKit

@MainActor @Observable
final class WalletModel {
    var key = ""
    var birthday = Date(timeIntervalSince1970: 1_577_836_800)
    var heightOverride = ""
    var host = "zec.rocks"
    var port = "443"
    var apiKey = ""
    var proAPI = false
    var movements: [Movement] = []
    var status = "Connect a viewing-only wallet to begin."
    var error: String?
    var progress: Double = 0
    var connected = false
    var busy = false
    var scanComplete = false
    var effectiveBirthday = 0
    var pricingFailures = 0
    var search = ""
    private var walletDirectory: URL?
    private let scanner = WalletScanner()
    private var choices: ChoiceStore?
    private var priceService: HistoricalPriceService?
    private var refreshTask: Task<Void, Never>?

    init() {
        host = UserDefaults.standard.string(forKey: "host") ?? "zec.rocks"
        port = UserDefaults.standard.string(forKey: "port") ?? "443"
        proAPI = UserDefaults.standard.bool(forKey: "proAPI")
        do {
            key = try KeychainStore.read(name: "viewing-key") ?? ""
            apiKey = try KeychainStore.read(name: "price-api-key") ?? ""
        } catch { self.error = "Keychain is unavailable. Your saved credentials could not be loaded." }
        scanner.onState = { [weak self] state in self?.receive(state) }
    }

    var visibleMovements: [Movement] {
        movements.filter { search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) ||
            $0.direction.rawValue.localizedCaseInsensitiveContains(search) }
            .sorted { $0.height == $1.height ? $0.id > $1.id : $0.height > $1.height }
    }
    var ledger: Result<LedgerResult, Error> { Result { try AcquisitionLedger.calculate(movements) } }
    var canDisplayAverage: Bool { scanComplete && !busy }
    static func number(_ value: Decimal?, digits: Int = 2) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = digits == 2 ? 2 : 0
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }

    func connect() {
        guard !busy else { return }
        error = nil
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty,
              let portNumber = Int(port), (1...65535).contains(portNumber) else {
            error = "Enter a TLS lightwalletd host and valid port in Settings."; return
        }
        guard birthday <= Date() else { error = "The wallet birthday cannot be in the future."; return }
        let height = heightOverride.isEmpty ? BirthdayResolver.height(for: birthday) : Int(heightOverride)
        guard let height, height >= 419200, height <= Int(UInt32.max) else {
            error = "Enter a mainnet birthday height at or after Sapling activation (419200)."; return
        }
        effectiveBirthday = BirthdayResolver.checkpointHeight(for: height)
        busy = true
        status = "Preparing local wallet at block \(effectiveBirthday)…"
        Task {
            do {
                let root = try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("ZECBuyingPrice")
                let fingerprint = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
                let walletDirectory = root.appendingPathComponent(fingerprint)
                self.walletDirectory = walletDirectory
                try await scanner.configure(key: key, birthday: effectiveBirthday, directory: walletDirectory, host: host, port: portNumber)
                try KeychainStore.save(key, name: "viewing-key")
                try KeychainStore.save(apiKey, name: "price-api-key")
                choices = try ChoiceStore(url: walletDirectory.appendingPathComponent("choices.json"))
                priceService = try HistoricalPriceService(cacheURL: root.appendingPathComponent("usd-prices.json"), apiKey: apiKey, pro: proAPI)
                UserDefaults.standard.set(host, forKey: "host")
                UserDefaults.standard.set(port, forKey: "port")
                UserDefaults.standard.set(proAPI, forKey: "proAPI")
                connected = true
                try await scanner.start()
                busy = false
            } catch {
                busy = false
                self.error = (error as? WalletScanner.Failure)?.localizedDescription ??
                    "Wallet setup failed. Check the viewing key, birthday, Keychain access, and lightwalletd endpoint."
                status = "Setup failed"
            }
        }
    }

    private func receive(_ state: SynchronizerState) {
        switch state.syncStatus {
        case .syncing(let fraction, _):
            scanComplete = false
            progress = Double(fraction)
            status = "Scanning • \(state.fullyScannedHeight) / \(state.latestBlockHeight) blocks"
        case .upToDate:
            scanComplete = true
            progress = 1
            refreshPrices()
        case .stopped: scanComplete = false; status = "Scan paused • local progress is saved"
        case .error:
            scanComplete = false
            status = "Scan failed"
            error = "Synchronization failed. Check the server connection and resume to retry."
        case .unprepared: break
        }
    }

    func refreshPrices() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            defer { busy = false; refreshTask = nil }
            busy = true
            error = nil
            pricingFailures = 0
            do {
                var fetched = try await scanner.movements()
                for index in fetched.indices {
                    if let choice = choices?.choices[fetched[index].id] {
                        fetched[index].included = choice.included
                        fetched[index].price = choice.manualPrice
                    }
                }
                movements = fetched
                for index in fetched.indices {
                    try Task.checkCancellation()
                    status = "Fetching historical prices • \(index + 1) / \(fetched.count)"
                    if fetched[index].price == nil && fetched[index].confirmed {
                        do { fetched[index].price = try await priceService?.price(on: fetched[index].date) }
                        catch is CancellationError { throw CancellationError() }
                        catch { pricingFailures += 1 }
                    }
                    if let currentIndex = movements.firstIndex(where: { $0.id == fetched[index].id }) {
                        movements[currentIndex].price = choices?.choices[fetched[index].id]?.manualPrice ?? fetched[index].price
                    }
                }
                status = pricingFailures == 0 ? "Synchronized • \(fetched.count) confirmed movements" :
                    "Synchronized • \(pricingFailures) historical prices unavailable"
            } catch is CancellationError { status = "Price retrieval paused" }
            catch { self.error = "Transaction history could not be classified completely. No complete average can be shown."; scanComplete = false }
        }
    }

    func setIncluded(_ id: String, _ included: Bool) {
        guard let index = movements.firstIndex(where: { $0.id == id }) else { return }
        do {
            try choices?.set(id: id, included: included, manualPrice: choices?.choices[id]?.manualPrice)
            movements[index].included = included
        } catch { self.error = "The transaction selection could not be saved." }
    }

    func setManualPrice(_ id: String, text: String) {
        guard let index = movements.firstIndex(where: { $0.id == id }),
              let value = Decimal(string: text), value > 0, !value.isNaN else {
            error = "Enter a positive USD price."; return
        }
        do {
            try choices?.set(id: id, included: movements[index].included, manualPrice: value)
            movements[index].price = value
        } catch { self.error = "The manual price could not be saved." }
    }
    func pause() { scanner.pause(); refreshTask?.cancel() }
    func disconnect() {
        refreshTask?.cancel()
        scanner.close()
        connected = false
        scanComplete = false
        movements = []
        error = nil
        status = "Connect a viewing-only wallet to begin."
    }
    func resetLocalHistory() {
        guard let directory = walletDirectory else { return }
        disconnect()
        do {
            let archive = directory.deletingLastPathComponent().appendingPathComponent("reset-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: directory, to: archive)
            choices = nil
            status = "Local history reset. The previous scan and choices were archived on this Mac."
        } catch { self.error = "Local history could not be reset. Close the app and retry." }
    }
    func resume() {
        Task {
            do { try await scanner.start() }
            catch { self.error = "The scan could not resume. Check the lightwalletd connection." }
        }
    }
}
