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

The development release target is `0.2.0`, with the versioned GitHub prerelease asset `ZECBuyingPrice-0.2.0-arm64.dmg` under `v0.2.0-dev`. The 0.2.0 DMG is Developer ID signed with hardened runtime and a secure timestamp. App and DMG signature checks and disk-image integrity verification passed. Apple notarization and Gatekeeper acceptance have not been verified; the website must state this until a notarization ticket and acceptance checks are confirmed. Signing and notarization status, source revision, download size, and the final SHA-256 checksum are recorded in `src/lib/release.json`. DMGs exceed Pages' 25 MiB per-asset limit, so `/download/` redirects directly to the GitHub binary.

To package this signed development release, run `VERSION="0.2.0" BUILD_NUMBER="2" ./script/package_dmg.sh` from the repository root. Adding `NOTARY_PROFILE="zcash-buying-price"` submits the DMG to Apple, staples its ticket, and checks Gatekeeper after notarization is authorized. The package script builds the optimized release app, includes the linked Swift compatibility library, signs with Developer ID, verifies signatures and disk-image integrity, and produces `dist/SHA256SUMS.txt`. Notarization and Gatekeeper checks run only when a notary profile is supplied. Verify architecture and minimum macOS version before changing the filename or platform claims. Publish a new versioned asset and update `src/lib/release.json`, `public/downloads/SHA256SUMS.txt`, release details, and both download URLs together. Do not overwrite an existing release asset silently. Confirm the versioned binary exists on GitHub before deploying its download redirects.

The 18 passing application tests describe the earlier implementation. The security update has not rerun that suite, and new tests remain deferred; release copy must distinguish this history from packaging checks and native observations. A user screenshot confirmed synchronization while the wallet interface was locked, including the updated progress bar and scanned-block count. Last-window close and quit cleanup, crash cleanup, migration, full scan completion, resume, and reorg handling remain under verification.

## References applied

- [shadcn skill and component workflow](https://ui.shadcn.com/docs/skills)
- [Claude SEO technical skill](https://github.com/AgriciDaniel/claude-seo/blob/main/skills/seo-technical/SKILL.md)
- [Claude SEO GEO skill](https://github.com/AgriciDaniel/claude-seo/blob/main/skills/seo-geo/SKILL.md)

The external SEO skills were consulted as references. The full Claude plugin and its optional integrations were not installed. SEO/GEO work focuses on crawlable HTML, correct metadata, documented software behavior, clear authorship, original examples, and primary sources. No results or citations from search engines are guaranteed.
