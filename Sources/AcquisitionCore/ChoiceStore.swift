import Foundation

public final class ChoiceStore {
    public struct Choice: Codable {
        public let included: Bool
        public let manualPrice: Decimal?
    }
    public private(set) var choices: [String: Choice]
    private let url: URL
    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            choices = try JSONDecoder().decode([String: Choice].self, from: Data(contentsOf: url))
        } else { choices = [:] }
    }
    public func set(id: String, included: Bool, manualPrice: Decimal?) throws {
        let old = choices
        choices[id] = Choice(included: included, manualPrice: manualPrice)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(choices).write(to: url, options: .atomic)
        } catch { choices = old; throw error }
    }
}
