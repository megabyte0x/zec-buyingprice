import Foundation
import AppKit
import Observation
import LocalAuthentication
import AcquisitionCore
import ZcashLightClientKit

@MainActor @Observable
final class WalletModel {
    var key = ""
    var birthday = Date(timeIntervalSince1970: 1_577_836_800)
    var heightOverride = ""
    var host = "zec.rocks"
    var port = "443"
    var apiKey = ""
    var proAPI = false
    var movements: [Movement] = []
    var status = "Connect a viewing-only wallet to begin."
    var error: String?
    var progress: Double = 0
    var scannedBlockCount: Int?
    var maxScannedHeight: Int?
    var fullyScannedHeight: Int?
    var chainTipHeight: Int?
    var interfaceLocked = true
    var authenticating = false
    var connected = false
    var busy = false
    var scanComplete = false
    var effectiveBirthday = 0
    var pricingFailures = 0
    var search = ""
    private var choosingNewWallet = false
    @ObservationIgnored private let vault: WalletVault
    @ObservationIgnored private let session: WalletSession
    @ObservationIgnored private let worker: WalletWorkerClient
    @ObservationIgnored private var lifecycle: WalletLifecycle?
    @ObservationIgnored private var context: LAContext?
    @ObservationIgnored private var activeToken: UUID?
    @ObservationIgnored private var nativeAuthenticationPending = false
    @ObservationIgnored private var interfaceAuthenticationToken: UUID?
    @ObservationIgnored private var interfaceAuthenticationContext: LAContext?
    @ObservationIgnored private var interfaceAuthenticationTask: Task<Void, Never>?
    @ObservationIgnored private var setupTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var walletDirectory: URL?
    @ObservationIgnored private var choices: ChoiceStore?
    @ObservationIgnored private var priceService: HistoricalPriceService?

    init(root: URL? = nil, sessionEligible: (() -> Bool)? = nil, unlockEligible: (() -> Bool)? = nil) {
        let eligible = sessionEligible ?? { WalletLifecycle.sessionEligible }
        let interactive = unlockEligible ?? { WalletLifecycle.unlockEligible }
        session = WalletSession(sessionEligible: eligible, unlockEligible: interactive)
        vault = WalletVault(root: root, sessionEligible: eligible)
        worker = WalletWorkerClient(runningSessionEligible: eligible)
        host = UserDefaults.standard.string(forKey: "host") ?? "zec.rocks"
        port = UserDefaults.standard.string(forKey: "port") ?? "443"
        proAPI = UserDefaults.standard.bool(forKey: "proAPI")
        if root == nil {
            do { apiKey = try KeychainStore.read(name: "price-api-key") ?? "" }
            catch { self.error = "The saved price API credential could not be loaded." }
            lifecycle = WalletLifecycle(onLock: { [weak self] in _ = self?.lock() },
                onLastWalletClose: { [weak self] in
                    if self?.lock() == true { NSApplication.shared.terminate(nil) }
                },
                onInterfaceLock: { [weak self] in self?.lockInterface() },
                nativeAuthenticationPending: { [weak self] in self?.nativeAuthenticationPending == true })
        }
        vault.onProtectionFailure = { [weak self] in
            if self?.lock() == true { self?.error = "Protected storage monitoring stopped. Unlock again to retry." }
        }
        worker.beforeConfigure = { [vault] pid in try vault.registerWorker(pid: pid) }
        worker.onEvent = { [weak self] event in self?.receive(event) }
        if vault.hasSavedWallet { status = "Wallet locked • authenticate to access your viewing key" }
    }

