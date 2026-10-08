import Foundation
import AcquisitionCore

struct WalletWorkerEvent: Codable, Sendable {
    let kind: String
    var progress: Double? = nil
    var scannedHeight: Int? = nil
    var tipHeight: Int? = nil
    var scannedBlockCount: Int? = nil
    var maxScannedHeight: Int? = nil
    var movements: [Movement]? = nil

    func validate() throws {
        guard ["syncing", "upToDate", "stopped", "movements", "error"].contains(kind),
              progress.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              scannedHeight.map({ $0 >= 0 }) ?? true,
              tipHeight.map({ $0 >= 0 }) ?? true,
              scannedBlockCount.map({ $0 >= 0 && $0 <= Int(UInt32.max) }) ?? true,
              maxScannedHeight.map({ $0 >= 0 && $0 <= Int(UInt32.max) }) ?? true,
              kind != "movements" || movements != nil else {
            throw WalletWorkerFailure.invalidProtocol
        }
    }
}

enum WalletWorkerFailure: Error, LocalizedError {
    case sessionRequired, unavailable, invalidProtocol

    var errorDescription: String? {
        switch self {
        case .sessionRequired: "Unlock the wallet before starting or resuming synchronization."
        case .unavailable: "The wallet worker is unavailable. Unlock the wallet again to retry."
        case .invalidProtocol: "The wallet worker returned an invalid response. Unlock the wallet again to retry."
        }
    }
}

struct WalletWorkerCommand: Codable, Sendable {
    let kind: String
    var key: String? = nil
    var birthday: Int? = nil
    var directory: String? = nil
    var host: String? = nil
    var port: Int? = nil

    func validate() throws {
        switch kind {
        case "configure":
            guard let key, !key.isEmpty, key.utf8.count <= 8192,
                  let birthday, birthday >= 419200, birthday <= Int(UInt32.max),
                  let directory, directory.hasPrefix("/"), directory.utf8.count <= 4096,
                  let host, !host.isEmpty, host.utf8.count <= 1024,
                  let port, (1...65535).contains(port) else {
                throw WalletWorkerFailure.invalidProtocol
            }
        case "pause", "resume", "movements":
            guard key == nil, birthday == nil, directory == nil, host == nil, port == nil else {
                throw WalletWorkerFailure.invalidProtocol
            }
        default: throw WalletWorkerFailure.invalidProtocol
        }
    }
}

struct WalletWorkerFrameDecoder {
    static let maximumFrameSize = 4 * 1024 * 1024
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames = [Data]()
        while buffer.count >= 4 {
            let count = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard count > 0, count <= Self.maximumFrameSize else {
                throw WalletWorkerFailure.invalidProtocol
            }
            guard buffer.count >= 4 + count else { break }
            frames.append(Data(buffer.dropFirst(4).prefix(count)))
            buffer.removeFirst(4 + count)
        }
        guard buffer.count <= Self.maximumFrameSize + 4 else {
            throw WalletWorkerFailure.invalidProtocol
        }
        return frames
    }

    func finish() throws {
        guard buffer.isEmpty else { throw WalletWorkerFailure.invalidProtocol }
    }

    static func encode<T: Encodable>(_ message: T) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        guard !payload.isEmpty, payload.count <= maximumFrameSize else {
            throw WalletWorkerFailure.invalidProtocol
        }
        let size = UInt32(payload.count)
        var frame = Data([UInt8((size >> 24) & 255), UInt8((size >> 16) & 255),
                          UInt8((size >> 8) & 255), UInt8(size & 255)])
        frame.append(payload)
        return frame
    }
}
