# feat(security): keep mainnet syncing while the authenticated app is open

The user revised the original foreground-only rule on October 8, 2026. The implementation now separates the wallet interface lock from the running sync session. Work used Build macOS Apps guidance and separate vault/cleanup, SDK worker, parent integration, and independent review subtasks.

## Implemented behavior

- Startup does not read the saved viewing key into a text field. Native Touch ID or the Mac login password authorizes each new sync session from a foreground wallet window.
- Switching apps, hiding, or minimizing locks the interface while the authenticated mainnet worker and price retrieval continue. The locked interface shows scan progress without wallet balances or transactions. Native reauthentication reveals the interface without reopening storage or restarting the worker.
- The menu and locked screen provide a full lock that stops syncing. Quitting, closing the last wallet window, sleeping, switching user sessions, and Mac screen lock also end the session. Full shutdown invalidates pending tasks and contexts, kills/reaps the worker, clears UI data, and detaches the encrypted volume. Successful last-wallet-window cleanup quits the app too.
- A Secure Enclave P-256 user-presence operation decrypts an AES-256-GCM credential envelope using ECDH and HKDF-SHA256. The hardware-wrapped CryptoKit key representation is persisted; the imported viewing key itself is encrypted outside the enclave. No software-key fallback exists.
- SDK accounts, SQLite journals, scan state, choices, price caches, and reset archives reside in an AES-256 encrypted sparse image. Secrets pass through stdin, never command-line arguments or logs.
- A guardian holding no credentials obtains exclusive ownership before vault metadata access and registers process identities before image passwords or SDK keys are delivered. Parent exit stops registered workers/commands and attempts app-owned volume cleanup. Unexpected guardian death closes the parent session. Startup recovery cannot detach another active app instance's vault.
- Image commands have finite output/exit deadlines. Interrupted attaches get repeated cleanup checks. Mountpoint cleanup is nonrecursive and does not traverse late-mounted wallet contents. Detach failures stay visible and prevent a new session or normal termination.
- Legacy migration remains authenticated and verified before deleting unchanged managed plaintext originals. Old backups and filesystem snapshots cannot be erased by migration.

## Protection boundary

While syncing, the worker uses the viewing key and the SDK volume is mounted. The interface lock is a privacy control, not an encryption boundary against another process that already controls the user's unlocked session. Stored copies are protected after a successful full shutdown, and reopening requires native authentication. Swift strings are not claimed to be reliably zeroized; successful app termination removes its process as well as the worker. Development rebuilds now stop only this bundle's GUI parent and wait for the worker and guardian; they abort on incomplete cleanup. Release packaging uses the same stop path before replacing the bundle. Launch verification checks the GUI process rather than accepting a remaining helper.

Unexpected-exit cleanup is best effort. Kernel/DiskImages failures, privileged interference, or data copied while already unlocked prevent any absolute claim that no one can ever extract a key. Cleanup failure is not silently reported as successful protection.

## Checks performed

The final revised app passed `./script/build_and_run.sh --verify`: compilation completed in 5.04 seconds and the packaged application launched. The bundle passed `codesign --verify --deep --strict`; Info.plist passed `plutil -lint`; both build/packaging scripts passed Bash syntax validation. `git diff --check` was clean and Tests has no changes.

Read-only review found and resolved missing SIGPIPE protection, metadata initialization before exclusive ownership, unbounded image-command waits, recursive deletion of potentially late-mounted directories, incomplete error-path process cleanup, and late re-registration of closed windows. The final scoped review found no additional material shutdown or key-path defect. Source review and compilation are not runtime proof.

## Deferred verification

The user confirmed the prior native authentication/foreground-lock build works. Continued mainnet syncing after switching/minimizing, interface reauthentication without worker restart, last-window/quit shutdown, unexpected-exit cleanup, and full migration still need validation of the revised build on supported hardware.

At the user's request, no new test cases are in the project and the existing suite was not run. Earlier draft cases remain outside the project for later explicit authorization. Earlier synthetic checks from before the user's instruction do not establish end-to-end security of this revised code. Release notarization was not performed.

## Sync-display follow-up

The user reported rising percentage with a stationary bar and block height. Source tracing confirmed both widgets share the same progress fraction; it did not reproduce or establish a specific native rendering defect. Both now use one shared custom `ProgressViewStyle` whose fill width is directly proportional to that fraction.

The previous block value was the contiguous fully-scanned frontier, which can remain stationary while the SDK scans newer ranges. Worker events now optionally report actual completed scanned-range counts since birthday and the maximum recorded scanned height, from a single read-only SQLite snapshot. The UI separates blocks scanned, chain tip, and history verified through a height. It does not calculate block height from the SDK's weighted work percentage. Requeued ranges can reduce the count after a rewind; failures omit optional metadata and preserve syncing. The schema assumptions match the pinned SDK and were source reviewed.

The progress follow-up passed the final build/GUI launch, signature, plist, shell syntax, and diff checks listed above. Scoped review found no additional material defect. Native painting and a live count update remain interactive checks; no test cases or synthetic wallet probes were added.

## fix(vault): stop command-output collection at EOF

The user reported the interface remaining at “Unlocking / opening protected storage” after authentication. Sampling the running GUI found its main thread spinning in `collectImageCommandOutput` during vault cleanup, while neither an image command nor a sync worker remained. The pipe stayed poll-readable at EOF; empty reads did not exit the loop. The collector now exits on a nil or empty read and retains the existing bounded child-exit wait, output cap, deadline, and kill/reap handling. Independent scoped review passed.

The corrected app passed `./script/build_and_run.sh --verify` with a 3.74-second build and was reopened. A subsequent live process check found the GUI at 0.0% CPU, the vault guardian running, and the sync worker active. A fresh GUI sample showed the normal AppKit event wait rather than the command-output loop. The bundle signature and diff checks passed; Tests remains unchanged. This confirms protected storage opened and the worker started in that observed session. Native progress painting and the remaining shutdown scenarios still require interactive verification. No test cases were added or run.
