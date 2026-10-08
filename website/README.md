# ZEC Buying Price website

Static Astro site with official shadcn/ui Radix components and Tailwind 4. The homepage and guides ship readable HTML; only the FAQ hydrates React. The site respects the system color scheme and reduced-motion preference.

## Development and validation

```sh
npm ci
ASTRO_TELEMETRY_DISABLED=1 npm run build
npm run audit
ASTRO_TELEMETRY_DISABLED=1 npm run preview
```

Astro reports the actual preview URL and may select another port if one is occupied. Use that address for browser checks:

```sh
SITE_URL=http://127.0.0.1:4322 node scripts/browser-check.mjs
```

Install Chromium with `npx playwright install chromium` if needed. The browser check covers mobile and desktop, light and dark schemes, FAQ behavior, browser errors, horizontal overflow, and axe WCAG checks. Run `node scripts/live-check.mjs` for the public domain, download, 404, and canonical hostname checks. The static audit checks unique metadata, canonical URLs, raw content, internal links, JSON-LD parsing, and sitemap membership. These do not prove search indexation or production Core Web Vitals.

## Deploy

```sh
npm run deploy
```

Uses the authenticated Wrangler account, Cloudflare Pages project `zecbuyingprice`, and production branch `main`. Vercel DNS holds the `zecbuyingprice` CNAME under `megabyte.sh`, pointing at `zecbuyingprice.pages.dev`. The custom hostname must also be attached in Cloudflare Pages for TLS validation. Cloudflare Bulk Redirect list `zecbuyingprice_canonical` redirects the Pages hostname and its preview subdomains to the canonical custom host, preserving paths and queries. Domain redirects are not supported by the Pages `_redirects` file. Unrelated DNS records should not be changed.

## Content and release updates

Guides live in `src/content/blog/`. Each has a unique intent, a direct answer, source links, examples where relevant, and a developer byline. Update review dates only when the article has actually been reviewed. The six initial intents are average ZEC buying price, tracker alternatives, viewing-key privacy, receipts versus purchases, historical ZEC prices, and incomplete results. No keyword-volume or ranking claims have been measured.

Canonical URLs and schema constants live in `src/lib/site.ts`. The download URL is deliberately versioned and is mirrored in `public/_redirects`. `public/_headers` applies security and cache headers. RSS, robots, sitemap, and llms.txt are generated during the build. llms.txt is an optional navigation aid; it is not a proven ranking lever.

The current development release is `0.2.1`, published under `v0.2.1-dev` with the exact asset filename and signing/notarization status recorded in `src/lib/release.json`. The previous 0.2.0 assets remain on their existing release. The website’s release manifest records the app source revision, final checksum, byte size, and verified signing/notarization status. Update that manifest, `src/lib/site.ts`, `public/_redirects`, and `public/downloads/SHA256SUMS.txt` together after inspecting the finished artifact. DMGs exceed Pages’ per-asset limit, so `/download/` redirects to GitHub.

To package and notarize this release from the repository root:

```sh
VERSION=0.2.1 BUILD_NUMBER=3 NOTARY_PROFILE=zcash-buying-price ./script/package_dmg.sh
cp dist/ZECBuyingPrice-0.2.1-arm64.dmg dist/ZECBuyingPrice-0.2.1-arm64-notarized.dmg
(cd dist && shasum -a 256 ZECBuyingPrice-0.2.1-arm64-notarized.dmg > SHA256SUMS-notarized.txt)
```

The package script builds the optimized app, includes its Swift compatibility library, signs with Developer ID and hardened runtime, and verifies the signatures and disk image. With `NOTARY_PROFILE`, it also submits to Apple, staples the accepted ticket, and checks Gatekeeper. Record the checksum after stapling and verify the included app read-only before publishing. Publish new versioned assets without overwriting older downloads, confirm the GitHub binary exists, then deploy the website.

Version 0.2.1 shows transactions and provisional acquisition values during syncing, preserves selections and prices across incoming snapshots, and reduces repeated database and price work. One focused progressive-sync regression test passed. The earlier 18-test suite was not rerun for this release. Full-sync performance, complete receipt/spend scanning, shutdown/crash cleanup, migration, resume, and controlled reorg behavior remain under verification; release copy must keep those limits separate from successful distribution checks.

## References applied

- [shadcn skill and component workflow](https://ui.shadcn.com/docs/skills)
- [Claude SEO technical skill](https://github.com/AgriciDaniel/claude-seo/blob/main/skills/seo-technical/SKILL.md)
- [Claude SEO GEO skill](https://github.com/AgriciDaniel/claude-seo/blob/main/skills/seo-geo/SKILL.md)

The external SEO skills were consulted as references. The full Claude plugin and its optional integrations were not installed. SEO/GEO work focuses on crawlable HTML, correct metadata, documented software behavior, clear authorship, original examples, and primary sources. No results or citations from search engines are guaranteed.
