---
title: How to calculate your average Zcash buying price
description: A worked ZEC moving-average example, including partial sends, manual prices, and the difference between wallet receipts and actual purchases.
category: Calculation
published: 2026-10-02
updated: 2026-10-02
summary: Add acquisition value as ZEC arrives. Remove it proportionally when ZEC leaves. The order of those movements matters.
---

Your average Zcash buying price is the acquisition value of the holdings you are tracking divided by their remaining ZEC quantity. ZEC Buying Price applies a moving average to selected confirmed wallet movements. A receipt increases quantity and value; a send removes both at the current average.

## A worked example

Suppose you acquire 2 ZEC at $40 per ZEC, then 1 ZEC at $70 per ZEC. These numbers are illustrative, not historical market observations.

| Movement | Remaining ZEC | Acquisition value | Average USD / ZEC |
| --- | ---: | ---: | ---: |
| Receive 2 ZEC at $40 | 2 | $80 | $40 |
| Receive 1 ZEC at $70 | 3 | $150 | $50 |
| Send 1 ZEC | 2 | $100 | $50 |
| Receive 2 ZEC at $80 | 4 | $260 | $65 |

The first two receipts produce `(2 × 40 + 1 × 70) / 3 = $50`. Sending 1 ZEC removes $50 of acquisition value. The remaining 2 ZEC still average $50 each. The final receipt adds $160, giving $260 across 4 ZEC.

This is why dividing all receipts by all received ZEC can disagree with the moving average of what remains. A send before a later purchase changes how much earlier acquisition value is carried forward.

## A wallet receipt is not automatically a purchase

A wallet may receive coins bought minutes earlier, coins moved from another account you own, a gift, or a payment. The blockchain receipt does not establish the exchange execution price or the economic category of that receipt.

Start by matching your wallet movements to records you understand. ZEC Buying Price lets you select movements and replace daily market estimates with manual USD-per-ZEC prices. It does not import exchange fills or classify every receipt for you. Read [wallet receipts versus purchases](/blog/wallet-receipts-vs-purchases/) before interpreting a daily price as what you paid.

## What happens to fees and pending movements?

The current application excludes pending movements from the acquisition calculation. Network fees are shown in transaction tooltips and do not form purchases in this ledger. That behavior is part of the app's calculation; it is not a general instruction for tax accounting.

Amounts are represented in zatoshis in the accounting core. One ZEC contains 100,000,000 zatoshis. Keeping the asset quantity exact avoids treating tiny floating-point differences as additional holdings.

## When the result should be withheld

If you exclude an early receipt but leave a later send selected, the ledger may try to remove more coins than it holds. A number calculated from that sequence would be misleading. Missing receipt prices and ambiguous reconciled history also prevent a complete result.

The app is a development build. Automated accounting tests do not establish that every wallet will finish scanning correctly. See [methodology and verification status](/methodology/) for the current limits.

## Sources and further reading

- [Application source and calculation notes](https://github.com/megabyte0x/zec-buyingprice#calculation)
- [Acquisition ledger implementation](https://github.com/megabyte0x/zec-buyingprice/blob/main/Sources/AcquisitionCore/AcquisitionLedger.swift)
- [Historical ZEC prices and manual overrides](/blog/historical-zcash-prices/)
