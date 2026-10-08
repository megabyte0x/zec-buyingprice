---
title: What a Zcash viewing key reveals in a local tracker
description: Understand Unified Full Viewing Keys, Secure Enclave protection, encrypted storage, network requests, and why view-only access still contains sensitive financial information.
category: Privacy
published: 2026-10-02
updated: 2026-10-08
summary: A viewing key grants visibility without spending authority. That makes it useful for research, but it still deserves careful handling.
---

A Zcash viewing key lets compatible software inspect covered wallet activity without possessing the spending key. ZEC Buying Price imports a mainnet Unified Full Viewing Key, or UFVK, through ZcashLightClientKit. It does not ask for your seed phrase and cannot sign transactions.

View-only does not mean public. The history a viewing key reveals can be sensitive even when the key cannot authorize a payment.

## Why a unified key matters

Zcash has multiple receiver types and value pools. A Unified Full Viewing Key packages supported viewing components into one encoded key. Which components and accounts are present affects the activity that software can see.

[ZIP 316](https://zips.z.cash/zip-0316) defines Unified Addresses and Unified Viewing Keys. The practical consequence for this app is straightforward: do not assume one imported key covers every account, pool, or wallet you have ever used.

## Where the app stores information

The app encrypts the imported viewing key using Secure Enclave protection. Each new wallet session requires Touch ID or your Mac login password. The encrypted credential envelope and encrypted wallet disk image live under `~/Library/Application Support/ZECBuyingPrice/protected-vault/`. Account data, scan state, SQLite journals, new price caches, transaction choices, and reset archives stay inside that encrypted volume. The optional CoinGecko API key remains in macOS Keychain.

The imported Zcash key itself is not stored inside the enclave. The enclave protects the cryptographic key used to unlock it. During migration from an older build, the app verifies encrypted copies before removing managed plaintext history and the legacy viewing-key Keychain item. That cannot remove copies in previous backups or filesystem snapshots.

## What happens when the window locks?

After authentication, syncing continues while the app is open, including when you switch apps, hide the app, or minimize the wallet window. The interface hides your financial history and requires authentication to show it again. The authenticated worker continues its scan.

Closing the last wallet window, quitting, sleeping, or locking the Mac ends the session: the app stops its worker and detaches encrypted storage. The menu also offers a full wallet lock that stops syncing. A helper watches for an unexpected exit and attempts cleanup; crash cleanup is best effort. No background daemon restarts the scan.

While the worker is syncing, it can access the viewing key and mounted database. Interface locking does not create another encryption boundary or prevent an attacker who already controls an unlocked process from extracting data. Consider who can access your Mac and your backups.

## Which services are contacted?

The app connects to a configurable TLS lightwalletd endpoint to scan wallet activity. The default endpoint is `zec.rocks:443`. It also requests historical market prices from CoinGecko.

The application's price requests contain the asset and date rather than the viewing key or transaction identifier. That limits what the price service receives from this request path. It does not make network use anonymous: services can still observe connection information such as your IP address.

For the exact data flow, inspect the [wallet scanner](https://github.com/megabyte0x/zec-buyingprice/blob/main/Sources/ZECBuyingPrice/Services/WalletScanner.swift) and [historical-price client](https://github.com/megabyte0x/zec-buyingprice/blob/main/Sources/AcquisitionCore/HistoricalPrice.swift).

## What to paste during setup

Use your wallet's supported method to obtain a mainnet UFVK. Wallet export features differ, so follow the documentation for the wallet you actually use. A public receiving address is not a replacement for this key. A seed phrase is not required.

Paste the key into the installed application on your Mac. The website has no key-import form. Choose a birthday date before the wallet's first activity; an optional birthday height takes precedence. See [setup](/setup/) for the application flow.

## Reading the privacy boundary correctly

This app separates visibility from spending authority. It does not prove that your operating system, backups, selected endpoint, or every dependency is free of risk. Keep that distinction clear when sharing screenshots or diagnostic files: a screenshot can expose the same history you wanted to keep local.

Read the [privacy and network behavior page](/privacy/) for the website and application boundaries. For acquisition results, also check [why an average may be incomplete](/blog/incomplete-zcash-average/).
