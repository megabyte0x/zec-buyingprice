import AppKit
import CryptoKit
import Darwin
import Foundation
import LocalAuthentication
import Security

@MainActor
final class WalletVault {
    struct Session {
        let viewingKey: String
        let birthday: Int
        let directory: URL
    }

    enum Failure: Error, LocalizedError {
        case unavailable, malformed, revoked, migration, detach, alreadyOpen
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Secure wallet storage is unavailable. A Mac with Secure Enclave support and native authentication is required."
            case .malformed: return "The protected wallet metadata is damaged. The existing wallet has been preserved."
            case .revoked: return "The authenticated app session ended. Open a wallet window and unlock again."
            case .migration: return "Wallet migration could not be verified. The existing wallet has been preserved."
            case .detach: return "The encrypted wallet volume could not be detached. Close the app and retry before unlocking."
            case .alreadyOpen: return "A wallet operation is already in progress."
            }
        }
    }

    private struct Envelope: Codable {
        let version: Int
        let hardwareKey: Data
        let ephemeralPublicKey: Data
        let salt: Data
        let ciphertext: Data
    }
    private struct Credential: Codable {
        let viewingKey: String
        let birthday: Int
        let password: String
        let migrations: [Migration]
    }
    private struct Migration: Codable {
        let name: String
        let manifest: [VerifiedWalletMigration.Entry]
    }

    private let root: URL
    private let storage: URL
    private let volume: EncryptedWalletVolume
    private let guardian: VaultGuard
    private let sessionEligible: @MainActor () -> Bool
    private let migrateLegacyCredential: Bool
    private var generation = UUID()
    private var opening = false
    private(set) var isOpen = false
    private var startupFailure: Error?
    var onProtectionFailure: (() -> Void)? {
        didSet { guardian.onFailure = onProtectionFailure }
    }

    init(root: URL? = nil, sessionEligible: @escaping @MainActor () -> Bool = {
        NSApplication.shared.isRunning && NSApplication.shared.windows.contains {
            $0.isVisible || $0.isMiniaturized || NSApplication.shared.isHidden
        }
    }) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZECBuyingPrice", isDirectory: true)
        storage = self.root.appendingPathComponent("protected-vault", isDirectory: true)
        let image = storage.appendingPathComponent("wallet.sparseimage")
        let mountRoot = storage.appendingPathComponent("mounts", isDirectory: true)
        let guardProcess = VaultGuard(image: image, mountRoot: mountRoot)
        guardian = guardProcess
        volume = EncryptedWalletVolume(image: image, mountRoot: mountRoot,
            commandWillStart: { try guardProcess.registerCommand(pid: $0) })
        self.sessionEligible = sessionEligible
        migrateLegacyCredential = root == nil
        do { try guardian.withRecoveryLease { try volume.detach() } } catch { startupFailure = error }
    }

    var hasSavedWallet: Bool {
        FileManager.default.fileExists(atPath: envelopeURL.path) ||
        FileManager.default.fileExists(atPath: pendingURL.path) ||
        (migrateLegacyCredential && KeychainStore.contains(name: "viewing-key"))
    }
    private var envelopeURL: URL { storage.appendingPathComponent("envelope.json") }
    private var pendingURL: URL { storage.appendingPathComponent("pending-envelope.json") }

    func open(context: LAContext, viewingKey: String?, birthday: Int,
              isCurrent: @escaping @MainActor () -> Bool = { true }) async throws -> Session {
        guard !opening, !isOpen else { throw Failure.alreadyOpen }
        if let startupFailure { throw startupFailure }
        let token = generation
        var protectionRequired = false
        func check() throws {
            guard token == generation, sessionEligible(), isCurrent(), !Task.isCancelled,
                !protectionRequired || guardian.isProtecting else { throw Failure.revoked }
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { throw Failure.revoked }
        }
        try check()
        opening = true
        defer { opening = false }
        do {
            try privateDirectory(storage)
            try guardian.start()
            protectionRequired = true
            try check()
            let committed = FileManager.default.fileExists(atPath: envelopeURL.path)
            let pending = FileManager.default.fileExists(atPath: pendingURL.path)
            let envelope: Envelope
            var credential: Credential
            if committed || pending {
                envelope = try readEnvelope(at: committed ? envelopeURL : pendingURL)
                try check()
                credential = try await Task.detached { try self.decrypt(envelope, context: context) }.value
                try check()
            } else {
                try check()
                let legacy = migrateLegacyCredential && KeychainStore.contains(name: "viewing-key")
                    ? try await KeychainStore.readLegacyViewingKey(context: context, authorized: { (try? check()) != nil }) : nil
                try check()
                guard let key = viewingKey ?? legacy, !key.isEmpty,
                      birthday >= 419_200, birthday <= Int(UInt32.max) else { throw Failure.malformed }
                guard legacy == nil || legacy == key else { throw Failure.migration }
                let sources = try legacySources()
                var migrations: [Migration] = []
                for source in sources {
                    let manifest = try await VerifiedWalletMigration.manifest(for: source, authorize: check)
                    try check()
                    migrations.append(Migration(name: source.lastPathComponent, manifest: manifest))
                }
                var passwordData = Data(count: 32)
                guard passwordData.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }) == errSecSuccess else {
                    throw Failure.unavailable
                }
                credential = Credential(viewingKey: key, birthday: birthday,
                    password: passwordData.base64EncodedString(), migrations: migrations)
                try check()
                let initialCredential = credential
                envelope = try await Task.detached { try self.encrypt(initialCredential, context: context) }.value
                try check()
                try privateDirectory(storage)
                try durableWrite(try JSONEncoder().encode(envelope), to: pendingURL)
            }
            guard !credential.viewingKey.isEmpty, credential.password.count >= 40,
                  credential.birthday >= 419_200, credential.birthday <= Int(UInt32.max) else { throw Failure.malformed }
            try check()
            if !FileManager.default.fileExists(atPath: volume.image.path) {
                guard !committed else { throw Failure.malformed }
                try await volume.create(password: credential.password)
                try check()
            }
            try check()
            var mount = try await volume.attach(password: credential.password)
            try check()
            let wallets = mount.appendingPathComponent("wallets", isDirectory: true)
            try privateDirectory(wallets)
            if !committed {
                for migration in credential.migrations {
                    try check()
                    try validateMigrationName(migration.name)
                    try await VerifiedWalletMigration.copy(source: root.appendingPathComponent(migration.name),
                        destination: wallets.appendingPathComponent(migration.name), manifest: migration.manifest, authorize: check)
                    try check()
                }
                try check()
                try volume.detach()
                try check()
                mount = try await volume.attach(password: credential.password)
                try check()
                for migration in credential.migrations {
                    try await VerifiedWalletMigration.verify(directory: mount.appendingPathComponent("wallets/\(migration.name)"),
                        manifest: migration.manifest, authorize: check)
                    try check()
                }
                try check()
                let reopened = try await Task.detached { try self.decrypt(envelope, context: context) }.value
                try check()
                guard reopened.viewingKey == credential.viewingKey, reopened.password == credential.password else { throw Failure.malformed }
                try check()
                try durableWrite(try JSONEncoder().encode(envelope), to: envelopeURL)
                try FileManager.default.removeItem(at: pendingURL)
                try synchronizeDirectory(storage)
            }
            try check()
            for migration in credential.migrations {
                try validateMigrationName(migration.name)
                let source = root.appendingPathComponent(migration.name)
                if FileManager.default.fileExists(atPath: source.path) {
                    try await VerifiedWalletMigration.verify(directory: mount.appendingPathComponent("wallets/\(migration.name)"),
                        manifest: migration.manifest, authorize: check)
                    try check()
                    try await VerifiedWalletMigration.removeVerifiedSource(directory: source,
                        manifest: migration.manifest, authorize: check)
                    try check()
                    try synchronizeDirectory(root)
                }
            }
            if migrateLegacyCredential {
                try check()
                if KeychainStore.contains(name: "viewing-key"),
                   let legacy = try await KeychainStore.readLegacyViewingKey(context: context, authorized: { (try? check()) != nil }) {
                    try check()
                    guard legacy == credential.viewingKey else { throw Failure.migration }
                    try check()
                    try KeychainStore.removeLegacyViewingKey()
                }
            }
            try check()
            if let viewingKey, viewingKey != credential.viewingKey {
                guard !viewingKey.isEmpty, birthday >= 419_200, birthday <= Int(UInt32.max) else { throw Failure.malformed }
                let replacement = Credential(viewingKey: viewingKey, birthday: birthday,
                    password: credential.password, migrations: credential.migrations)
                try check()
                let updated = try await Task.detached {
                    try self.encrypt(replacement, envelope: envelope, context: context)
                }.value
                try check()
                try durableWrite(try JSONEncoder().encode(updated), to: envelopeURL)
                credential = replacement
            }
            let fingerprint = SHA256.hash(data: Data(credential.viewingKey.utf8)).map { String(format: "%02x", $0) }.joined()
            let directory = mount.appendingPathComponent("wallets/\(fingerprint)", isDirectory: true)
            try privateDirectory(directory)
            try check()
            isOpen = true
            return Session(viewingKey: credential.viewingKey, birthday: credential.birthday, directory: directory)
        } catch {
            isOpen = false
            do {
                try guardian.withRecoveryLease { try volume.detach() }
                try guardian.finish()
                startupFailure = nil
            } catch {
                startupFailure = Failure.detach
                throw Failure.detach
            }
            throw error
        }
    }

    func registerWorker(pid: Int32) throws {
        guard isOpen, sessionEligible() else { throw Failure.revoked }
        try guardian.registerWorker(pid: pid)
    }

    func lock() throws {
        let ownedSession = isOpen || opening || guardian.isProtecting
        generation = UUID()
        isOpen = false
        do {
            try guardian.withRecoveryLease { try volume.detach() }
            try guardian.finish()
            startupFailure = nil
        } catch {
            if !ownedSession, case Failure.alreadyOpen = error { return }
            startupFailure = Failure.detach
            throw Failure.detach
        }
    }

    private func legacySources() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter {
            let name = $0.lastPathComponent
            return name.hasPrefix("reset-") || (name.count == 64 && name.allSatisfy { $0.isHexDigit })
        }
    }
    private func validateMigrationName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              name.hasPrefix("reset-") || (name.count == 64 && name.allSatisfy { $0.isHexDigit }) else { throw Failure.malformed }
    }
    private func readEnvelope(at url: URL) throws -> Envelope {
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 16 * 1024 * 1024 else { throw Failure.malformed }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == 2, !envelope.hardwareKey.isEmpty, envelope.hardwareKey.count <= 65_536,
                envelope.ephemeralPublicKey.count == 65, envelope.salt.count == 32,
                envelope.ciphertext.count > 28 else { throw Failure.malformed }
            return envelope
        } catch { throw Failure.malformed }
    }
    nonisolated private func privateKey(envelope: Envelope, context: LAContext) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        guard SecureEnclave.isAvailable else { throw Failure.unavailable }
        do {
            return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: envelope.hardwareKey,
                authenticationContext: context)
        } catch { throw Failure.unavailable }
    }
    nonisolated private func encrypt(_ credential: Credential, context: LAContext) throws -> Envelope {
        guard SecureEnclave.isAvailable else { throw Failure.unavailable }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.userPresence, .privateKeyUsage], &error) else { throw Failure.unavailable }
        let key: SecureEnclave.P256.KeyAgreement.PrivateKey
        do {
            key = try SecureEnclave.P256.KeyAgreement.PrivateKey(compactRepresentable: false,
                accessControl: access, authenticationContext: context)
        } catch { throw Failure.unavailable }
        return try seal(credential, key: key, context: context)
    }
    nonisolated private func encrypt(_ credential: Credential, envelope: Envelope, context: LAContext) throws -> Envelope {
        try seal(credential, key: privateKey(envelope: envelope, context: context), context: context)
    }
    nonisolated private func seal(_ credential: Credential, key: SecureEnclave.P256.KeyAgreement.PrivateKey,
        context: LAContext) throws -> Envelope {
        let ephemeral = P256.KeyAgreement.PrivateKey(compactRepresentable: false)
        let publicKey = ephemeral.publicKey.x963Representation
        let hardwareKey = key.dataRepresentation
        var salt = Data(count: 32)
        guard salt.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }) == errSecSuccess else {
            throw Failure.unavailable
        }
        let sharedSecret = try ephemeral.sharedSecretFromKeyAgreement(with: key.publicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
            sharedInfo: keyDerivationInfo(recipient: key.publicKey, ephemeral: publicKey), outputByteCount: 32)
        let plaintext = try JSONEncoder().encode(credential)
        let sealed = try AES.GCM.seal(plaintext, using: symmetricKey,
            authenticating: authenticatedMetadata(hardwareKey: hardwareKey, ephemeral: publicKey, salt: salt))
        guard let ciphertext = sealed.combined else { throw Failure.unavailable }
        let envelope = Envelope(version: 2, hardwareKey: hardwareKey, ephemeralPublicKey: publicKey,
            salt: salt, ciphertext: ciphertext)
        let verified = try decrypt(envelope, context: context)
        guard verified.viewingKey == credential.viewingKey, verified.password == credential.password else { throw Failure.unavailable }
        return envelope
    }
    nonisolated private func decrypt(_ envelope: Envelope, context: LAContext) throws -> Credential {
        let key = try privateKey(envelope: envelope, context: context)
        let publicKey: P256.KeyAgreement.PublicKey
        do { publicKey = try P256.KeyAgreement.PublicKey(x963Representation: envelope.ephemeralPublicKey) }
        catch { throw Failure.malformed }
        let sharedSecret: SharedSecret
        do { sharedSecret = try key.sharedSecretFromKeyAgreement(with: publicKey) }
        catch { throw Failure.unavailable }
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: envelope.salt,
            sharedInfo: keyDerivationInfo(recipient: key.publicKey, ephemeral: envelope.ephemeralPublicKey), outputByteCount: 32)
        do {
            let sealed = try AES.GCM.SealedBox(combined: envelope.ciphertext)
            let plaintext = try AES.GCM.open(sealed, using: symmetricKey,
                authenticating: authenticatedMetadata(hardwareKey: envelope.hardwareKey,
                    ephemeral: envelope.ephemeralPublicKey, salt: envelope.salt))
            return try JSONDecoder().decode(Credential.self, from: plaintext)
        } catch { throw Failure.malformed }
    }
    nonisolated private func keyDerivationInfo(recipient: P256.KeyAgreement.PublicKey, ephemeral: Data) -> Data {
        Data("app.zec.buyingprice.vault.ecdh-hkdf-sha256-aes256gcm.v2".utf8) + recipient.x963Representation + ephemeral
    }
    nonisolated private func authenticatedMetadata(hardwareKey: Data, ephemeral: Data, salt: Data) -> Data {
        Data("app.zec.buyingprice.vault.envelope.v2".utf8) + hardwareKey + ephemeral + salt
    }
}

