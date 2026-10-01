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
    var synchronizer: SDKSynchronizer?
    private var observation: AnyCancellable?
    private var databaseURL: URL?
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
        databaseURL = directory.appendingPathComponent("wallet.db")
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
        databaseURL = nil
    }

    func movements() async throws -> [Movement] {
        guard let sync = synchronizer, let databaseURL else { return [] }
        let database = try Connection(databaseURL.path, readonly: true)
        var result: [Movement] = []
        for transaction in await sync.transactions {
            if transaction.state == .expired { continue }
            let confirmed = transaction.state == .confirmed
            if confirmed && (transaction.minedHeight == nil || transaction.blockTime == nil) {
                throw Failure.unavailableHistory
            }
            guard let time = transaction.blockTime else { continue }
            let height = transaction.minedHeight ?? Int.max
            if transaction.isShielding || transaction.poolCrossingValue != nil { continue }
            let rows = try database.prepare("SELECT value, from_account_uuid, to_account_uuid, is_change FROM v_tx_outputs WHERE txid = ?",
                Blob(bytes: Array(transaction.rawID)))
            let account = transaction.accountUUID.id
            let outputs = try rows.map { row -> WalletFlow.Output in
                guard let amount = row[0] as? Int64, let change = row[3] as? Int64 else {
                    throw Failure.unavailableHistory
                }
                return WalletFlow.Output(amount: amount,
                    fromOwned: (row[1] as? Blob)?.bytes == account,
                    toOwned: (row[2] as? Blob)?.bytes == account, change: change != 0)
            }
            let fee = transaction.fee?.amount ?? 0
            let flow = try WalletFlow.classify(outputs, balanceDelta: transaction.value.amount, fee: fee)
            let txid = transaction.rawID.map { String(format: "%02x", $0) }.joined()
            let amounts: [(Movement.Direction, Int64)] = [(.received, flow.received), (.sent, flow.sent)]
            for (direction, amount) in amounts where amount > 0 {
                result.append(Movement(id: "\(txid):\(direction.rawValue)", date: Date(timeIntervalSince1970: time),
                    height: height, zatoshis: amount, direction: direction,
                    confirmed: confirmed, transactionIndex: transaction.index ?? 0, feeZatoshis: transaction.fee?.amount))
            }
        }
        return result
    }
}
