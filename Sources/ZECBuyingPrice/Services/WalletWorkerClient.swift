import Foundation
import Darwin

@MainActor
final class WalletWorkerClient {
    var onEvent: ((WalletWorkerEvent) -> Void)?
    var beforeConfigure: ((Int32) throws -> Void)?
    var processIdentifier: pid_t? { process?.processIdentifier }
    private let executableURL: URL?
    private let runningSessionEligible: @MainActor () -> Bool
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var writer: WalletWorkerPipeWriter?
    private var generation = UUID()

    init(executableURL: URL? = nil, runningSessionEligible: @escaping @MainActor () -> Bool = { WalletLifecycle.sessionEligible }) {
        self.executableURL = executableURL ?? Bundle.main.executableURL
        self.runningSessionEligible = runningSessionEligible
    }

    deinit {
        writer?.close()
        process?.terminationHandler = nil
        if let process {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        try? input?.fileHandleForWriting.close()
        try? output?.fileHandleForReading.close()
    }

    func start(key: String, birthday: Int, directory: URL, host: String, port: Int) throws {
        guard runningSessionEligible() else { throw WalletWorkerFailure.sessionRequired }
        close()
        guard let executableURL else { throw WalletWorkerFailure.unavailable }
        let command = WalletWorkerCommand(kind: "configure", key: key, birthday: birthday,
            directory: directory.path, host: host, port: port)
        try command.validate()
        let frame = try WalletWorkerFrameDecoder.encode(command)
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["--wallet-worker"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let token = UUID()
        generation = token
        do {
            try process.run()
            try input.fileHandleForReading.close()
            try output.fileHandleForWriting.close()
            self.process = process
            self.input = input
            self.output = output
            let writer = try WalletWorkerPipeWriter(descriptor: input.fileHandleForWriting.fileDescriptor) { [weak self] in
                DispatchQueue.main.async { self?.failed(token: token) }
            }
            self.writer = writer
            guard runningSessionEligible() else {
                close()
                throw WalletWorkerFailure.sessionRequired
            }
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async { self?.failed(token: token) }
            }
            beginReading(output.fileHandleForReading.fileDescriptor, token: token)
            try beforeConfigure?(process.processIdentifier)
            guard self.process === process, generation == token, runningSessionEligible() else {
                close()
                throw WalletWorkerFailure.sessionRequired
            }
            try writer.enqueue(frame)
        } catch {
            if self.process === process { close() }
            else if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            if error is WalletWorkerFailure { throw error }
            throw WalletWorkerFailure.unavailable
        }
    }

    func pause() {
        do { try send(WalletWorkerCommand(kind: "pause")) }
        catch { if process != nil { failed(token: generation) } }
    }

    func resume() throws { try send(WalletWorkerCommand(kind: "resume")) }
    func requestMovements() throws { try send(WalletWorkerCommand(kind: "movements")) }

    func close() {
        generation = UUID()
        let child = process
        process = nil
        child?.terminationHandler = nil
        writer?.close()
        writer = nil
        if let child {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
        try? input?.fileHandleForWriting.close()
        try? output?.fileHandleForReading.close()
        input = nil
        output = nil
    }

    private func send(_ command: WalletWorkerCommand) throws {
        guard runningSessionEligible() else {
            close()
            throw WalletWorkerFailure.sessionRequired
        }
        guard let process, process.isRunning, let writer else { throw WalletWorkerFailure.unavailable }
        try writer.enqueue(WalletWorkerFrameDecoder.encode(command))
    }

    private func beginReading(_ descriptor: Int32, token: UUID) {
        let owned = dup(descriptor)
        guard owned >= 0 else { failed(token: token); return }
        guard fcntl(owned, F_SETFD, FD_CLOEXEC) == 0 else {
            Darwin.close(owned)
            failed(token: token)
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { Darwin.close(owned) }
            var decoder = WalletWorkerFrameDecoder()
            var bytes = [UInt8](repeating: 0, count: 8192)
            do {
                while true {
                    let count = Darwin.read(owned, &bytes, bytes.count)
                    if count < 0 && errno == EINTR { continue }
                    guard count >= 0 else { throw WalletWorkerFailure.unavailable }
                    if count == 0 {
                        try decoder.finish()
                        break
                    }
                    for frame in try decoder.append(Data(bytes.prefix(count))) {
                        let event = try JSONDecoder().decode(WalletWorkerEvent.self, from: frame)
                        try event.validate()
                        DispatchQueue.main.async {
                            guard let self, self.generation == token, self.process != nil else { return }
                            guard self.runningSessionEligible() else { self.failed(token: token); return }
                            self.onEvent?(event)
                        }
                    }
                }
            } catch {}
            DispatchQueue.main.async { self?.failed(token: token) }
        }
    }

    private func failed(token: UUID) {
        guard generation == token, process != nil else { return }
        close()
        onEvent?(WalletWorkerEvent(kind: "error"))
    }
}

final class WalletWorkerPipeWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "wallet-worker.input")
    private var descriptor: Int32
    private var pending = [Data]()
    private var offset = 0
    private var scheduled = false
    private let onFailure: () -> Void

    init(descriptor: Int32, onFailure: @escaping () -> Void) throws {
        self.descriptor = dup(descriptor)
        self.onFailure = onFailure
        guard self.descriptor >= 0 else { throw WalletWorkerFailure.unavailable }
        guard fcntl(self.descriptor, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(self.descriptor, F_SETFL, fcntl(self.descriptor, F_GETFL) | O_NONBLOCK) == 0,
              fcntl(self.descriptor, F_SETNOSIGPIPE, 1) == 0 else {
            Darwin.close(self.descriptor)
            self.descriptor = -1
            throw WalletWorkerFailure.unavailable
        }
    }

    func enqueue(_ frame: Data) throws {
        lock.lock()
        guard descriptor >= 0, pending.reduce(0, { $0 + $1.count }) + frame.count <= 8 * 1024 * 1024 else {
            lock.unlock()
            throw WalletWorkerFailure.unavailable
        }
        pending.append(frame)
        let shouldSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if shouldSchedule { queue.async { self.drain() } }
    }

    func close() {
        lock.lock()
        if descriptor >= 0 { Darwin.close(descriptor) }
        descriptor = -1
        pending.removeAll()
        offset = 0
        lock.unlock()
    }

    private func drain() {
        lock.lock()
        guard descriptor >= 0, let frame = pending.first else {
            scheduled = false
            lock.unlock()
            return
        }
        let remaining = frame.count - offset
        let written = frame.withUnsafeBytes { buffer in
            Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), remaining)
        }
        let code = errno
        if written > 0 {
            offset += written
            if offset == frame.count { pending.removeFirst(); offset = 0 }
        }
        let failed = written < 0 && code != EAGAIN && code != EWOULDBLOCK && code != EINTR
        lock.unlock()
        if failed { close(); onFailure(); return }
        if written < 0 {
            queue.asyncAfter(deadline: .now() + .milliseconds(10)) { self.drain() }
        } else { queue.async { self.drain() } }
    }

    deinit { close() }
}
