---
title: Zcash tracker alternatives for acquisition research
description: Compare a local ZEC acquisition notebook with Koinly, CoinTracking, and a spreadsheet by input records, wallet visibility, and purpose.
category: Alternatives
published: 2026-10-02
updated: 2026-10-02
summary: Choose by the records you have and the question you need answered, from a local wallet average to a broader reporting workflow.
---

A Zcash tracker can mean several different things: a price chart, a wallet history viewer, an acquisition ledger, or a tax reporting service. ZEC Buying Price is a local macOS acquisition notebook. Koinly and CoinTracking document broader import workflows. A spreadsheet gives you direct control over your own records.

The right alternative depends on whether you need an estimate from wallet movements or an account of purchases across exchanges and wallets.

## Compare the input before the output

| Approach | Starting input | Practical role | What to check |
| --- | --- | --- | --- |
| ZEC Buying Price | Mainnet Unified Full Viewing Key | Local moving-average research in USD | Scan completion, key coverage, and receipt prices |
| Koinly | Public address or CSV in its Zcash integration guide | Broader reporting workflow | Whether your actual history is represented |
| CoinTracking | Public Zcash address in its wallet importer | Imported transaction review | Whether private activity requires other records |
| Spreadsheet | Your own purchase and movement records | Custom ledger and reconciliation | Formula order, missing rows, and duplicated transfers |

This comparison describes documented inputs as reviewed on 2 October 2026. It does not establish feature parity or a complete test of either commercial service.

## Koinly as an alternative

Koinly's Zcash integration page describes public-address and CSV imports, followed by transaction review and reporting. That can be a useful starting point when you want to combine records beyond one wallet.

Its public integration instructions do not establish Unified Full Viewing Key scanning. Before importing, check how your shielded activity will be represented and whether additional records are necessary. A complete-looking table is only useful when its input is complete. [Koinly's Zcash integration](https://koinly.io/integrations/zcash/) is the source for the documented import methods.

## CoinTracking as an alternative

CoinTracking's Zcash importer asks for a public wallet address and offers manual or daily checks. Review its current documentation before assuming that this particular importer covers the private portions of your wallet history. [CoinTracking's Zcash importer](https://cointracking.info/import/zcash_address/) documents that workflow.

Neither public-address importer should be treated as evidence that shielded wallet history has been fully reconstructed. Address visibility and viewing-key capability are different inputs.

## When a spreadsheet is enough

If you have a small number of exchange purchases, a spreadsheet can retain the actual quantities, execution prices, and fees without substituting market observations. Keep transfers between your own accounts separate from purchases so the same acquisition is not counted twice.

Its weakness is maintenance. When you add sends between purchases, a moving-average ledger needs chronological formulas and a remaining acquisition value. A single weighted average of all receipts will not necessarily represent the coins that remain. The [worked average-price example](/blog/zcash-average-buying-price/) shows the difference.

## When the local app fits

ZEC Buying Price fits a narrower question: “What is the average acquisition price of the confirmed movements I selected?” It keeps scan state and choices on your Mac, uses a viewing key, and allows manual prices. It currently has no exchange CSV importer or tax-report export.

It also has development limits: complete scanning and reorg handling are still under verification. Use [release notes](/releases/) to assess the available build and [methodology](/methodology/) to assess the calculation.
