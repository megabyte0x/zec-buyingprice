import Foundation
import Combine
import AcquisitionCore
import ZcashLightClientKit
import SQLite

@MainActor
final class WalletScanner {
    enum Failure: Error, LocalizedError {
        case invalidKey, unavailableHistory
        var errorDescription: String? {
            switch self {
            case .invalidKey: "Enter a valid mainnet Unified Full Viewing Key."
            case .unavailableHistory: "Some transaction outputs cannot be classified reliably. The complete acquisition average is unavailable."
            }
        }
    }
    struct ScanMetrics {
        let scannedBlockCount: Int
        let maxScannedHeight: Int?
    }

    var synchronizer: SDKSynchronizer?
    private var observation: AnyCancellable?
    private var historyReader: WalletHistoryReader?
    private var transactionObservation: AnyCancellable?
    var onTransactionsChanged: (() -> Void)?
    var onState: ((SynchronizerState) -> Void)?

    func configure(key: String, birthday: Int, directory: URL, host: String, port: Int) async throws {
        let validated: UnifiedFullViewingKey
        do { validated = try UnifiedFullViewingKey(encoding: key, network: .mainnet) }
        catch { throw Failure.invalidKey }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let initializer = Initializer(cacheDbURL: nil,
            fsBlockDbRoot: directory.appendingPathComponent("blocks"),
            generalStorageURL: directory.appendingPathComponent("storage"),
            dataDbURL: directory.appendingPathComponent("wallet.db"),
            torDirURL: directory.appendingPathComponent("tor"),
            endpoint: LightWalletEndpoint(address: host, port: port, secure: true),
            network: ZcashNetworkBuilder.network(for: .mainnet),
            spendParamsURL: directory.appendingPathComponent("sapling-spend.params"),
            outputParamsURL: directory.appendingPathComponent("sapling-output.params"),
            saplingParamsSourceURL: .default, loggingPolicy: .noLogging,
            isTorEnabled: false, isExchangeRateEnabled: false)
        let sync = SDKSynchronizer(initializer: initializer)
        guard try await sync.prepare(with: nil, walletBirthday: birthday, name: "Acquisition account", keySource: nil) == .success else {
            throw Failure.unavailableHistory
        }
        if try await sync.listAccounts().isEmpty {
            _ = try await sync.importAccount(ufvk: validated.stringEncoded, seedFingerprint: nil,
                zip32AccountIndex: nil, purpose: .viewOnly, name: "Acquisition account", keySource: nil, birthday: birthday)
        }
        synchronizer = sync
        historyReader = try WalletHistoryReader(databaseURL: directory.appendingPathComponent("wallet.db"), birthday: birthday)
        transactionObservation = sync.eventStream.receive(on: DispatchQueue.main).sink { [weak self] event in
            switch event {
            case .foundTransactions, .minedTransaction, .storedUTXOs:
                self?.onTransactionsChanged?()
            case .connectionStateChanged: break
            }
        }
        observation = sync.stateStream.receive(on: DispatchQueue.main).sink { [weak self] state in
            self?.onState?(state)
        }
    }
    func start() async throws { try await synchronizer?.start(retry: true) }
    func pause() { synchronizer?.stop() }
    func close() {
        pause()
        observation?.cancel()
        observation = nil
        synchronizer = nil
        transactionObservation?.cancel()
        transactionObservation = nil
        historyReader = nil
    }

    func scanMetrics() async throws -> ScanMetrics? {
        try await historyReader?.scanMetrics()
    }

    func movements() async throws -> WalletHistorySnapshot {
        guard let sync = synchronizer, let historyReader else {
            return WalletHistorySnapshot(movements: [], incompleteTransactionCount: 0)
        }
        return try await historyReader.movements(transactions: sync.allTransactions())
    }
}

struct WalletHistorySnapshot: Sendable {
    let movements: [Movement]
    let incompleteTransactionCount: Int
}

