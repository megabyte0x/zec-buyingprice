import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';
const base = 'https://zecbuyingprice.megabyte.sh';
const paths = ['/', '/blog/', '/methodology/', '/setup/', '/privacy/', '/releases/', '/blog/zcash-average-buying-price/', '/blog/zcash-tracker-alternatives/', '/blog/zcash-viewing-key-privacy/', '/blog/wallet-receipts-vs-purchases/', '/blog/historical-zcash-prices/', '/blog/incomplete-zcash-average/', '/robots.txt', '/sitemap-index.xml', '/sitemap-0.xml', '/rss.xml', '/llms.txt', '/downloads/SHA256SUMS.txt'];
const results = [];
for (const path of paths) {
  const response = await fetch(base + path, { signal: AbortSignal.timeout(20000) });
  const body = await response.text();
  assert.equal(response.status, 200, path);
  assert(!response.headers.get('x-robots-tag')?.includes('noindex') || path.startsWith('/downloads/'), `Noindex on public page ${path}`);
  if (path.endsWith('/')) {
    assert(body.includes(`rel="canonical" href="${base}${path}"`), path);
    assert(body.includes('<h1'), path);
  }
  results.push({ path, status: response.status });
}
const download = await fetch(base + '/download/', { redirect: 'manual' });
assert.equal(download.status, 302);
assert(download.headers.get('location').endsWith('ZECBuyingPrice-0.1.0-arm64.dmg'));
const missing = await fetch(base + '/not-a-real-page/');
assert.equal(missing.status, 404);
for (const host of ['zecbuyingprice.pages.dev', 'cbb763f2.zecbuyingprice.pages.dev']) {
  const response = await fetch(`https://${host}/blog/?source=check`, { redirect: 'manual' });
  assert.equal(response.status, 301, host);
  assert.equal(response.headers.get('location'), base + '/blog/?source=check', host);
}
const report = { results, download: 302, missing: 404, canonicalHostRedirect: 301 };
await writeFile('/tmp/zec-site-reference/live-smoke.json', JSON.stringify(report, null, 2));
console.log(JSON.stringify({ publicUrls: results.length, status: 'pass', download: 302, missing: 404, canonicalHostRedirect: 301 }));
