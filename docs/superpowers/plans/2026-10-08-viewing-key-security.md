# feat(security): revised viewing-key implementation plan

The user revised the goal: authenticated mainnet sync continues while the app is running, including when its UI is locked or the app is in the background. Closing the last wallet window or quitting closes protected storage. No test cases are to be added until explicit authorization.

## Subtask 1: Vault and crash cleanup agent

Keep Secure Enclave encryption and verified migration intact. Use running-session eligibility for protected operations. Add a credential-free guardian before image commands, synchronously register process identities before secret delivery, handle late image attach after parent death, and detach app-owned storage after terminating workers. Maintain visible detach failures and startup recovery.

## Subtask 2: Worker agent

Replace foreground checks with live-parent/session checks. Retain parent death, EOF, screen lock, sleep, and session suspension shutdown. Register worker identity with the vault guardian before transmitting credentials. Keep bounded secret-free logs/arguments and normal kill/reap behavior.

## Subtask 3: Parent app integration

Separate foreground unlock eligibility from ongoing sync eligibility. Lock the interface on focus loss/hide/minimize while preserving sync and prices. Require fresh native authentication to reveal wallet data, without restarting the running worker. Close the full session on last wallet close, quit, sleep, and Mac lock. Track independent UI-authentication generations and cancel late callbacks. Add guardian dispatch and registration wiring. Update UI text, README, and design records to describe the protection boundary accurately.

## Subtask 4: Independent review and build

Review alternate saved-key paths, UI authentication races, unexpected worker death, normal closure, guardian process identities, attach cleanup races, and failure handling. Build and launch via Build macOS Apps `script/build_and_run.sh --verify`. Verify signature/plist/scripts and clean diff, preserving Tests unchanged. Native interaction remains a separate user verification; do not infer successful authentication or live sync from compilation.

## Current handoff

All four implementation subtasks are complete. The final revised application builds and launches; signature, plist, scripts, diff, and unchanged Tests checks pass. Final scoped source review found no additional material shutdown/key-path defect. Revised native background syncing and close/quit behavior still await user verification; no test cases were added or run.
