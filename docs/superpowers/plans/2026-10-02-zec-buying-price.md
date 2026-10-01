# ZEC Buying Price Implementation Plan

> **For agentic workers:** Use executing-plans to implement this plan task-by-task in this chat. Steps use checkbox syntax for tracking.

**Goal:** Build a native viewing-only Zcash acquisition-price calculator with real scanning and selectable incoming and outgoing movements.

**Architecture:** SwiftUI owns the desktop flow. A pure Swift core calculates selected holdings and persists choices; SDK and HTTP adapters provide confirmed movements and historical daily prices.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, Security Keychain, ZcashLightClientKit, CoinGecko.

**Spec:** docs/superpowers/specs/2026-10-02-zec-buying-price-design.md

## Global Constraints

- Target macOS 14 or later, mainnet Unified Full Viewing Keys, and USD.
- Never send wallet keys or identifiers to the price provider; never log key material.
- Use integer zatoshis, decimal USD, confirmed movements, and stable inclusion choices.
- Missing prices and inconsistent selected holdings withhold the complete average.
- Do not count change or internal transfers as purchases; demonstrate scanning separately from mocks.

### Task 1: Calculation core

Files: Package.swift, Sources/AcquisitionCore/Movement.swift, Sources/AcquisitionCore/AcquisitionLedger.swift, Tests/AcquisitionCoreTests/LedgerTests.swift.

Interfaces: `Movement` carries stable ID, timestamp, height, amount in zatoshis, direction, inclusion, and optional price. `AcquisitionLedger.calculate(_ movements: [Movement]) throws -> LedgerResult` returns remaining quantity, value, and optional average.

- [ ] Create the package and failing test for two receipts and one send.

```swift
XCTAssertEqual(try AcquisitionLedger.calculate([
    receipt(100_000_000, price: 30), receipt(100_000_000, price: 50),
    send(100_000_000)
]).averagePrice, 40)
```

- [ ] Run `swift test --filter LedgerTests` and observe the missing implementation.
- [ ] Implement chronological decimal weighted accumulation and proportional send removal.
- [ ] Test missing receipt prices, oversends, complete liquidation, exclusions, exact zatoshis, and deterministic ordering; run `swift test`.

### Task 2: Price retrieval and choice persistence

Files: Sources/AcquisitionCore/HistoricalPrice.swift, Sources/AcquisitionCore/ChoiceStore.swift, Tests/AcquisitionCoreTests/PriceTests.swift, Tests/AcquisitionCoreTests/ChoiceTests.swift.

Interfaces: `HistoricalPriceService.price(on: Date) async throws -> Decimal`; `ChoiceStore` saves inclusion and manual price by movement ID to an atomic JSON file.

- [ ] Test UTC day normalization and provider decoding before implementing them.

```swift
XCTAssertEqual(try HistoricalPriceService.decode(data), Decimal(40))
```

- [ ] Implement CoinGecko requests, credentials, positive price validation, unique-day disk caching, bounded retry, and cancellation.
- [ ] Test malformed/absent values and persistent choices after recreating a store; run `swift test`.

### Task 3: Real SDK adapter

Files: Sources/ZECBuyingPrice/Services/WalletScanner.swift, Sources/ZECBuyingPrice/Services/KeychainStore.swift, Package.swift.

- [ ] Inspect pinned SDK source for UFVK import, watch-only account setup, birthday resolution, sync state, and output interpretation.
- [ ] Pin its immutable revision and compatible Rust binary; resolve dependencies with `swift package resolve`.
- [ ] Validate official viewing-key fixtures with the SDK and build the adapter against actual APIs.
- [ ] Implement durable scanning, pause/resume, conservative date-to-height resolution, pending exclusion, and movement normalization using documented SDK data.
- [ ] Run controlled service integration checks for receipts, sends, change, internal transfers, and reorg/resume; report absent integration evidence explicitly.

### Task 4: Native desktop flow

Files: Sources/ZECBuyingPrice/App/ZECBuyingPriceApp.swift, Stores/WalletModel.swift, Views/ContentView.swift, Views/SetupView.swift, Views/TransactionTable.swift, Views/SettingsView.swift.

- [ ] Create a WindowGroup and app-owned observable model; keep setup and table views separate.
- [ ] Connect secure key entry, birthday controls, service settings, scan progress, pause/resume, pricing progress, and sanitized errors.
- [ ] Bind each checkbox and manual price override to persisted choices and immediate recalculation.
- [ ] Build with `swift build`; inspect native setup, table interactions, incomplete valuation, and selection errors in the launched app.

### Task 5: Packaging and verification

Files: script/build_and_run.sh, .codex/environments/environment.toml, README.md, .gitignore.

- [ ] Package executable and SwiftPM resource bundles into `dist/ZECBuyingPrice.app` using the macOS plugin bootstrap contract.
- [ ] Support run, debug, logs, telemetry, and verify flags; wire the Codex Run action.
- [ ] Run `swift test` and `./script/build_and_run.sh --verify`.
- [ ] Audit the approved spec against source, test output, live integration evidence, and rendered UI; leave unverifiable requirements open.
- [ ] Document commands, historical-price limitations, key coverage, and actual verification results.

Commits use Conventional Commits when Git author identity is available. Missing identity does not prevent building or testing the application.
