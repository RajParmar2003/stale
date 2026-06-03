# Stale — Project Plan & Tracker

> Living document. Updated as work progresses so nothing is lost between sessions.
> Last updated: **2026-05-29**.

## 1. What Stale is

A free, **client-side, no-install** web tool that tells Mac users which of their installed
apps are out of date — the gap left when **MacUpdater shut down on 2026-01-01**. It matches a
user's installed apps (from `system_profiler`) against the **Homebrew Cask** version database,
entirely in the browser. Installable to the macOS Dock as a PWA.

## 2. Goals (from the brief)

| Goal | Status |
|---|---|
| Genuinely original, with researched proof of the gap | ✅ done — see `DECISIONS.md` |
| Robustly works, no flaws | ✅ verified — see `TESTING.md` / `LIMITATIONS.md` |
| Professional codebase (VCS, license, structured files, docs) | ✅ done |
| Top-tier macOS-native UI, blistering UX | ✅ done |
| Retention features → earns a Dock spot (not "installed and forgotten") | ✅ done (PWA + score + diff + resume + reminders) |
| Full pilot testing, incl. on the real machine | ✅ done — 365 real apps |
| MD docs: plan, wins, limitations, testing | ✅ this set |

## 3. Architecture (buildless static app)

```
stale/
├── index.html                  # markup + PWA wiring
├── manifest.webmanifest        # PWA / Dock metadata
├── service-worker.js           # offline app-shell cache
├── assets/
│   ├── css/styles.css          # macOS-native aesthetic, light/dark, gauge
│   ├── js/app.js               # all logic; 10 numbered sections; window.Stale test API
│   └── icons/                  # PNG icons (192/512/maskable/apple-touch) + favicon.svg
├── docs/                       # PROJECT_PLAN, DECISIONS, WINS, LIMITATIONS, TESTING
├── README.md  CHANGELOG.md  LICENSE  package.json  .gitignore
```

Why buildless: instant load, host anywhere, trivially auditable (key for a privacy tool), no
toolchain rot. Trade-off accepted: no bundling/minification (file sizes are tiny anyway).

## 4. Feature checklist

- [x] Fetch + cache Homebrew Cask DB (IndexedDB, 12h TTL, offline fallback)
- [x] Parse `system_profiler` JSON; tolerate bare arrays
- [x] Dedupe duplicate entries (real exports contain them)
- [x] Name normalisation (handles `.app`, ™/®/©/℠, accents, punctuation, case)
- [x] Version compare (numeric, comma-build aware, undecidable → null)
- [x] Severity (major/minor/patch)
- [x] Grouping (action / self-updating / ok / unknown / mas), Apple apps excluded
- [x] Freshness score (weighted, self-updaters cushioned)
- [x] Animated gauge + count-up + colour states
- [x] Diff since last scan + resume (IndexedDB)
- [x] Batch `brew install --cask` copy
- [x] Per-app `brew` pill + homepage link
- [x] Search/filter; summary chips jump to groups
- [x] Calendar reminder (.ics)
- [x] PWA: manifest + service worker + icons; "Add to Dock" affordance
- [x] Light/dark, reduced-motion, a11y
- [x] `window.Stale` debug/test API

## 5. Known limitations (summary — full detail in LIMITATIONS.md)

1. Coverage = Homebrew casks (~7,600). Apps outside it show "Not tracked", not "current".
2. Version comparison is heuristic; some version strings are undecidable → flagged, not guessed.
3. Requires running one Terminal command (no native auto-scan from a browser).
4. True background notifications aren't possible from a static web app (we use `.ics` + resume instead).

## 6. Ideas / future (not built)

- Pull **Sparkle appcast** versions for apps Homebrew misses (wider coverage; needs per-app feed URLs + CORS handling).
- Optional tiny menubar companion (native) that runs the scan automatically.
- Shareable "Freshness card" image for social proof.
- Crowd stats ("your Mac is fresher than X% of scans") — would require a backend, breaking the zero-server promise; deliberately deferred.

## 7. Verification log

See `TESTING.md` for the full pilot run (15 unit assertions + 365-app real-data test + PWA/ICS/edge cases) and the one bug found-and-fixed.
