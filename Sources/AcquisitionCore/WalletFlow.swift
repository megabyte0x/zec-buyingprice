import Foundation

public enum WalletFlow {
    public struct Output {
        public let amount: Int64
        public let fromOwned: Bool
        public let toOwned: Bool
        public let change: Bool
        public init(amount: Int64, fromOwned: Bool, toOwned: Bool, change: Bool) {
            self.amount = amount; self.fromOwned = fromOwned
            self.toOwned = toOwned; self.change = change
        }
    }
    public static func classify(_ outputs: [Output], balanceDelta: Int64, fee: Int64) throws -> (received: Int64, sent: Int64) {
        var received: Int64 = 0
        var sent: Int64 = 0
        for output in outputs where !output.change {
            guard output.amount >= 0 else { throw LedgerError.invalidAmount }
            if output.toOwned && !output.fromOwned {
                let sum = received.addingReportingOverflow(output.amount)
                guard !sum.overflow else { throw LedgerError.invalidAmount }
                received = sum.partialValue
            }
            if output.fromOwned && !output.toOwned {
                let sum = sent.addingReportingOverflow(output.amount)
                guard !sum.overflow else { throw LedgerError.invalidAmount }
                sent = sum.partialValue
            }
        }
        let delta = received.subtractingReportingOverflow(sent)
        let afterFee = delta.partialValue.subtractingReportingOverflow(fee)
        guard !delta.overflow, !afterFee.overflow, afterFee.partialValue == balanceDelta else {
            throw LedgerError.invalidAmount
        }
        return (received, sent)
    }
}
