# Audit & Hardening (PR #5)

> Full review pass over the redesign + four feature PRs: a repeatable test suite, real-data
> regression, and the bugs the audit surfaced and fixed. Date: 2026-06-03.

## Test suite

`tests/test.html` loads the **real shipped engine** (`assets/js/app.js`) and runs 29 assertions
against it, plus a real-data fixture (`tests/apps.fixture.json` — a curated subset of the
author's actual machine, including the LibreOffice the user updated and a genuine duplicate
Discord entry). Open `/tests/test.html` in a browser; results render on the page and are exposed
on `window.__TESTS` for headless reads.

**Result: 29/29 passing.** Coverage:
- Version compare: `<`, `>`, numeric-not-lexical (`1.10 > 1.9`), `1.2.0 == 1.2`, comma-build,
  empty/non-numeric → null, and the real case `26.2.3.2` vs `26.2.3`.
- Severity major/minor/patch/unknown.
- Normalization: `.app`/space/case, `™`/`®`/`℠`, accent folding (`café → cafe`).
- Parsing: junk → error, empty → none, `bundle_id` read.
- Dedupe keeps the higher version (verified on the duplicate Discord: 10 → 9).
- Freshness edge case (empty → null).
- DB-dependent: Homebrew DB loads (7,694 casks), `analyze` produces groups, **no app in two
  groups**, and **LibreOffice `26.2.3.2` is correctly NOT in "worth updating"** (status=ahead).
- ICS reminder well-formed.

## Real-data regression (the user's LibreOffice update)

The user updated LibreOffice via Stale's copy-command (6.20.0-era → **26.2.3.2**). Re-running the
real fixture: `action: 0` — nothing is falsely flagged, and LibreOffice resolves to `ahead`
of Homebrew's `26.2.3`. The copy-command → terminal → updated → re-scan loop is confirmed working.

## Bugs found and fixed during the audit

### 1. 🔴 iTunes `/lookup` has no CORS → App Store data silently failed in the browser
**Symptom:** Mac App Store rows fell back to "manage in the App Store" with no version.
**Root cause:** Apple's `itunes.apple.com/**lookup**` endpoint returns `HTTP 200` but **omits**
`Access-Control-Allow-Origin`, so the browser blocks the response. The `/**search**` endpoint
*does* send CORS headers. The code used `/lookup` whenever a bundleId was present.
**Evidence:**
```
curl -I -H "Origin: http://localhost:4199" .../lookup?bundleId=...   → (no ACAO header)  ×5
curl -I -H "Origin: http://localhost:4199" .../search?term=...       → access-control-allow-origin: http://localhost:4199
```
**Fix:** always use `/search` from the browser, then disambiguate the result by `bundleId`
(exact) → exact name → name prefix. Verified: Things3 now returns `3.22.11` + artwork + store
URL, and the row renders `3.19.0 → 3.22.11 MINOR` with the real App Store icon.

### 2. 🟡 Engine threw without the full app DOM (blocked the test harness)
**Root cause:** `boot()` ran before `window.Stale` was assigned, and `setDb()` touched
`dom.dbStatus` (null on the test page), throwing before the test API existed.
**Fix:** assign `window.Stale` *before* `boot()`; `boot()` detects missing UI and only loads the
DB; `setDb`/`applyBuildIdentity`/`checkBtn` access made null-safe. The engine is now usable
headlessly — which is what makes the test suite possible.

### 3. 🟡 Stale code served after updates (service worker)
**Root cause:** cache-first SW served old HTML/JS/CSS after a deploy.
**Fix (shipped in PR #3):** network-first for code, cache-first for static assets, external APIs
bypass the SW. Confirmed this was the cause of repeated dev-cache confusion; the fix prevents
users from getting stale code post-update too.

## Verified mechanisms (standalone Swift harnesses)

- **Real icon extraction** + path allowlist: real apps serve PNGs; `/etc/passwd` rejected (5/5).
- **Bundle-ID augmentation**: Music→com.apple.Music, Spotify→com.spotify.client, missing→nil.
- **Update token validation**: 8/8 (injection/traversal/empty/caps rejected).
- **Hidden-process streaming**: brew output streamed, clean termination, exit code propagated.

## Residual limitations (unchanged, documented in LIMITATIONS.md)

- App Store name-search can mis-match an app with an ambiguous title (mitigated by bundleId
  disambiguation when the native scanner provides it). Best-effort by design.
- Homebrew-only coverage for non-MAS apps; heuristic version compare.
- Native window visual click-test of the live brew upgrade still pending a real notarized run.
