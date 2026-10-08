import Foundation

public enum MovementSnapshot {
    public static func reconcile(_ incoming: [Movement], previous: [Movement],
                                 choices: [String: ChoiceStore.Choice]) -> [Movement] {
        let known = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        return incoming.map { movement in
            var updated = movement
            if let choice = choices[movement.id] {
                updated.included = choice.included
                updated.price = choice.manualPrice ?? updated.price
            }
            if updated.price == nil, let existing = known[movement.id],
               HistoricalPriceService.day(existing.date) == HistoricalPriceService.day(movement.date) {
                updated.price = existing.price
            }
            return updated
        }
    }
}
