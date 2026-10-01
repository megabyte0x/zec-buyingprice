import Foundation

public struct LedgerResult: Sendable {
    public let zatoshis: Int64
    public let value: Decimal
    public var averagePrice: Decimal? {
        zatoshis > 0 ? value / (Decimal(zatoshis) / 100_000_000) : nil
    }
}

public enum LedgerError: Error, LocalizedError {
    case missingPrice, inconsistentSelection, invalidAmount
    public var errorDescription: String? {
        switch self {
        case .missingPrice: "Selected receipts need historical prices before an average can be shown."
        case .inconsistentSelection: "A selected send exceeds selected holdings. Review the transaction checkboxes."
        case .invalidAmount: "A transaction contains an invalid amount or price."
        }
    }
}

public enum AcquisitionLedger {
    public static func calculate(_ movements: [Movement]) throws -> LedgerResult {
        var quantity: Int64 = 0
        var cost: Decimal = 0
        let ordered = movements.filter { $0.included && $0.confirmed }.sorted {
            if $0.height != $1.height { return $0.height < $1.height }
            if $0.transactionIndex != $1.transactionIndex { return $0.transactionIndex < $1.transactionIndex }
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.direction != $1.direction { return $0.direction == .received }
            return $0.id < $1.id
        }
        for movement in ordered {
            guard movement.zatoshis > 0 else { throw LedgerError.invalidAmount }
            switch movement.direction {
            case .received:
                guard let price = movement.price else { throw LedgerError.missingPrice }
                guard price > 0, !price.isNaN else { throw LedgerError.invalidAmount }
                let sum = quantity.addingReportingOverflow(movement.zatoshis)
                guard !sum.overflow else { throw LedgerError.invalidAmount }
                quantity = sum.partialValue
                cost += movement.quantity * price
            case .sent:
                guard movement.zatoshis <= quantity else { throw LedgerError.inconsistentSelection }
                cost -= cost * Decimal(movement.zatoshis) / Decimal(quantity)
                quantity -= movement.zatoshis
                if quantity == 0 { cost = 0 }
            }
        }
        return LedgerResult(zatoshis: quantity, value: cost)
    }
}
