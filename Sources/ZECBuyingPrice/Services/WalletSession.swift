import Foundation

@MainActor
final class WalletSession {
    enum Failure: Error { case locked }
    private let sessionEligible: () -> Bool
    private let unlockEligible: () -> Bool
    private var token: UUID?
    private var authenticated = false

    init(sessionEligible: @escaping () -> Bool, unlockEligible: @escaping () -> Bool) {
        self.sessionEligible = sessionEligible
        self.unlockEligible = unlockEligible
    }

    var isUnlocked: Bool { authenticated && token != nil && sessionEligible() }

    func begin() throws -> UUID {
        guard unlockEligible(), sessionEligible() else { throw Failure.locked }
        let next = UUID()
        token = next
        authenticated = false
        return next
    }

    func complete(_ candidate: UUID) throws {
        guard accepts(candidate) else { throw Failure.locked }
        authenticated = true
    }

    func accepts(_ candidate: UUID) -> Bool {
        token == candidate && sessionEligible() && (authenticated || unlockEligible())
    }

    func invalidate() {
        token = nil
        authenticated = false
    }
}