private actor WalletHistoryReader {
    private let database: Connection
    private let walletBirthday: Int
    private let outputs: Statement

    init(databaseURL: URL, birthday: Int) throws {
        database = try Connection(databaseURL.path, readonly: true)
        database.busyTimeout = 1
        walletBirthday = birthday
        outputs = try database.prepare("SELECT value, from_account_uuid, to_account_uuid, is_change FROM v_tx_outputs WHERE txid = ?")
    }

    func scanMetrics() throws -> WalletScanner.ScanMetrics {
        // The pinned Rust SDK stores nonoverlapping, end-exclusive scan ranges;
        // priority 10 means Scanned. Requeued ranges no longer count as complete.
        let statement = try database.prepare("""
            SELECT COALESCE(SUM(block_range_end - MAX(block_range_start, ?)), 0),
                   (SELECT MAX(height) FROM blocks WHERE height >= ?)
            FROM scan_queue
            WHERE priority = 10 AND block_range_end > ?
            """, Int64(walletBirthday), Int64(walletBirthday), Int64(walletBirthday))
        guard let row = try statement.failableNext(), let count = row[0] as? Int64,
              count >= 0, count <= Int64(UInt32.max) else {
            throw WalletScanner.Failure.unavailableHistory
        }
        let maximum = row[1] as? Int64
        guard maximum.map({ $0 >= 0 && $0 <= Int64(UInt32.max) }) ?? true else {
            throw WalletScanner.Failure.unavailableHistory
        }
        return WalletScanner.ScanMetrics(scannedBlockCount: Int(count), maxScannedHeight: maximum.map(Int.init))
    }

    func movements(transactions: [ZcashTransaction.Overview]) throws -> WalletHistorySnapshot {
        var result: [Movement] = []
        var incomplete = 0
        // Keep every output read in this snapshot consistent while the SDK writes new batches.
        try database.transaction(.deferred) {
            for transaction in transactions {
                if transaction.state == .expired { continue }
                if transaction.isShielding || transaction.poolCrossingValue != nil { continue }
                let confirmed = transaction.state == .confirmed
                guard let time = transaction.blockTime, !confirmed || transaction.minedHeight != nil else {
                    if confirmed { incomplete += 1 }
                    continue
                }
                let account = transaction.accountUUID.id
                _ = outputs.bind(Blob(bytes: Array(transaction.rawID)))
                var classifiedOutputs: [WalletFlow.Output] = []
                while let row = try outputs.failableNext() {
                    guard let amount = row[0] as? Int64, let change = row[3] as? Int64 else {
                        throw WalletScanner.Failure.unavailableHistory
                    }
                    classifiedOutputs.append(WalletFlow.Output(amount: amount,
                        fromOwned: (row[1] as? Blob)?.bytes == account,
                        toOwned: (row[2] as? Blob)?.bytes == account, change: change != 0))
                }
                let flow: (received: Int64, sent: Int64)
                do {
                    flow = try WalletFlow.classify(classifiedOutputs,
                        balanceDelta: transaction.value.amount, fee: transaction.fee?.amount ?? 0)
                } catch {
                    // Enhancement may still be filling in this transaction's outputs.
                    incomplete += 1
                    continue
                }
                let txid = transaction.rawID.map { String(format: "%02x", $0) }.joined()
                let amounts: [(Movement.Direction, Int64)] = [(.received, flow.received), (.sent, flow.sent)]
                for (direction, amount) in amounts where amount > 0 {
                    result.append(Movement(id: "\(txid):\(direction.rawValue)", date: Date(timeIntervalSince1970: time),
                        height: transaction.minedHeight ?? Int.max, zatoshis: amount, direction: direction,
                        confirmed: confirmed, transactionIndex: transaction.index ?? 0, feeZatoshis: transaction.fee?.amount))
                }
            }
        }
        return WalletHistorySnapshot(movements: result, incompleteTransactionCount: incomplete)
    }
}
