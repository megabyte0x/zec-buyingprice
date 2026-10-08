import Darwin
import Foundation

struct VaultGuardCommand: Codable {
    let kind: String
    let pid: Int32?
}

@MainActor
final class VaultGuard {
    private let image: URL
    private let mountRoot: URL
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var finishing = false
    var onFailure: (() -> Void)?
    var isProtecting: Bool { process?.isRunning == true }

    init(image: URL, mountRoot: URL) {
        self.image = image
        self.mountRoot = mountRoot
    }

    func start() throws {
        if let process, process.isRunning { return }
        guard let executable = Bundle.main.executableURL else { throw WalletVault.Failure.unavailable }
        let child = Process()
        let commands = Pipe()
        let replies = Pipe()
        child.executableURL = executable
        child.arguments = ["--vault-guard", image.path, mountRoot.path]
        child.standardInput = commands
        child.standardOutput = replies
        child.standardError = FileHandle.nullDevice
        guard fcntl(commands.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0,
            fcntl(replies.fileHandleForReading.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0,
            fcntl(commands.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw WalletVault.Failure.unavailable
        }
        child.terminationHandler = { [weak self] stopped in
            Task { @MainActor in
                guard let self, self.process === stopped, !self.finishing else { return }
                self.onFailure?()
            }
        }
        try child.run()
        process = child
        input = commands.fileHandleForWriting
        output = replies.fileHandleForReading
        do { try receiveAcknowledgement() }
        catch {
            try? input?.close()
            if child.isRunning { child.terminate() }
            try? waitForExit(child)
            process = nil
            input = nil
            output = nil
            throw WalletVault.Failure.unavailable
        }
    }

    func registerWorker(pid: Int32) throws { try send(VaultGuardCommand(kind: "worker", pid: pid)) }
    func registerCommand(pid: Int32) throws { try send(VaultGuardCommand(kind: "command", pid: pid)) }

    func withRecoveryLease(_ operation: () throws -> Void) throws {
        if process?.isRunning == true { try operation(); return }
        let directory = image.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path) else { try operation(); return }
        let descriptor = Darwin.open(directory.appendingPathComponent("guard.lock").path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw WalletVault.Failure.unavailable }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw WalletVault.Failure.alreadyOpen }
        try operation()
    }

    func finish() throws {
        guard let process else { return }
        finishing = true
        process.terminationHandler = nil
        defer { finishing = false }
        if !process.isRunning {
            try? input?.close()
            try? output?.close()
            self.process = nil
            input = nil
            output = nil
            return
        }
        try send(VaultGuardCommand(kind: "finish", pid: nil))
        try input?.close()
        try waitForExit(process)
        guard process.terminationStatus == 0 else { throw WalletVault.Failure.detach }
        try output?.close()
        self.process = nil
        input = nil
        output = nil
    }

    private func waitForExit(_ child: Process) throws {
        let deadline = Date().addingTimeInterval(5)
        while child.isRunning {
            guard Date() < deadline else {
                kill(child.processIdentifier, SIGKILL)
                throw WalletVault.Failure.unavailable
            }
            usleep(10_000)
        }
        child.waitUntilExit()
    }

    private func send(_ command: VaultGuardCommand) throws {
        guard let process, process.isRunning, let input else { throw WalletVault.Failure.unavailable }
        try input.write(contentsOf: JSONEncoder().encode(command) + Data([10]))
        try receiveAcknowledgement()
    }

    private func receiveAcknowledgement() throws {
        guard let output else { throw WalletVault.Failure.unavailable }
        var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
        guard poll(&descriptor, 1, 5_000) > 0,
            try output.read(upToCount: 2) == Data([49, 10]) else { throw WalletVault.Failure.unavailable }
    }

    deinit { try? input?.close() }
}
