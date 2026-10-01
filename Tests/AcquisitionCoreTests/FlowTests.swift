import XCTest
@testable import AcquisitionCore

final class FlowTests: XCTestCase {
    func testExternalReceiptsAndSendsExcludeChangeAndSelfTransfers() throws {
        let result = try WalletFlow.classify([
            .init(amount: 50, fromOwned: false, toOwned: true, change: false),
            .init(amount: 20, fromOwned: true, toOwned: false, change: false),
            .init(amount: 100, fromOwned: true, toOwned: true, change: true),
            .init(amount: 70, fromOwned: true, toOwned: true, change: false)
        ], balanceDelta: 29, fee: 1)
        XCTAssertEqual(result.received, 50)
        XCTAssertEqual(result.sent, 20)
    }
    func testIncompleteOutputsFailReconciliation() {
        XCTAssertThrowsError(try WalletFlow.classify([], balanceDelta: 50, fee: 0))
    }
}
