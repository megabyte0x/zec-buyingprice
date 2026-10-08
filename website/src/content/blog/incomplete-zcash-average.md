---
title: Why your Zcash average acquisition price is incomplete
description: Diagnose unfinished scanning, missing daily prices, oversends, and inconsistent movement selections without mistaking a partial result for a complete ledger.
category: Troubleshooting
published: 2026-10-02
updated: 2026-10-09
summary: An incomplete result points to unfinished or inconsistent inputs. Check scanning, receipt prices, and selected movements in that order.
---

ZEC Buying Price withholds a complete average when required history or pricing is unfinished, or when selected movements do not form a consistent ledger. This is useful information: a missing result can be more accurate than a precise number based on partial data.

During syncing, transactions appear as the SDK discovers and enhances them. The summary can show a provisional average from discovered movements with available receipt prices. More history or prices can change that figure, and sends without sufficient selected priced receipts still prevent a calculation. The provisional label stays separate from a complete result.

## 1. Check scanning before changing the ledger

A viewing-key scan must discover covered wallet activity before the app can present a complete result. Check the endpoint in Settings, network connectivity, and the birthday you supplied. A birthday after the wallet's first activity may miss earlier receipts.

Choose a date before the wallet's first activity. The app resolves birthday dates conservatively against SDK checkpoints with a two-day margin. An explicit height takes precedence, and the SDK can round it to an available checkpoint.

The progress bar reports the SDK’s work percentage. The block count reports completed scan ranges, while the verified height marks continuous coverage from the birthday. Newer ranges can be scanned first, so the verified height can stay fixed while other work advances.

Do not infer full completion from an isolated progress update. The current development build has verified live scan progress and pause behavior; complete receipt and spend scanning remains under verification. See [release status](/releases/).

## 2. Find receipts without prices

Every selected receipt needs a usable acquisition price. A failed request, inaccessible older date, or missing price observation can leave the ledger incomplete.

If you have a documented acquisition price, enter it using the movement's price editor. If history is older than the public API's coverage window, check your API plan or use manual input. [Historical-price coverage](/blog/historical-zcash-prices/) explains the date and access limits.

## 3. Look for selected sends without selected funding

Consider a simple sequence: receive 2 ZEC, then send 1 ZEC. If you deselect the receipt while keeping the send, the selected ledger starts with zero and tries to remove one. It cannot produce a meaningful remaining acquisition value.

Restore a coherent selection if the receipt belongs in the history you are tracking. Do not add a fictitious receipt to make the error disappear. The selected ledger is separate from the live wallet balance, so a funded wallet does not automatically mean your selected accounting sequence is funded.

## 4. Treat ambiguous history as unresolved

The scanner reconciles SDK output information against each transaction's account balance change. If those records cannot be reconciled unambiguously, the app reports the problem instead of labeling the average complete.

A key may also omit activity outside its account or receiver coverage. [Viewing-key scope](/blog/zcash-viewing-key-privacy/) explains why importing one key does not prove that all of your ZEC history is present.

## Before reporting a problem

Record the app version, the displayed error, whether scanning was paused, and whether any selected receipts lack prices. Report reproducible steps through the [project's issue tracker](https://github.com/megabyte0x/zec-buyingprice/issues). Keep viewing keys, API keys, transaction history, and identifying screenshots out of public reports.

Resetting history archives local scan state and choices; it is not a substitute for understanding the missing input. Review the reset confirmation in the app before using it. For the calculation itself, see [methodology](/methodology/).
