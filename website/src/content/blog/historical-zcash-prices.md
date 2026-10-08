---
title: Historical Zcash prices, UTC dates, and missing data
description: How ZEC Buying Price uses CoinGecko daily USD observations, why dates follow UTC, and how manual overrides fill gaps in older history.
category: Price data
published: 2026-10-02
updated: 2026-10-02
summary: Daily prices give a consistent reference. They cannot identify the exact price of your trade, and older dates may need another input.
---

ZEC Buying Price requests CoinGecko's historical USD price for the UTC date of a wallet movement. It caches prices by day and allows manual unit-price overrides. A daily observation gives a repeatable market reference, not the exact execution price of an exchange trade.

## Why the date uses UTC

A transaction near midnight can fall on different calendar dates depending on your time zone. Using UTC gives the application one date for the historical-price lookup, instead of changing the lookup when your Mac's time zone changes.

For example, a movement at 01:00 in India occurs at 19:30 UTC on the previous date. These times illustrate the date boundary; they are not a transaction from a real wallet. The price lookup follows the UTC date.

The app's historical-price tests cover UTC date handling. You can inspect the [price implementation](https://github.com/megabyte0x/zec-buyingprice/blob/main/Sources/AcquisitionCore/HistoricalPrice.swift) and [price tests](https://github.com/megabyte0x/zec-buyingprice/blob/main/Tests/AcquisitionCoreTests/PriceTests.swift).

## Why older transactions can lack prices

CoinGecko's published historical-data guidance limits public-plan historical access to the past 365 days. Older receipt dates may require a suitable paid API plan or a manually entered price. This coverage statement was reviewed on 2 October 2026; plan details can change. [CoinGecko historical coverage](https://support.coingecko.com/hc/en-us/articles/4538747001881-What-granularity-do-you-support-for-historical-data) documents the access window.

The app's Settings lets you configure optional Demo or Pro API access. Choosing a paid endpoint does not establish that a particular subscription covers every date. Check the plan associated with your key.

## Missing data is not a zero-dollar purchase

If the app cannot obtain a required receipt price, it does not treat the receipt as a free acquisition and display a complete average. A missing price means missing input. The average remains incomplete until the required inputs are available.

Open the affected movement and enter a manual USD-per-ZEC value if you have a reliable record. If you do not, retain the incomplete status rather than selecting an arbitrary value just to produce a number.

## Why caching matters

Several movements on the same UTC date share one daily price. The application caches observations and throttles requests, reducing repeated lookups. Cached data and manually entered choices are stored locally and persist across restarts.

Caching helps with repeated research; it does not expand the API's history window or transform a market observation into an actual purchase record. For that distinction, read [wallet receipts versus purchases](/blog/wallet-receipts-vs-purchases/).

## Check the whole result

Historical prices are one part of the ledger. A completed price lookup cannot compensate for unfinished scanning or inconsistent movement selections. The [methodology page](/methodology/) explains the calculation, and [incomplete average troubleshooting](/blog/incomplete-zcash-average/) separates scan progress from pricing and selection problems.
