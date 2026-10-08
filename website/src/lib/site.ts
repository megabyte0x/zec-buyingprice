import release from './release.json';
export const site = {
  name: 'ZEC Buying Price',
  url: 'https://zecbuyingprice.megabyte.sh',
  repo: 'https://github.com/megabyte0x/zec-buyingprice',
  author: 'Megabyte',
  authorUrl: 'https://github.com/megabyte0x',
  version: '0.2.0',
  release: 'https://github.com/megabyte0x/zec-buyingprice/releases/tag/v0.2.0-dev',
  asset: 'https://github.com/megabyte0x/zec-buyingprice/releases/download/v0.2.0-dev/ZECBuyingPrice-0.2.0-arm64-notarized.dmg',
};
export const faqs = [
  {question:'What does ZEC Buying Price calculate?',answer:'The moving average acquisition price in USD per ZEC for selected confirmed wallet movements. Receipts add quantity and acquisition value. Sends remove both proportionally. The selected ledger can differ from your wallet balance.'},
  {question:'Does the app need my seed phrase?',answer:'No. It imports a mainnet Unified Full Viewing Key, encrypted using Secure Enclave protection on your Mac. It does not request a seed phrase or spending key and cannot sign transactions. A viewing key still reveals financial history, so treat it as sensitive.'},
  {question:'Is the historical price my actual purchase price?',answer:'Not necessarily. CoinGecko provides a daily market observation for the transaction’s UTC date. Click a movement’s price to replace that estimate with your actual USD price per ZEC.'},
  {question:'Can I use it for a tax return?',answer:'The app is an acquisition research tool. It does not generate tax reports, identify every taxable event, or choose a jurisdiction’s accounting rules. Use complete exchange and wallet records when preparing a return.'},
  {question:'Which Macs are supported?',answer:`The downloadable development build requires an Apple Silicon Mac with Secure Enclave support running macOS 14 or later. An Intel DMG is not provided. ${release.notarized ? 'This DMG is Developer ID signed, notarized by Apple, and includes a stapled notarization ticket.' : release.signed ? 'This DMG is Developer ID signed, but is not notarized by Apple. Gatekeeper acceptance has not been verified.' : 'Packaging and signing checks are pending.'}`},
  {question:'Does scanning stop when I switch apps?',answer:'Syncing continues while the app is open, including when you switch apps, hide it, or minimize its window. The wallet interface locks until you authenticate again. Closing the last wallet window, quitting, sleeping, or locking the Mac ends the session and closes encrypted storage.'},
  {question:'Why is my average incomplete?',answer:'The app withholds a complete result while scanning or receipt pricing is unfinished. Missing prices, inconsistent selections, selected sends greater than selected holdings, or ambiguous history can also prevent completion.'},
];