struct VerifiedWalletMigration {
    struct Entry: Codable, Equatable {
        let path: String
        let digest: String?
    }
    @MainActor static func manifest(for directory: URL, authorize: () throws -> Void) async throws -> [Entry] {
        var entries: [Entry] = []
        let manager = FileManager.default
        let rootAttributes = try manager.attributesOfItem(atPath: directory.path)
        guard rootAttributes[.type] as? FileAttributeType == .typeDirectory else { throw WalletVault.Failure.migration }
        func visit(_ url: URL, relative: String) async throws {
            await Task.yield()
            try authorize()
            let attributes = try manager.attributesOfItem(atPath: url.path)
            switch attributes[.type] as? FileAttributeType {
            case .typeDirectory:
                entries.append(Entry(path: relative, digest: nil))
                for child in try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    try await visit(child, relative: relative.isEmpty ? child.lastPathComponent : "\(relative)/\(child.lastPathComponent)")
                }
            case .typeRegular:
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                var hash = SHA256()
                while true {
                    await Task.yield()
                    try authorize()
                    guard let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
                    hash.update(data: data)
                }
                entries.append(Entry(path: relative, digest: hash.finalize().map { String(format: "%02x", $0) }.joined()))
            default: throw WalletVault.Failure.migration
            }
        }
        try await visit(directory, relative: "")
        return entries.sorted { $0.path < $1.path }
    }
    @MainActor static func verify(directory: URL, manifest expected: [Entry], authorize: () throws -> Void) async throws {
        guard try await manifest(for: directory, authorize: authorize) == expected else { throw WalletVault.Failure.migration }
    }
    @MainActor static func removeVerifiedSource(directory: URL, manifest expected: [Entry],
        authorize: () throws -> Void) async throws {
        let remaining = try await manifest(for: directory, authorize: authorize)
        let allowed = Dictionary(uniqueKeysWithValues: expected.map { ($0.path, $0) })
        guard remaining.allSatisfy({ allowed[$0.path] == $0 }) else { throw WalletVault.Failure.migration }
        for entry in remaining.reversed() {
            await Task.yield()
            try authorize()
            let url = directory.appendingPathComponent(entry.path)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if entry.digest == nil {
                guard attributes[.type] as? FileAttributeType == .typeDirectory,
                    try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty else { throw WalletVault.Failure.migration }
            } else {
                guard attributes[.type] as? FileAttributeType == .typeRegular else { throw WalletVault.Failure.migration }
                let input = try FileHandle(forReadingFrom: url)
                var hash = SHA256()
                do {
                    while true {
                        await Task.yield()
                        try authorize()
                        guard let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
                        hash.update(data: data)
                    }
                    try input.close()
                } catch {
                    try? input.close()
                    throw error
                }
                guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == entry.digest else {
                    throw WalletVault.Failure.migration
                }
            }
            try authorize()
            try FileManager.default.removeItem(at: url)
            try synchronizeDirectory(url.deletingLastPathComponent())
        }
    }
    @MainActor static func copy(source: URL, destination: URL, manifest: [Entry], authorize: () throws -> Void) async throws {
        try await verify(directory: source, manifest: manifest, authorize: authorize)
        if FileManager.default.fileExists(atPath: destination.path) {
            try await verify(directory: destination, manifest: manifest, authorize: authorize)
            return
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".migration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        for entry in manifest {
            await Task.yield()
            try authorize()
            let original = source.appendingPathComponent(entry.path)
            let copied = staging.appendingPathComponent(entry.path)
            if entry.digest == nil {
                try privateDirectory(copied)
            } else {
                guard FileManager.default.createFile(atPath: copied.path, contents: nil,
                    attributes: [.posixPermissions: 0o600]) else { throw WalletVault.Failure.migration }
                let input = try FileHandle(forReadingFrom: original)
                defer { try? input.close() }
                let output = try FileHandle(forWritingTo: copied)
                defer { try? output.close() }
                while true {
                    await Task.yield()
                    try authorize()
                    guard let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
                    try output.write(contentsOf: data)
                }
                try output.synchronize()
            }
        }
        try await verify(directory: staging, manifest: manifest, authorize: authorize)
        try await verify(directory: source, manifest: manifest, authorize: authorize)
        try authorize()
        try FileManager.default.moveItem(at: staging, to: destination)
        try synchronizeDirectory(destination.deletingLastPathComponent())
    }
}

