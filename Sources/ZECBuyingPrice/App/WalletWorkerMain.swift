import Foundation
import AppKit
import CoreGraphics
import Darwin
import ZcashLightClientKit

@MainActor
enum WalletWorkerMain {
    private static var runtime: WalletWorkerRuntime?

    static func run() -> Never {
        let parent = getppid()
        let protocolOutput = dup(STDOUT_FILENO)
        guard protocolOutput >= 0, parent > 1 else { _exit(1) }
        guard fcntl(protocolOutput, F_SETFD, FD_CLOEXEC) == 0 else { _exit(1) }
        let null = open("/dev/null", O_WRONLY)
        guard null >= 0 else { _exit(1) }
        guard dup2(null, STDOUT_FILENO) == STDOUT_FILENO,
              dup2(null, STDERR_FILENO) == STDERR_FILENO else { _exit(1) }
        Darwin.close(null)
        let worker = WalletWorkerRuntime(parent: parent, output: protocolOutput)
        runtime = worker
        worker.run()
        RunLoop.main.run()
        _exit(0)
    }
}

@MainActor
private final class WalletWorkerRuntime {
    private let parent: pid_t
    private let scanner = WalletScanner()
    private let writer: WalletWorkerPipeWriter
    private var watchdog: DispatchSourceTimer?
    private var observers = [NSObjectProtocol]()
    private var commands = [WalletWorkerCommand]()
    private var operation: Task<Void, Never>?
    private var configured = false
    private var receivedConfiguration = false
    private var syncActivity: NSObjectProtocol?
    private var metricsTask: Task<Void, Never>?
    private var lastMetricsRead = Date.distantPast
    private var metricsPending = false
    private var cachedMetrics: WalletScanner.ScanMetrics?
    private var latestSyncEvent: WalletWorkerEvent?
    private var previousProgress: Double = 0
    private var previousScannedHeight: Int = 0

    init(parent: pid_t, output: Int32) {
        self.parent = parent
        do { writer = try WalletWorkerPipeWriter(descriptor: output) { _exit(0) } }
        catch { _exit(1) }
        Darwin.close(output)
    }

    private var parentSessionIsRunning: Bool {
        guard getppid() == parent, kill(parent, 0) == 0,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session[kCGSessionOnConsoleKey as String] as? Bool == true &&
            session[kCGSessionLoginDoneKey as String] as? Bool == true
    }

