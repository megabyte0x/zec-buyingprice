# feat(website): publish and verify the download site

Verified on 2 October 2026 at https://zecbuyingprice.megabyte.sh/.

## Publication

- Cloudflare Pages project: `zecbuyingprice`.
- Final deployment: [a7fd4364 deployment](https://a7fd4364.zecbuyingprice.pages.dev).
- Custom domain is active, with active HTTP validation and Google certificate issuance.
- Vercel DNS CNAME: `zecbuyingprice` → `zecbuyingprice.pages.dev`, record `rec_2bb51746010831e2f7a1f133`.
- Cloudflare Bulk Redirect list: `zecbuyingprice_canonical`, ID `322a2bc7106144c6bea591cda60abda7`.
- Canonical redirect ruleset: `8af455a18b6245fcb9a57a17e06e278a`; rule `0be5d683d2224bd8a4b5c540ed930d9d`.
- GitHub prerelease: https://github.com/megabyte0x/zec-buyingprice/releases/tag/v0.1.0-dev.

## Checks run

Production build: 13 HTML pages, zero Astro errors, warnings, or hints. Static audit: 13 unique titles and descriptions, 254 local links, 39 parsed JSON-LD blocks, 12 sitemap URLs, and FAQ content present in raw HTML.

Live smoke check: 18 public URLs returned HTTP 200. The download action returned HTTP 302 directly to the versioned DMG. A nonexistent path returned HTTP 404. Both primary and preview Pages hostnames returned HTTP 301 to the canonical hostname, preserving the path and query. Indexable public pages did not return an X-Robots-Tag noindex header.

Chromium checks on the live custom domain: homepage at 390px and 1440px in light and dark schemes; mobile alternatives, release, and setup pages. No axe WCAG violations, page errors, or horizontal page overflow. FAQ collapse and reopen worked. Scrollable tables and checksum blocks are keyboard focusable.

Final Lighthouse local mobile run: performance 98, accessibility 100, best practices 100, SEO 100. LCP 2.3 seconds, CLS 0, total blocking time 0 ms. These are local simulated lab results, not production field measurements. No CrUX, search rankings, indexation, or AI citations have been measured.

The DMG passed hdiutil verification. Its read-only mounted application passed strict deep signature verification and included libswiftCompatibilitySpan.dylib. A publicly downloaded copy matched SHA-256 `f446164ad345653e799e59bc4a67efcff4c8a49eabd1657177adb0408a2d4b3e`.

## Limits

The DMG remains an ad hoc signed, non-notarized Apple Silicon development build. Complete scanning, resume, and controlled reorg behavior remain under verification, as described in the application README and release page. Native application tests were not rerun for this website task; site claims about the existing 18 tests are explicitly attributed to the repository's verification status.

Website source, packaging script, and documentation are saved in the local repository. No source commit or branch push was performed. The release tag points to the existing app source revision; packaging adds and locally signs the compatibility library.

## feat(release): prepare the 0.2.0 security update

On 8 October 2026, the user authorized pushing the security implementation, building a signed DMG, and updating the website. The app source revision is `9b896125966d36a0fc95cd43a4df3acafeb53154` on `feat/viewing-key-security`. The optimized release build completed in 102.04 seconds.

`ZECBuyingPrice-0.2.0-arm64.dmg` is 50,001,325 bytes (47.7 MiB), with SHA-256 `dcff1b788171ca49a3e88fd857fb5ca15df4abaf99fd25a3bd18c28d5049619c`. The app and DMG passed code-signature verification. The app uses Developer ID Application: Yash Garg (9UR77TD484), a secure timestamp, and hardened runtime. Read-only inspection of the produced DMG confirmed the included app passes strict deep signature verification, reports version 0.2.0, runs on arm64, requires macOS 14, and includes the Swift compatibility library. Disk-image integrity verification passed.

Apple notarization submission was blocked by automatic approval review because signing authorization did not explicitly cover uploading the payload to Apple. The user was asked for that approval. No submission was made, and the current release metadata does not claim notarization or Gatekeeper acceptance.

The website privacy, setup, FAQ, release notes, and related guides describe encrypted credential/storage protection, continued syncing with the interface locked, and the limits of shutdown/crash cleanup. The user confirmed native authentication and showed active mainnet progress with the interface locked. Tests remain deferred; no new cases or suite runs were added to this release work. Earlier verification above describes the prior website deployment and does not establish the status of this new release.
