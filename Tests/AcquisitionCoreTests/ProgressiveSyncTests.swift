import XCTest
@testable import AcquisitionCore

final class ProgressiveSyncTests: XCTestCase {
    func testDiscoveredHistoryUpdatesTheRunningValueWithoutLosingPricesOrChoices() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let receipt = Movement(id: "receipt", date: date, height: 100,
            zatoshis: 200_000_000, direction: .received)
        var pricedReceipt = receipt
        pricedReceipt.price = 30
        let send = Movement(id: "send", date: date, height: 101,
            zatoshis: 100_000_000, direction: .sent)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let choices = try ChoiceStore(url: root.appendingPathComponent("choices.json"))
        try choices.set(id: "send", included: false, manualPrice: nil)

        let initial = try AcquisitionLedger.calculate([pricedReceipt])
        XCTAssertEqual(initial.value, 60)
        let discovered = MovementSnapshot.reconcile([receipt, send], previous: [pricedReceipt], choices: choices.choices)
        XCTAssertEqual(discovered.count, 2)
        let provisional = try AcquisitionLedger.calculate(discovered)
        XCTAssertEqual(provisional.value, 60)
        XCTAssertEqual(provisional.averagePrice, 30)
        XCTAssertFalse(discovered[1].included)
        let unpriced = Movement(id: "unpriced", date: date, height: 102,
            zatoshis: 100_000_000, direction: .received)
        let available = try AcquisitionLedger.calculate(discovered + [unpriced], availablePricesOnly: true)
        XCTAssertEqual(available.value, 60)
        XCTAssertEqual(available.averagePrice, 30)

        let replacement = Movement(id: "older-receipt", date: date, height: 99,
            zatoshis: 100_000_000, direction: .received, price: 60)
        try choices.set(id: "send", included: true, manualPrice: nil)
        let updated = MovementSnapshot.reconcile([replacement, receipt, send], previous: discovered, choices: choices.choices)
        let recalculated = try AcquisitionLedger.calculate(updated)
        XCTAssertEqual(recalculated.zatoshis, 200_000_000)
        XCTAssertEqual(recalculated.value, 80)
        XCTAssertEqual(recalculated.averagePrice, 40)
    }
}
