import XCTest
@testable import AcquisitionCore

final class PriceTests: XCTestCase {
    func testDecodesPositiveUSDPrice() throws {
        let data = Data(#"{"market_data":{"current_price":{"usd":42.5}}}"#.utf8)
        XCTAssertEqual(try HistoricalPriceService.decode(data), Decimal(string: "42.5"))
    }
    func testRejectsMissingAndZeroPrices() {
        XCTAssertThrowsError(try HistoricalPriceService.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try HistoricalPriceService.decode(Data(#"{"market_data":{"current_price":{"usd":0}}}"#.utf8)))
    }
    func testDayUsesUTC() {
        XCTAssertEqual(HistoricalPriceService.day(Date(timeIntervalSince1970: 86_399)), "01-01-1970")
        XCTAssertEqual(HistoricalPriceService.day(Date(timeIntervalSince1970: 86_400)), "02-01-1970")
    }
    func testChoiceRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ChoiceStore(url: url)
        try store.set(id: "transaction", included: false, manualPrice: 77)
        let restored = try ChoiceStore(url: url)
        XCTAssertEqual(restored.choices["transaction"]?.included, false)
        XCTAssertEqual(restored.choices["transaction"]?.manualPrice, 77)
    }
}