@MainActor
final class EncryptedWalletVolume {
    let image: URL
    private let mountRoot: URL
    private var command: Process?
    private var activeMount: URL?
    private var interruptedCommand = false
    private var generation = UUID()
    private let commandWillStart: ((Int32) throws -> Void)?

    init(image: URL, mountRoot: URL, commandWillStart: ((Int32) throws -> Void)? = nil) {
        self.image = image
        self.mountRoot = mountRoot
        self.commandWillStart = commandWillStart
    }

    func create(password: String) async throws {
        guard !FileManager.default.fileExists(atPath: image.path) else { throw WalletVault.Failure.malformed }
        try privateDirectory(image.deletingLastPathComponent())
        let token = generation
        _ = try await run(["create", "-size", "32g", "-type", "SPARSE", "-fs", "APFS", "-volname",
            "ZECVault-\(UUID().uuidString)", "-encryption", "AES-256", "-stdinpass", "-nospotlight", image.path], password: password)
        guard generation == token, !Task.isCancelled else { throw WalletVault.Failure.revoked }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: image.path)
        let handle = try FileHandle(forWritingTo: image)
        try handle.synchronize()
        try handle.close()
        try synchronizeDirectory(image.deletingLastPathComponent())
    }

    func attach(password: String) async throws -> URL {
        try detach()
        let token = generation
        try privateDirectory(mountRoot)
        var backupExcluded = mountRoot
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try backupExcluded.setResourceValues(values)
        let mount = mountRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try privateDirectory(mount)
        do {
            _ = try await run(["attach", image.path, "-stdinpass", "-mountpoint", mount.path,
                "-nobrowse", "-noautoopen", "-owners", "on", "-plist"], password: password)
            guard generation == token, !Task.isCancelled else { throw WalletVault.Failure.revoked }
            activeMount = mount
            try privateDirectory(mount)
            try Data().write(to: mount.appendingPathComponent(".metadata_never_index"))
            return mount
        } catch {
            try detach()
            throw error
        }
    }

    func detach() throws {
        generation = UUID()
        // Stop and reap the image command before checking for mounts left by DiskImages.
        if let command {
            if command.isRunning {
                interruptedCommand = true
                kill(command.processIdentifier, SIGKILL)
                try waitForImageCommand(command, timeout: 5)
            } else if command.terminationStatus != 0 { interruptedCommand = true }
        }
        if interruptedCommand {
            var failure: Error?
            for _ in 0..<20 {
                do { try detachMountedImages(); failure = nil }
                catch { failure = error }
                usleep(250_000)
            }
            if let failure { throw failure }
            interruptedCommand = false
        } else { try detachMountedImages() }
    }

    private func detachMountedImages() throws {
        let info = try runSynchronous(["info", "-plist"])
        guard let dictionary = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any],
              let images = dictionary["images"] as? [[String: Any]] else { throw WalletVault.Failure.detach }
        for mounted in images {
            let mountedImage = (mounted["image-path"] as? String).map { URL(fileURLWithPath: $0).standardizedFileURL }
            let entities = mounted["system-entities"] as? [[String: Any]] ?? []
            let ownedMount = entities.contains {
                guard let path = $0["mount-point"] as? String else { return false }
                return path.hasPrefix(mountRoot.standardizedFileURL.path + "/")
            }
            guard mountedImage == image.standardizedFileURL || ownedMount else { continue }
            guard let device = entities.compactMap({ $0["dev-entry"] as? String }).first else { throw WalletVault.Failure.detach }
            _ = try runSynchronous(["detach", device])
        }
        activeMount = nil
        if FileManager.default.fileExists(atPath: mountRoot.path) {
            for directory in try FileManager.default.contentsOfDirectory(at: mountRoot, includingPropertiesForKeys: nil) {
                guard rmdir(directory.path) == 0 || errno == ENOENT else { throw WalletVault.Failure.detach }
            }
        }
    }

    private func run(_ arguments: [String], password: String) async throws -> Data {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory()]
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw WalletVault.Failure.unavailable
        }
        try process.run()
        command = process
        do {
            try commandWillStart?(process.processIdentifier)
            try input.fileHandleForWriting.write(contentsOf: Data(password.utf8) + Data([0]))
            try input.fileHandleForWriting.close()
            let result = try await Task.detached {
                try collectImageCommandOutput(process, output: output.fileHandleForReading, timeout: 30)
            }.value
            guard process.terminationStatus == 0 else { throw WalletVault.Failure.unavailable }
            if command === process { command = nil }
            return result
        } catch {
            interruptedCommand = true
            try? input.fileHandleForWriting.close()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            do { try waitForImageCommand(process, timeout: 5) }
            catch { throw WalletVault.Failure.detach }
            if command === process { command = nil }
            throw error
        }
    }

    private func runSynchronous(_ arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        command = process
        do {
            let data = try collectImageCommandOutput(process, output: output.fileHandleForReading, timeout: 30)
            guard process.terminationStatus == 0 else { throw WalletVault.Failure.detach }
            if command === process { command = nil }
            return data
        } catch {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            do { try waitForImageCommand(process, timeout: 5) }
            catch { throw WalletVault.Failure.detach }
            if command === process { command = nil }
            throw error
        }
    }
}

