# feat(security): protect viewing keys after app closure and keep open-app sync running

The user revised the approved design on October 8, 2026: switching focus must not end mainnet syncing. Keep native authentication and the interface lock; close the protected session when the application closes. Test development remains deferred until the user explicitly authorizes it.

## Session behavior

- Startup reads only nonsensitive metadata; never repopulate a saved viewing key into a text field.
- Native Touch ID or the Mac login password authorizes each new sync session, initiated from a foreground wallet window.
- Once authenticated, the worker continues syncing when the app loses focus, hides, or minimizes. The interface locks and returning requires native authentication to display wallet data again. Interface unlock reuses the running session without decrypting the saved key again or restarting the worker.
- Quitting, closing the last wallet window, sleep, user-session suspension, and Mac screen lock invalidate pending work, stop and reap the worker, clear in-memory UI data, and detach protected storage. Successful last-wallet-window closure also terminates the parent app.
- A new foreground unlock is required after the session ends. No launch agent, login item, or daemon automatically unlocks or restarts syncing.
- Separate generation checks prevent late authentication or setup callbacks from reopening a closed session.

## Protected storage

A nonexportable Secure Enclave P-256 key-agreement key protects a credential envelope. Its hardware-wrapped CryptoKit representation, ephemeral public key, salt, and ciphertext are persisted. User presence and private-key usage access control protect decryption. Ephemeral ECDH, domain-separated HKDF-SHA256, and AES-256-GCM encrypt and authenticate the viewing key and a random encrypted-volume password. No software-key fallback exists.

Imported Zcash viewing keys cannot themselves live inside the Secure Enclave. The SDK stores another copy in its database, so SDK account storage, SQLite journals, scan progress, transaction choices, price caches, and reset archives reside in a private AES-256 encrypted APFS sparse image. Passwords are passed through stdin, never arguments or the login Keychain. Mounts suppress Finder browsing/automatic opening and Spotlight indexing and are excluded from backup.

The SDK runs in a separate process with bounded stdin/stdout IPC. Normal shutdown kills and reaps this worker before detaching the image. A credential-free guardian starts before protected storage opens and registers SDK and image-command process identities before sending secrets. Unexpected parent exit triggers worker termination and app-owned volume cleanup, accounting for an in-flight attach. Successful normal detach also closes the guardian.

Detach errors remain visible and prevent normal app termination or a new unlock. Existing stale mounts are cleaned on startup. Cleanup after a crash is best effort: the design cannot promise instantaneous revocation under OS failure, privileged interference, or extraction from an already unlocked process. An interface lock hides wallet data but leaves the worker's key and mounted database available to the authenticated app during syncing.

## Migration

Authenticate before reading a legacy credential. Copy every managed wallet directory and reset archive into encrypted storage, verify streamed manifests, and commit durable metadata before deleting unchanged plaintext originals and the legacy Keychain item. Interrupted cleanup resumes from verified subsets. Preserve recoverable source/destination data on failures; reject unexpected files and symlinks. Existing backups or snapshots outside managed copies cannot be erased by this migration.

## Verification and scope

Use separate vault, worker, UI integration, and independent review subtasks with focused agent context. Use Build macOS Apps build/run and lifecycle guidance. Do not add test cases until the user authorizes them. Build, launch, source review, signature/plist checks, and diff checks proceed. The user confirmed the prior native authentication behavior; revised background syncing, interface reauthentication, close/quit, and crash cleanup require their own runtime verification.

## Sources

- [Apple Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave)
- [Apple CryptoKit key persistence](https://developer.apple.com/documentation/cryptokit/storing-cryptokit-keys-in-the-keychain)
- [Apple user presence access control](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/userpresence)
- Local `hdiutil` documentation for AES-256 sparse images, stdin passwords, private mount points, and detach.
