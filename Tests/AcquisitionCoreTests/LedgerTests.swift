import XCTest
@testable import AcquisitionCore

final class LedgerTests: XCTestCase {
    func movement(_ index: Int, _ amount: Int64, _ direction: Movement.Direction,
                  _ price: Decimal? = nil, included: Bool = true) -> Movement {
        Movement(id: String(index), date: Date(timeIntervalSince1970: Double(index)),
                 height: index, zatoshis: amount, direction: direction,
                 included: included, price: price)
    }

    func testSendPreservesWeightedAverage() throws {
        let result = try AcquisitionLedger.calculate([
            movement(1, 100_000_000, .received, 30),
            movement(2, 100_000_000, .received, 50),
            movement(3, 100_000_000, .sent)
        ])
        XCTAssertEqual(result.zatoshis, 100_000_000)
        XCTAssertEqual(result.value, 40)
        XCTAssertEqual(result.averagePrice, 40)
    }

    func testNewReceiptChangesRemainingAverage() throws {
        let result = try AcquisitionLedger.calculate([
            movement(4, 100_000_000, .received, 60),
            movement(1, 100_000_000, .received, 30),
            movement(3, 100_000_000, .sent),
            movement(2, 100_000_000, .received, 50)
        ])
        XCTAssertEqual(result.averagePrice, 50)
    }

    func testExcludedMovementsHaveNoEffect() throws {
        let result = try AcquisitionLedger.calculate([
            movement(1, 100_000_000, .received, 30),
            movement(2, 100_000_000, .received, nil, included: false),
            movement(3, 200_000_000, .sent, included: false)
        ])
        XCTAssertEqual(result.averagePrice, 30)
        XCTAssertEqual(result.zatoshis, 100_000_000)
    }

    func testMissingPriceAndOversendAreErrors() {
        XCTAssertThrowsError(try AcquisitionLedger.calculate([movement(1, 1, .received)]))
        XCTAssertThrowsError(try AcquisitionLedger.calculate([movement(1, 1, .sent)]))
    }

    func testPendingMovementsDoNotAffectHoldings() throws {
        var pending = movement(1, 100_000_000, .received, 100)
        pending.confirmed = false
        XCTAssertNil(try AcquisitionLedger.calculate([pending]).averagePrice)
    }

    func testSameBlockUsesTransactionOrderInsteadOfIdentifier() throws {
        let receipt = Movement(id: "z", date: Date(timeIntervalSince1970: 0), height: 1,
            zatoshis: 100_000_000, direction: .received, price: 30, transactionIndex: 0)
        let send = Movement(id: "a", date: Date(timeIntervalSince1970: 0), height: 1,
            zatoshis: 100_000_000, direction: .sent, transactionIndex: 1)
        XCTAssertEqual(try AcquisitionLedger.calculate([send, receipt]).zatoshis, 0)
    }

    func testLiquidationResetsCostAndSingleZatoshiIsExact() throws {
        let result = try AcquisitionLedger.calculate([
            movement(1, 100_000_000, .received, 30),
            movement(2, 100_000_000, .sent),
            movement(3, 1, .received, 50)
        ])
        XCTAssertEqual(result.zatoshis, 1)
        XCTAssertEqual(result.value, Decimal(string: "0.0000005"))
        XCTAssertEqual(result.averagePrice, 50)
        let empty = try AcquisitionLedger.calculate([])
        XCTAssertNil(empty.averagePrice)
    }
}