    var isLocked: Bool { !choosingNewWallet && (connected ? interfaceLocked : vault.hasSavedWallet) }
    private var authorized: Bool { connected && session.isUnlocked }
    private var interfaceAuthorized: Bool { authorized && !interfaceLocked }
    var visibleMovements: [Movement] {
        guard interfaceAuthorized else { return [] }
        return movements.filter { search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) ||
            $0.direction.rawValue.localizedCaseInsensitiveContains(search) }
            .sorted { $0.height == $1.height ? $0.id > $1.id : $0.height > $1.height }
    }
    var ledger: Result<LedgerResult, Error> { Result { try AcquisitionLedger.calculate(movements) } }
    var canDisplayAverage: Bool { interfaceAuthorized && scanComplete && !busy }
    var scanBlockSummary: String {
        var parts: [String] = []
        if let scannedBlockCount { parts.append("\(scannedBlockCount.formatted()) blocks scanned") }
        if let chainTipHeight { parts.append("Chain tip \(chainTipHeight.formatted())") }
        return parts.isEmpty ? "Waiting for block scan details…" : parts.joined(separator: " • ")
    }

    var scanHistorySummary: String? {
        guard let fullyScannedHeight else { return nil }
        var text = "History verified through block \(fullyScannedHeight.formatted())"
        if let maxScannedHeight { text += " • Highest scanned block \(maxScannedHeight.formatted())" }
        return text
    }

    static func number(_ value: Decimal?, digits: Int = 2) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = digits == 2 ? 2 : 0
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }

    func connect() {
        if connected { unlockInterface(); return }
        guard !busy, !authenticating else { return }
        error = nil
        let token: UUID
        do { token = try session.begin() }
        catch { self.error = "Open the wallet window in the foreground before unlocking."; return }
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty,
              let portNumber = Int(port), (1...65535).contains(portNumber) else {
            session.invalidate()
            error = "Enter a TLS lightwalletd host and valid port in Settings."; return
        }
        guard birthday <= Date() else {
            session.invalidate(); error = "The wallet birthday cannot be in the future."; return
        }
        let height = heightOverride.isEmpty ? BirthdayResolver.height(for: birthday) : Int(heightOverride)
        guard let height, height >= 419200, height <= Int(UInt32.max) else {
            session.invalidate()
            error = "Enter a mainnet birthday height at or after Sapling activation (419200)."; return
        }
        let input = isLocked ? nil : key.trimmingCharacters(in: .whitespacesAndNewlines)
        if let input, input.isEmpty {
            session.invalidate(); error = "Enter your mainnet viewing key."; return
        }
        let checkpoint = BirthdayResolver.checkpointHeight(for: height)
        let endpointHost = host
        let priceAPIKey = apiKey
        let pricePro = proAPI
        key = ""
        busy = true
        activeToken = token
        let authentication = LAContext()
        authentication.localizedCancelTitle = "Keep wallet locked"
        authentication.touchIDAuthenticationAllowableReuseDuration = 0
        context = authentication
        nativeAuthenticationPending = true
        authenticating = true
        status = "Authenticate with Touch ID or your Mac login password…"
        setupTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard try await authentication.evaluatePolicy(.deviceOwnerAuthentication,
                    localizedReason: "Unlock your viewing-only wallet and start mainnet syncing.") else {
                    throw WalletSession.Failure.locked
                }
                for _ in 0..<20 where !self.session.accepts(token) {
                    guard self.activeToken == token, WalletLifecycle.nativeAuthenticationIsForeground,
                          !Task.isCancelled else { throw WalletSession.Failure.locked }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                self.nativeAuthenticationPending = false
                guard self.session.accepts(token), !Task.isCancelled else { throw WalletSession.Failure.locked }
                if let input {
                    do { _ = try UnifiedFullViewingKey(encoding: input, network: .mainnet) }
                    catch { throw WalletScanner.Failure.invalidKey }
                }
                self.status = "Opening protected wallet storage…"
                let unlocked = try await self.vault.open(context: authentication, viewingKey: input,
                    birthday: checkpoint, isCurrent: { [weak self] in self?.session.accepts(token) == true })
                guard self.session.accepts(token), !Task.isCancelled else { throw WalletSession.Failure.locked }
                self.walletDirectory = unlocked.directory
                self.effectiveBirthday = unlocked.birthday
                self.choices = try ChoiceStore(url: unlocked.directory.appendingPathComponent("choices.json"))
                self.priceService = try HistoricalPriceService(cacheURL: unlocked.directory.appendingPathComponent("usd-prices.json"),
                    apiKey: priceAPIKey, pro: pricePro)
                try KeychainStore.save(priceAPIKey, name: "price-api-key")
                UserDefaults.standard.set(endpointHost, forKey: "host")
                UserDefaults.standard.set(String(portNumber), forKey: "port")
                UserDefaults.standard.set(pricePro, forKey: "proAPI")
                guard self.session.accepts(token) else { throw WalletSession.Failure.locked }
                try self.worker.start(key: unlocked.viewingKey, birthday: unlocked.birthday,
                    directory: unlocked.directory, host: endpointHost, port: portNumber)
                try self.session.complete(token)
                self.connected = true
                self.interfaceLocked = false
                self.authenticating = false
                self.context?.invalidate()
                self.context = nil
                self.choosingNewWallet = false
                self.busy = false
                self.setupTask = nil
                self.status = "Preparing wallet scan • syncing continues while the app is open"
            } catch {
                guard self.activeToken == token else { return }
                let message: String
                if let native = error as? LAError, [.userCancel, .appCancel, .systemCancel].contains(native.code) {
                    message = "Authentication cancelled. Your wallet remains locked."
                } else if error is WalletSession.Failure || error is CancellationError {
                    message = "The wallet session was locked. Unlock again from the foreground window."
                } else {
                    message = (error as? LocalizedError)?.errorDescription ?? "Wallet unlock failed. Your wallet remains locked."
                }
                if self.lock() { self.error = message }
            }
        }
    }

    private func receive(_ event: WalletWorkerEvent) {
        guard authorized else { _ = lock(); return }
        switch event.kind {
        case "syncing":
            scanComplete = false
            progress = min(1, max(0, event.progress ?? 0))
            updateScanMetrics(event)
            status = "Scanning mainnet"
        case "upToDate":
            scanComplete = true
            progress = 1
            updateScanMetrics(event)
            status = "Mainnet scan complete"
            refreshPrices()
        case "stopped":
            scanComplete = false
            status = "Scan paused • encrypted progress is saved"
        case "movements":
            guard let fetched = event.movements else { return }
            priceMovements(fetched)
        case "error":
            if lock() { error = "Wallet processing stopped. Unlock again to retry from saved progress." }
        default: break
        }
    }

    private func updateScanMetrics(_ event: WalletWorkerEvent) {
        scannedBlockCount = event.scannedBlockCount
        maxScannedHeight = event.maxScannedHeight
        fullyScannedHeight = event.scannedHeight
        chainTipHeight = event.tipHeight
    }

    func refreshPrices() {
        guard authorized, refreshTask == nil else { return }
        do { try worker.requestMovements() }
        catch { if lock() { self.error = "Wallet history is unavailable. Unlock again to retry." } }
    }

    private func priceMovements(_ incoming: [Movement]) {
        guard authorized, refreshTask == nil, let token = activeToken else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activeToken == token { self.busy = false; self.refreshTask = nil }
            }
            guard self.session.accepts(token) else { return }
            self.busy = true
            self.error = nil
            self.pricingFailures = 0
            var fetched = incoming
            for index in fetched.indices {
                if let choice = self.choices?.choices[fetched[index].id] {
                    fetched[index].included = choice.included
                    fetched[index].price = choice.manualPrice
                }
            }
            self.movements = fetched
            do {
                for index in fetched.indices {
                    try Task.checkCancellation()
                    guard self.session.accepts(token) else { throw CancellationError() }
                    self.status = "Fetching historical prices • \(index + 1) / \(fetched.count)"
                    if fetched[index].price == nil && fetched[index].confirmed {
                        do { fetched[index].price = try await self.priceService?.price(on: fetched[index].date) }
                        catch is CancellationError { throw CancellationError() }
                        catch {
                            guard self.session.accepts(token), !Task.isCancelled else { throw CancellationError() }
                            self.pricingFailures += 1
                        }
                    }
                    guard self.session.accepts(token), !Task.isCancelled else { throw CancellationError() }
                    if let currentIndex = self.movements.firstIndex(where: { $0.id == fetched[index].id }) {
                        self.movements[currentIndex].price = self.choices?.choices[fetched[index].id]?.manualPrice ?? fetched[index].price
                    }
                }
                guard self.session.accepts(token) else { return }
                self.status = self.pricingFailures == 0 ? "Synchronized • \(fetched.count) confirmed movements" :
                    "Synchronized • \(self.pricingFailures) historical prices unavailable"
            } catch is CancellationError {
                if self.session.accepts(token) { self.status = "Price retrieval paused" }
            } catch {
                if self.session.accepts(token) {
                    self.error = "Transaction history could not be classified completely. No complete average can be shown."
                    self.scanComplete = false
                }
            }
        }
    }

    func setIncluded(_ id: String, _ included: Bool) {
        guard interfaceAuthorized, let index = movements.firstIndex(where: { $0.id == id }) else { return }
        do {
            try choices?.set(id: id, included: included, manualPrice: choices?.choices[id]?.manualPrice)
            movements[index].included = included
        } catch { self.error = "The transaction selection could not be saved." }
    }

    func setManualPrice(_ id: String, text: String) {
        guard let index = movements.firstIndex(where: { $0.id == id }),
              let value = Decimal(string: text), value > 0, !value.isNaN else {
            error = "Enter a positive USD price."; return
        }
        guard interfaceAuthorized else { error = "Unlock your wallet before editing prices."; return }
        do {
            try choices?.set(id: id, included: movements[index].included, manualPrice: value)
            movements[index].price = value
        } catch { self.error = "The manual price could not be saved." }
    }

    func pause() {
        guard interfaceAuthorized else { return }
        worker.pause()
        refreshTask?.cancel()
    }

    func lockInterface() {
        guard connected else { _ = lock(); return }
        interfaceLocked = true
        search = ""
        error = nil
        cancelInterfaceAuthentication()
    }

    private func cancelInterfaceAuthentication() {
        interfaceAuthenticationToken = nil
        interfaceAuthenticationContext?.invalidate()
        interfaceAuthenticationContext = nil
        interfaceAuthenticationTask?.cancel()
        interfaceAuthenticationTask = nil
        nativeAuthenticationPending = false
        authenticating = false
    }

    private func unlockInterface() {
        guard authorized, WalletLifecycle.unlockEligible, !authenticating else { return }
        let token = UUID()
        let sessionToken = activeToken
        interfaceAuthenticationToken = token
        let authentication = LAContext()
        authentication.localizedCancelTitle = "Keep wallet locked"
        authentication.touchIDAuthenticationAllowableReuseDuration = 0
        interfaceAuthenticationContext = authentication
        nativeAuthenticationPending = true
        authenticating = true
        error = nil
        interfaceAuthenticationTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard try await authentication.evaluatePolicy(.deviceOwnerAuthentication,
                    localizedReason: "Unlock your wallet interface. Mainnet syncing can continue while it is locked.") else {
                    throw WalletSession.Failure.locked
                }
                for _ in 0..<20 where !WalletLifecycle.unlockEligible {
                    guard self.interfaceAuthenticationToken == token, WalletLifecycle.nativeAuthenticationIsForeground,
                          !Task.isCancelled else { throw WalletSession.Failure.locked }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                guard self.interfaceAuthenticationToken == token, self.activeToken == sessionToken,
                      self.authorized, WalletLifecycle.unlockEligible, !Task.isCancelled else {
                    throw WalletSession.Failure.locked
                }
                self.interfaceLocked = false
                self.cancelInterfaceAuthentication()
            } catch {
                guard self.interfaceAuthenticationToken == token else { return }
                self.cancelInterfaceAuthentication()
                self.error = "The wallet interface remains locked. Syncing continues while the app is open."
            }
        }
    }

    @discardableResult func lock() -> Bool {
        cancelInterfaceAuthentication()
        interfaceLocked = true
        session.invalidate()
        activeToken = nil
        context?.invalidate()
        context = nil
        nativeAuthenticationPending = false
        setupTask?.cancel()
        setupTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        worker.close()
        choices = nil
        priceService = nil
        walletDirectory = nil
        key = ""
        connected = false
        busy = false
        scanComplete = false
        movements = []
        progress = 0
        scannedBlockCount = nil
        maxScannedHeight = nil
        fullyScannedHeight = nil
        chainTipHeight = nil
        search = ""
        status = "Wallet locked • syncing stopped"
        do { try vault.lock(); return true }
        catch { self.error = error.localizedDescription; return false }
    }

    func disconnect() {
        if lock() {
            choosingNewWallet = true
            error = nil
            status = "Connect another viewing-only wallet."
        }
    }

    func resetLocalHistory() {
        guard interfaceAuthorized, let directory = walletDirectory else { return }
        worker.close()
        refreshTask?.cancel()
        refreshTask = nil
        busy = false
        do {
            let archive = directory.deletingLastPathComponent().appendingPathComponent("reset-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: directory, to: archive)
            _ = lock()
            status = "Encrypted history archived. Unlock to start a fresh scan."
        } catch {
            if lock() { self.error = "Local history could not be reset. Unlock and retry." }
        }
    }

    func resume() {
        guard interfaceAuthorized else { error = "Unlock your wallet before resuming."; return }
        do { try worker.resume() }
        catch { if lock() { self.error = "The scan could not resume. Unlock and retry." } }
    }
}