    func run() {
        guard parentSessionIsRunning else { _exit(0) }
        scanner.onState = { [weak self] state in self?.receive(state) }
        scanner.onTransactionsChanged = { [weak self] in
            guard let self, self.configured else { return }
            self.enqueue(WalletWorkerCommand(kind: "movements"))
        }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self, parent] in
            guard getppid() == parent, kill(parent, 0) == 0 else { _exit(0) }
            DispatchQueue.main.async {
                guard self?.parentSessionIsRunning == true else { _exit(0) }
            }
        }
        watchdog = timer
        timer.resume()
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: nil) { _ in _exit(0) })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: nil) { _ in _exit(0) })
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var decoder = WalletWorkerFrameDecoder()
            var bytes = [UInt8](repeating: 0, count: 8192)
            do {
                while true {
                    let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { _exit(0) }
                    for frame in try decoder.append(Data(bytes.prefix(count))) {
                        let command = try JSONDecoder().decode(WalletWorkerCommand.self, from: frame)
                        try command.validate()
                        DispatchQueue.main.async { self?.enqueue(command) }
                    }
                }
            } catch { _exit(1) }
        }
    }

    private func enqueue(_ command: WalletWorkerCommand) {
        guard parentSessionIsRunning else { _exit(0) }
        if command.kind == "movements", commands.contains(where: { $0.kind == "movements" }) { return }
        guard commands.count < 32 else { _exit(0) }
        if command.kind == "configure" {
            guard !receivedConfiguration else { _exit(1) }
            receivedConfiguration = true
        } else if !receivedConfiguration { _exit(1) }
        commands.append(command)
        guard operation == nil else { return }
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.operation = nil }
            while !self.commands.isEmpty {
                guard self.parentSessionIsRunning else { _exit(0) }
                let command = self.commands.removeFirst()
                do { try await self.perform(command) }
                catch {
                    self.setSyncActivity(false)
                    self.emit(WalletWorkerEvent(kind: "error"))
                    if command.kind == "configure" { _exit(1) }
                }
            }
        }
    }

    private func perform(_ command: WalletWorkerCommand) async throws {
        guard parentSessionIsRunning else { _exit(0) }
        switch command.kind {
        case "configure":
            guard let key = command.key, let birthday = command.birthday,
                  let directory = command.directory, let host = command.host, let port = command.port else {
                throw WalletWorkerFailure.invalidProtocol
            }
            setSyncActivity(true)
            try await scanner.configure(key: key, birthday: birthday,
                directory: URL(fileURLWithPath: directory), host: host, port: port)
            guard parentSessionIsRunning else { _exit(0) }
            configured = true
            enqueue(WalletWorkerCommand(kind: "movements"))
            setSyncActivity(true)
            try await scanner.start()
        case "pause":
            guard configured else { throw WalletWorkerFailure.invalidProtocol }
            scanner.pause()
            setSyncActivity(false)
        case "resume":
            guard configured else { throw WalletWorkerFailure.invalidProtocol }
            setSyncActivity(true)
            try await scanner.start()
        case "movements":
            guard configured else { throw WalletWorkerFailure.invalidProtocol }
            let snapshot = try await scanner.movements()
            guard parentSessionIsRunning else { _exit(0) }
            emit(WalletWorkerEvent(kind: "movements", movements: snapshot.movements,
                incompleteTransactionCount: snapshot.incompleteTransactionCount))
        default: throw WalletWorkerFailure.invalidProtocol
        }
    }

    private func receive(_ state: SynchronizerState) {
        guard parentSessionIsRunning else { _exit(0) }
        var event: WalletWorkerEvent
        switch state.syncStatus {
        case .syncing(let progress, _):
            setSyncActivity(true)
            event = WalletWorkerEvent(kind: "syncing", progress: Double(progress),
                scannedHeight: state.fullyScannedHeight, tipHeight: state.latestBlockHeight)
        case .upToDate:
            setSyncActivity(false)
            event = WalletWorkerEvent(kind: "upToDate", progress: 1,
                scannedHeight: state.fullyScannedHeight, tipHeight: state.latestBlockHeight)
        case .stopped:
            setSyncActivity(false)
            event = WalletWorkerEvent(kind: "stopped")
        case .error:
            setSyncActivity(false)
            event = WalletWorkerEvent(kind: "error")
        case .unprepared: return
        }
        event.scannedBlockCount = cachedMetrics?.scannedBlockCount
        event.maxScannedHeight = cachedMetrics?.maxScannedHeight
        latestSyncEvent = event
        emit(event)
        guard configured else { return }
        if event.kind == "upToDate" || event.kind == "stopped" ||
            (event.kind == "syncing" && ((event.progress ?? 0) < previousProgress ||
                (event.scannedHeight ?? 0) < previousScannedHeight)) {
            enqueue(WalletWorkerCommand(kind: "movements"))
        }
        if event.kind == "syncing" || event.kind == "upToDate" {
            previousProgress = event.progress ?? 0
            previousScannedHeight = event.scannedHeight ?? 0
            refreshMetrics(force: event.kind == "upToDate")
        }
    }

    private func refreshMetrics(force: Bool) {
        if metricsTask != nil {
            if force { metricsPending = true }
            return
        }
        guard force || Date().timeIntervalSince(lastMetricsRead) >= 1 else { return }
        lastMetricsRead = Date()
        metricsTask = Task { [weak self] in
            guard let self else { return }
            self.cachedMetrics = try? await self.scanner.scanMetrics()
            guard self.parentSessionIsRunning else { _exit(0) }
            if var event = self.latestSyncEvent, event.kind == "syncing" || event.kind == "upToDate" {
                event.scannedBlockCount = self.cachedMetrics?.scannedBlockCount
                event.maxScannedHeight = self.cachedMetrics?.maxScannedHeight
                self.emit(event)
            }
            self.metricsTask = nil
            if self.metricsPending {
                self.metricsPending = false
                self.refreshMetrics(force: true)
            }
        }
    }

    private func setSyncActivity(_ active: Bool) {
        if active, syncActivity == nil {
            syncActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Synchronizing the viewing-only wallet session")
        } else if !active, let activity = syncActivity {
            ProcessInfo.processInfo.endActivity(activity)
            syncActivity = nil
        }
    }

    private func emit(_ event: WalletWorkerEvent) {
        do { try writer.enqueue(WalletWorkerFrameDecoder.encode(event)) }
        catch { _exit(1) }
    }
}
