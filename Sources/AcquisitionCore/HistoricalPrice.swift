import Foundation

public enum PriceError: Error, LocalizedError {
    case unavailable, requestFailed(Int)
    public var errorDescription: String? {
        switch self {
        case .unavailable: "No positive historical USD price is available for this date."
        case .requestFailed(let code): "Historical price request failed (HTTP \(code)). Check API credentials and historical coverage."
        }
    }
}

public actor HistoricalPriceService {
    private struct Response: Decodable {
        struct Market: Decodable { let current_price: [String: Decimal] }
        let market_data: Market?
    }
    private var cache: [String: Decimal]
    private let url: URL
    private let apiKey: String
    private let pro: Bool
    private var lastRequest = Date.distantPast

    public init(cacheURL: URL, apiKey: String = "", pro: Bool = false) throws {
        url = cacheURL
        self.apiKey = apiKey
        self.pro = pro
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            cache = try JSONDecoder().decode([String: Decimal].self, from: Data(contentsOf: cacheURL))
        } else { cache = [:] }
    }

    public nonisolated static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter.string(from: date)
    }

    public nonisolated static func decode(_ data: Data) throws -> Decimal {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let price = response.market_data?.current_price["usd"], price > 0, !price.isNaN else {
            throw PriceError.unavailable
        }
        return price
    }

    public func price(on date: Date) async throws -> Decimal {
        let day = Self.day(date)
        if let cached = cache[day] { return cached }
        let delay = max(0, 2 - Date().timeIntervalSince(lastRequest))
        try await Task.sleep(for: .seconds(delay))
        let host = pro ? "pro-api.coingecko.com" : "api.coingecko.com"
        var components = URLComponents(string: "https://\(host)/api/v3/coins/zcash/history")!
        components.queryItems = [URLQueryItem(name: "date", value: day), URLQueryItem(name: "localization", value: "false")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: pro ? "x-cg-pro-api-key" : "x-cg-demo-api-key")
        }
        for attempt in 0..<3 {
            try Task.checkCancellation()
            lastRequest = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 || status >= 500 {
                if attempt < 2 { try await Task.sleep(for: .seconds(5 * (attempt + 1))); continue }
            }
            guard status == 200 else { throw PriceError.requestFailed(status) }
            let price = try Self.decode(data)
            cache[day] = price
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: url, options: .atomic)
            return price
        }
        throw PriceError.unavailable
    }
}
