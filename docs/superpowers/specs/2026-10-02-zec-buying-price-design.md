# ZEC Buying Price design

Approved direction: native macOS app, local viewing-key scanning, historical USD prices, selectable receipts and sends, and moving-average acquisition cost for remaining holdings.

## User flow

The user supplies a Unified Full Viewing Key for Zcash mainnet and a wallet birthday date. An optional explicit birthday block height overrides date resolution. The app validates the key through the Zcash library, imports a watch-only account, and scans from the birthday. The birthday is the earliest possible wallet activity, not the user's date of birth. No spending key or seed is requested.

The main window shows scan progress, historical-price progress, estimated average acquisition price in USD per ZEC, selected remaining ZEC, remaining acquisition value, and a transaction table. Each confirmed movement displays date, direction, ZEC amount, historical USD price, estimated USD value, and an inclusion checkbox. All receipts and sends are initially included. The user can exclude either direction with one click and results update immediately. Selection survives refresh and restart.

Selecting a wallet requires a full viewing key because incoming-only authority cannot support the requested outgoing accounting. Unsupported keys receive a clear error rather than silently producing incomplete results. Coverage depends on the pools and account represented by the imported key; the UI explains that boundary.

## Architecture

Use SwiftUI with a Swift Package executable and a reproducible script that packages the executable and resources into a launchable macOS app. Target macOS 14 or later. Keep the interface native: setup form, progress indicators, summary values, searchable transaction table, and settings for service configuration.

The application model coordinates three components:

- A wallet scanner wrapping ZcashLightClientKit. It owns key validation, account import, birthday resolution, persistent wallet data, synchronization, cancellation, and transaction normalization.
- A historical-price service using CoinGecko's Zcash USD history endpoint, with UTC daily caching, request throttling, retry handling, and configurable Demo or Pro credentials.
- A deterministic calculation engine operating on selected, confirmed wallet movements using integer zatoshis and decimal USD values.

Pin the SDK to an immutable revision with a matching published macOS Rust binary after verifying its actual import and synchronization APIs. Use library validation rather than implementing viewing-key parsing. The app never writes the SDK's database directly.

## Wallet data and scanning

Use a configurable TLS lightwalletd endpoint. The default must be verified during implementation. Resolve a date to a conservative block height using block timestamps and a safety margin; never use an assumed fixed block interval. Clamp to supported pool activation boundaries through SDK checkpoint rules. Show the effective birthday height before scanning.

Keep SDK wallet state in Application Support. Keep the viewing key and API credentials in Keychain, and omit them from logs, error strings, exports, and settings summaries. A viewing key cannot spend funds but exposes financial history. Historical-price requests contain only the asset and date, never wallet identifiers or key material.

Expose downloading, scanning, paused, synchronized, and failed states. Cancellation retains durable wallet progress. Resume and reorg recovery use SDK facilities. Publish results from committed wallet state, and refresh movements after synchronization changes. Pending transactions are shown separately and excluded from calculations until confirmed.

Normalize transactions into economic movements belonging to the imported account. Do not count change, shielding, unshielding, or internal self-transfers as new acquisitions. Use the SDK's transaction/output information to establish external received and sent amounts and fees. Do not equate gross outputs or a raw transaction balance delta with a purchase. Movement IDs include transaction ID and sufficient direction/output identity to preserve choices across rescans.

## Historical valuation

For the first version, use the price provider's daily USD observation at 00:00 UTC for the transaction's UTC calendar day. Clearly label this as a daily market-price estimate, including its timestamp and source. The blockchain does not establish the user's actual purchase price.

Fetch prices for unique dates rather than duplicate transactions, persist the cache, and allow an optional positive manual USD-per-ZEC override per movement. CoinGecko's free historical coverage is limited; unavailable dates remain visibly unpriced. The app must not substitute today's price or zero. Rate limiting and transient failures show retryable states.

## Calculation rules

Process included confirmed movements chronologically, with deterministic ordering by block height, transaction order where available, and stable movement ID. Let Q be remaining ZEC and C be its estimated USD acquisition value, initially zero.

For a receipt of q ZEC at price p USD per ZEC, Q becomes Q + q and C becomes C + q * p. For a send of q ZEC, remove q * (C / Q) from C and q from Q. A send's historical market price is displayed but does not change the acquisition price of remaining holdings. Network fees are displayed separately and do not form a receipt or an additional purchase.

Example: receive 1 ZEC at $30 and 1 ZEC at $50. Q is 2, C is $80, and average acquisition price is $40. Send 1 ZEC: Q is 1, C is $40, and average remains $40. Receive another 1 ZEC at $60: Q is 2, C is $100, and average becomes $50.

If an included send exceeds selected holdings, flag the selection as inconsistent and withhold the aggregate rather than invent negative holdings or silently clamp the send. If an included receipt lacks a price, show incomplete valuation and withhold the complete average. Excluding that receipt can also make subsequent sends inconsistent. When Q reaches zero, reset C to zero and display no remaining average. Excluded movements have no effect on the selected accounting ledger; this ledger is distinct from the actual wallet balance.

## Persistence and failures

Persist inclusion choices and manual prices in an app-owned atomic file separate from SDK storage. A reorg removes orphaned movements from calculations while preserving their saved choices if they reappear. Confirmed movement changes trigger recalculation. Missing dates or amounts remain visible errors, not silently omitted records.

Present sanitized, actionable errors for invalid or wrong-network keys, inaccessible Keychain, invalid birthdays, service failures, incomplete scan, missing historical prices, and inconsistent selection. Scanning or pricing failure must not display an apparently complete final average. A reset action clearly identifies the local wallet data and preferences it removes.

## Verification and delivery

Build the native executable and packaged app on this Mac. Test the calculation engine with weighted receipts, partial and complete sends, exclusions in both directions, missing prices, inconsistent selections, same-block ordering, and exact zatoshi handling. Test price decoding, UTC dates, caching, and error handling using controlled responses.

Verify SDK key validation and birthday handling against official test vectors and controlled fixtures. Use a disposable viewing-only test account and controlled lightwalletd history to verify receipts, spends, self-transfers, interruption/resume, and reorg recovery. A passing mock scanner is insufficient evidence of real scanning. If the controlled service cannot run here, retain the integration tests and explicitly report the unverified behavior.

Run the app and inspect setup, progress, transaction checkboxes, errors, and recalculation. Keep demo data explicitly labeled and separate from real wallet results. Deliver source, build/run instructions, the launchable app, and verification results. Do not claim live wallet scanning or complete historical pricing without corresponding evidence.

## Sources

- Zcash Swift SDK: https://github.com/zcash/zcash-swift-wallet-sdk
- SDK macOS package declaration: https://github.com/zcash/zcash-swift-wallet-sdk/blob/main/Package.swift
- CoinGecko historical coverage: https://support.coingecko.com/hc/en-us/articles/4538747001881-What-granularity-do-you-support-for-historical-data
