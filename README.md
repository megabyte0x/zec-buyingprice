# ZEC Buying Price

A native macOS 14+ application for estimating the average acquisition price of selected Zcash wallet movements. It imports a mainnet Unified Full Viewing Key through ZcashLightClientKit 3.0.0 and uses CoinGecko daily USD prices.

## Screenshots

Captured from the native macOS app. The acquisition dashboard and dialogs use synthetic transactions and prices for illustration; they do not show a real wallet or establish successful synchronization. The temporary screenshot fixture is not included in the application.

### Wallet setup

Connect a mainnet viewing key and choose the wallet birthday.

![Wallet setup](docs/screenshots/wallet-setup.jpg)

### Acquisition dashboard

Review the average acquisition price, remaining selected holdings, scan progress, and transaction selections.

![Acquisition dashboard with illustrative transactions](docs/screenshots/acquisition-dashboard.jpg)

### Lab settings

Configure the TLS lightwalletd endpoint and optional CoinGecko API access.

![Lab settings](docs/screenshots/settings.jpg)

### Manual acquisition price

Override a movement's daily market estimate with an actual USD price per ZEC.

![Manual acquisition price editor](docs/screenshots/manual-price.jpg)

### Reset confirmation

Review the confirmation before archiving local scan history and transaction choices.

![Reset local history confirmation](docs/screenshots/reset-confirmation.jpg)

## Requirements

- macOS 14 or later on a Mac with Secure Enclave support (Apple silicon or a supported Intel Mac with a T2 chip).
- Touch ID or a Mac account password for native authentication.
- Xcode with Swift 6 or later and its command-line tools selected.
- Internet access to download dependencies and scan a wallet.

## Run

```sh
swift test
./script/build_and_run.sh
```

The script creates `dist/ZECBuyingPrice.app`, signs it locally, and launches it. The Codex Run action invokes the same script. Additional modes are `--verify`, `--debug`, `--logs`, `--telemetry`, and `--stop`. Rebuilds wait for this bundle's worker and cleanup guardian to exit before replacing it. The first build downloads the official SDK binary and networking dependencies.

## Package a release

```sh
VERSION="0.2.0" BUILD_NUMBER="2" NOTARY_PROFILE="zcash-buying-price" ./script/package_dmg.sh
```

This builds the optimized Apple Silicon app, signs the app and DMG with Developer ID and a secure timestamp, submits the DMG to Apple, staples the notarization ticket, and checks Gatekeeper acceptance. The default identity is `Developer ID Application: Yash Garg (9UR77TD484)`; override it with `SIGNING_IDENTITY` if needed. `VERSION` and `BUILD_NUMBER` default to `0.1.0` and `1`. Output is `dist/ZECBuyingPrice-<version>-arm64.dmg`, with its final checksum in `dist/SHA256SUMS.txt`. Omitting `NOTARY_PROFILE` produces a signed DMG without notarization.

## Use

1. Enter a mainnet Unified Full Viewing Key and a date before the wallet's first activity. An optional birthday block height takes precedence.
2. Open Settings to configure the TLS lightwalletd endpoint and optional CoinGecko Demo or Pro API key. The default endpoint is `zec.rocks:443`.
3. Authenticate with Touch ID or your Mac login password, then start scanning. The scan continues while the app is open, including when you switch apps or minimize the window. The full average is withheld until synchronization and required receipt pricing finish.
4. Toggle each transaction's inclusion checkbox. Click its USD-per-ZEC price to enter a manual override. Choices persist across rescans and restarts.

The scan bar follows the SDK's work percentage. Block details show completed blocks scanned separately from the chain tip and the height through which history is fully verified. The SDK can scan ranges in a different order, so the verified height can pause while other work advances.

The viewing key is encrypted using a Secure Enclave protected key. The encrypted credential envelope and an AES-256 encrypted wallet disk image live under `~/Library/Application Support/ZECBuyingPrice/protected-vault/`. The Secure Enclave supplies a hardware-wrapped key representation; the imported Zcash viewing key itself cannot be stored directly inside the enclave. SDK account data, SQLite journals, scan progress, new price caches, transaction choices, and reset archives stay inside the encrypted wallet volume. The price API key remains in Keychain.

Each new sync session requires native authentication from the foreground wallet window. Switching apps, hiding, or minimizing locks the wallet interface while its authenticated worker continues syncing with mainnet. Unlocking the interface requires Touch ID or your Mac login password without restarting that worker. The menu also offers a full wallet lock that stops syncing.

