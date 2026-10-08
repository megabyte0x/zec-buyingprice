---
title: Why a Zcash wallet receipt is not your purchase record
description: A ZEC deposit date and a daily USD price cannot reconstruct an exchange fill. Learn how to select movements and enter actual acquisition prices.
category: Records
published: 2026-10-02
updated: 2026-10-02
summary: A receipt records when coins reached a wallet. Your exchange record explains when and at what price you acquired them.
---

A Zcash wallet receipt tells you that coins arrived. It does not establish when you bought them, the execution price, or whether the movement was a purchase at all. ZEC Buying Price can attach a daily market estimate to a receipt, but an estimate is different from an acquisition record.

## Two timestamps, two meanings

Imagine buying 2 ZEC on an exchange on Monday and withdrawing them to your wallet on Friday. The wallet records Friday's receipt. A price request for that receipt date produces a Friday market observation, even though your purchase happened on Monday.

If the price moved between those dates, the resulting estimate will differ from your purchase price. The app cannot infer Monday's fill from Friday's transaction.

## Use an actual price when you have one

The transaction table lets you click a movement's USD-per-ZEC price and enter a manual override. For a single straightforward fill, use your documented unit acquisition price for the quantity being represented.

If a withdrawal combines several fills, work out which acquisitions it represents before entering a number. The current app accepts a unit price; it does not import or reconcile the underlying exchange orders. Keep those source records outside the app so you can explain how you arrived at the override.

The treatment of trading fees and other costs depends on the purpose of your records. This guide describes application behavior and does not select tax rules for your jurisdiction.

## Transfers can duplicate an acquisition

Moving coins between your own wallets does not create a second purchase record. Counting both the original purchase and its later transfer as independent acquisitions can inflate the quantity or change the average you meant to track.

ZEC Buying Price reconciles ownership-based self-transfer and change information where available. Even so, a transfer from a different wallet or exchange may appear as an incoming movement. You still need to review what each selected receipt represents.

## Selection needs a consistent ledger

An inclusion checkbox changes the accounting history. If you remove a receipt but retain a later send, the remaining selected ledger can become inconsistent. The app withholds a complete average when selected sends exceed selected holdings.

Choose movements as a coherent sequence, not as isolated rows that happen to look useful. The selected remaining holdings are an accounting result and can differ from the actual wallet balance. See the [moving-average example](/blog/zcash-average-buying-price/) for the effect of a partial send.

## Keep the estimate useful

A daily market estimate can be useful when you are exploring a history and do not yet have all the records. Label it as an estimate. Replace it when a reliable acquisition record becomes available. Do not turn a convenient proxy into a claim that the blockchain proves what you paid.

Sources: [application calculation and limitations](https://github.com/megabyte0x/zec-buyingprice#historical-price-limitations), [manual-price setup](/setup/), and [historical Zcash price coverage](/blog/historical-zcash-prices/).
