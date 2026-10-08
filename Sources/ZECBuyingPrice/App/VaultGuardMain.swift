import Darwin
import Foundation

@MainActor
enum VaultGuardMain {
    private struct Registration {
        let pid: Int32
        let worker: Bool
        let seconds: Int
        let microseconds: Int
        let events: Int32
    }

    static func run() -> Never {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, arguments[1] == "--vault-guard", getppid() > 1 else { _exit(1) }
        let image = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        let mountRoot = URL(fileURLWithPath: arguments[3]).standardizedFileURL
        guard image.lastPathComponent == "wallet.sparseimage", mountRoot.lastPathComponent == "mounts",
            image.deletingLastPathComponent() == mountRoot.deletingLastPathComponent() else { _exit(1) }
        let lock = Darwin.open(image.deletingLastPathComponent().appendingPathComponent("guard.lock").path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { _exit(1) }
        signal(SIGPIPE, SIG_IGN)
        let parent = getppid()
        var registrations: [Registration] = []
        let ready = acknowledge()
        while ready && getppid() == parent {
            guard let line = readLineBytes() else { break }
            do {
                let command = try JSONDecoder().decode(VaultGuardCommand.self, from: line)
                if command.kind == "finish", command.pid == nil {
                    _ = acknowledge()
                    _exit(0)
                }
                guard ["worker", "command"].contains(command.kind), let pid = command.pid,
                    let information = processInformation(pid), information.kp_eproc.e_ppid == parent else { break }
                let events = kqueue()
                guard events >= 0 else { break }
                var event = kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ENABLE | EV_ONESHOT),
                    fflags: UInt32(NOTE_EXIT), data: 0, udata: nil)
                guard kevent(events, &event, 1, nil, 0, nil) == 0,
                    let verified = processInformation(pid),
                    verified.kp_proc.p_un.__p_starttime.tv_sec == information.kp_proc.p_un.__p_starttime.tv_sec,
                    verified.kp_proc.p_un.__p_starttime.tv_usec == information.kp_proc.p_un.__p_starttime.tv_usec else {
                    Darwin.close(events)
                    break
                }
                let started = information.kp_proc.p_un.__p_starttime
                registrations.append(Registration(pid: pid, worker: command.kind == "worker",
                    seconds: started.tv_sec, microseconds: Int(started.tv_usec), events: events))
                guard acknowledge() else { break }
            } catch { break }
        }
        for registration in registrations {
            if matches(registration) { kill(registration.pid, SIGKILL) }
        }
        for registration in registrations where registration.worker {
            waitForExit(registration)
        }
        let volume = EncryptedWalletVolume(image: image, mountRoot: mountRoot)
        for registration in registrations where !registration.worker {
            waitForExit(registration) { try? volume.detach() }
        }
        for registration in registrations { Darwin.close(registration.events) }
        var detached = false
        for _ in 0..<20 {
            do { try volume.detach(); detached = true }
            catch { detached = false }
            usleep(250_000)
        }
        _exit(detached ? 0 : 1)
    }

    private static func waitForExit(_ registration: Registration, whileWaiting: (() -> Void)? = nil) {
        let deadline = Date().addingTimeInterval(5)
        while matches(registration) {
            guard Date() < deadline else { _exit(1) }
            var event = kevent()
            var timeout = timespec(tv_sec: 0, tv_nsec: 250_000_000)
            let count = kevent(registration.events, nil, 0, &event, 1, &timeout)
            if count > 0, event.filter == Int16(EVFILT_PROC), event.fflags & UInt32(NOTE_EXIT) != 0 { return }
            if count < 0 && errno != EINTR {
                if !matches(registration) { return }
                usleep(250_000)
            }
            whileWaiting?()
        }
    }
    private static func matches(_ registration: Registration) -> Bool {
        guard let information = processInformation(registration.pid), information.kp_proc.p_stat != SZOMB else { return false }
        let started = information.kp_proc.p_un.__p_starttime
        return started.tv_sec == registration.seconds && Int(started.tv_usec) == registration.microseconds
    }

    private static func processInformation(_ pid: Int32) -> kinfo_proc? {
        var information = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, 4, &information, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.size else { return nil }
        return information
    }

    private static func readLineBytes() -> Data? {
        var line = Data()
        var byte: UInt8 = 0
        while line.count <= 1024 {
            let count = Darwin.read(STDIN_FILENO, &byte, 1)
            if count < 0 && errno == EINTR { continue }
            guard count == 1 else { return nil }
            if byte == 10 { return line }
            line.append(byte)
        }
        return nil
    }

    private static func acknowledge() -> Bool {
        var bytes: [UInt8] = [49, 10]
        return Darwin.write(STDOUT_FILENO, &bytes, bytes.count) == bytes.count
    }
}