private func privateDirectory(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw WalletVault.Failure.migration }
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
}

private func durableWrite(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    let handle = try FileHandle(forWritingTo: url)
    try handle.synchronize()
    try handle.close()
    try synchronizeDirectory(url.deletingLastPathComponent())
}

private func synchronizeDirectory(_ directory: URL) throws {
    let descriptor = Darwin.open(directory.path, O_RDONLY)
    guard descriptor >= 0 else { throw WalletVault.Failure.migration }
    defer { Darwin.close(descriptor) }
    guard fsync(descriptor) == 0 else { throw WalletVault.Failure.migration }
}

private func waitForImageCommand(_ process: Process, timeout: TimeInterval) throws {
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning {
        guard Date() < deadline else { throw WalletVault.Failure.detach }
        usleep(10_000)
    }
    process.waitUntilExit()
}

private func collectImageCommandOutput(_ process: Process, output: FileHandle, timeout: TimeInterval) throws -> Data {
    let deadline = Date().addingTimeInterval(timeout)
    var data = Data()
    while true {
        var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
        let ready = poll(&descriptor, 1, process.isRunning ? 100 : 0)
        if ready > 0 && descriptor.revents & Int16(POLLIN) != 0 {
            guard let chunk = try output.read(upToCount: 65_536), !chunk.isEmpty else { break }
            data.append(chunk)
        } else if !process.isRunning { break }
        else if ready > 0 { usleep(10_000) }
        if data.count > 1024 * 1024 || Date() >= deadline {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            try waitForImageCommand(process, timeout: 5)
            throw WalletVault.Failure.unavailable
        }
        if ready < 0 && errno != EINTR {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            try waitForImageCommand(process, timeout: 5)
            throw WalletVault.Failure.unavailable
        }
    }
    try waitForImageCommand(process, timeout: 5)
    return data
}