Quitting, closing the last wallet window, sleeping, or locking the Mac ends the session: the app terminates and reaps the sync worker, clears displayed data, and detaches the encrypted volume. Closing the last wallet window also quits the application after cleanup succeeds. Reopening requires authentication before key access or sync. A separate cleanup helper holds no credentials and watches for unexpected app exit, stops registered workers, and detaches app-owned storage. No launch agent or daemon restarts sync. Failed detach remains visible and blocks normal termination/unlock. An unavailable Secure Enclave, cancelled authentication, or failed migration has no software fallback.

The interface lock is a privacy control, not a new encryption boundary: while syncing, the worker uses the viewing key and the SDK database is mounted. This design protects stored copies after the session closes; it cannot prevent extraction by an attacker who already controls an unlocked process, nor erase copies taken previously. Crash cleanup is best effort rather than an instantaneous guarantee against system failure or privileged interference.

On the first authenticated unlock, existing wallet directories and reset archives migrate into the encrypted volume. The app verifies the encrypted copies before removing managed plaintext originals and the legacy viewing-key Keychain item. Interrupted migration cleanup can resume. Previous backups and filesystem snapshots cannot be erased by this migration. Price requests contain only the asset and date. Viewing keys reveal financial history; the application does not request spending keys or sign transactions.

## Calculation

Selected confirmed receipts add ZEC and acquisition value at the historical or manually entered price. Selected sends remove ZEC and acquisition value proportionally at the running average. Sending does not change the average of the remaining holdings. Pending movements are excluded. Network fees are available in transaction tooltips and do not form purchases. The selected accounting ledger is distinct from the actual wallet balance.

Missing prices and sends exceeding the selected holdings prevent a complete average. Excluding a receipt can make later selected sends inconsistent. SDK output information is reconciled against each transaction's account balance change; ambiguous history fails visibly rather than being presented as a complete average.

## Historical-price limitations

Market-price estimates are not actual exchange purchase records. CoinGecko's daily historical observation is used for the transaction's UTC date; manual overrides can represent the actual acquisition price. Free historical access is limited to one year. Older transactions can require a paid API plan or manual prices. Requests are cached per UTC day and throttled.

Birthday dates resolve conservatively against actual timestamps from the SDK release's mainnet checkpoints, with a two-day margin. This may scan earlier than the requested date. The SDK also rounds explicit heights to its available checkpoint. Key pool/account coverage determines visible history.

## Verification status

The security update compiles. New test development is deferred at the user’s request; the existing suite has not been rerun against this update. The user confirmed native authentication and mainnet syncing with the interface locked in the revised build, including the visible scan bar and block count. Close/quit cleanup, unexpected-exit cleanup, and complete migration still require interactive verification. Before this security update, all 18 existing tests passed. Automated tests cover moving-average accounting, exclusion, liquidation, missing prices, oversends, exact zatoshis, UTC dates, price response decoding, manual-price validation, persistence, pending exclusion, same-block transaction ordering, ownership-based self-transfer/change exclusion, and reconciliation of incomplete output history. SDK integration tests validate an official public mainnet UFVK fixture, reject invalid/wrong-network keys, import a real view-only account against the default endpoint, and observe live scan progress followed by a successful pause.

Complete receipt/spend scanning, interruption/resume, and controlled reorg behavior remain under verification. A live test that required contiguous scan height to advance within 60 seconds failed: scan progress reached 4% while the SDK scanned newer ranges first. The corrected progress/pause test passes; it does not establish full scan completion. The app is currently a development build, not a verified production release.

## Sources

- [Zcash Swift SDK](https://github.com/zcash/zcash-swift-wallet-sdk), including mainnet checkpoint timestamps and public key test fixture.
- [Public SDK viewing-key fixture](https://github.com/zcash/zcash-swift-wallet-sdk/blob/055145a4b2b8e57eb8673d16708dd8c3f0dbb13e/Tests/OfflineTests/DerivationToolTests/DerivationToolMainnetTests.swift), verified byte-for-byte against the integration-test key.
- [Default server information](https://hosh.zec.rocks/zec/zec.rocks).
- [CoinGecko historical coverage](https://support.coingecko.com/hc/en-us/articles/4538747001881-What-granularity-do-you-support-for-historical-data).
