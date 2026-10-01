import Foundation

public struct Movement: Identifiable, Codable, Sendable {
    public enum Direction: String, Codable, Sendable { case received, sent }
    public let id: String
    public let date: Date
    public let height: Int
    public let zatoshis: Int64
    public let direction: Direction
    public var included: Bool
    public var price: Decimal?
    public var confirmed: Bool
    public let transactionIndex: Int
    public let feeZatoshis: Int64?

    public init(id: String, date: Date, height: Int, zatoshis: Int64,
                direction: Direction, included: Bool = true, price: Decimal? = nil,
                confirmed: Bool = true, transactionIndex: Int = 0, feeZatoshis: Int64? = nil) {
        self.id = id
        self.date = date
        self.height = height
        self.zatoshis = zatoshis
        self.direction = direction
        self.included = included
        self.price = price
        self.confirmed = confirmed
        self.transactionIndex = transactionIndex
        self.feeZatoshis = feeZatoshis
    }

    public var quantity: Decimal { Decimal(zatoshis) / 100_000_000 }
}
