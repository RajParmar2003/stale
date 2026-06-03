# Changelog

All notable changes to Stale are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); this project uses semantic versioning.

## [1.1.0] — 2026-05-29

### Added
- **Two distinct entities — Local and Web.** Stale now detects whether it's running as the
  local instance (`run.command` / localhost) or the deployed web instance, and identifies itself
  with a **LOCAL** (amber) or **WEB** (blue) badge. `?build=web|local` or a `<meta name="stale-build">`
  can override detection.
- **Per-entity storage namespacing** — IndexedDB (`stale-local` / `stale-web`) and the
  service-worker cache (`stale-shell-local-v1` / `stale-shell-web-v1`) are separate, so the two
  entities never share data or interfere. Verified by an isolation test (see `docs/TESTING.md`).
- **`run.command`** double-click launcher for the local entity (auto-picks a free port, opens the browser).
- New doc: [`docs/ENTITIES.md`](docs/ENTITIES.md) — the local-vs-web architecture and isolation matrix.

### Changed
- Both entities share one engine, so behaviour and performance are identical by construction.

### Migration
- The pre-1.1 single `stale-db` database is deleted automatically on first launch.

## [1.0.0] — 2026-05-29

First complete, tested release.

### Added
- Client-side app-update checker: paste `system_profiler` JSON → matched against the
  Homebrew Cask database (~7,600 apps), entirely in the browser.
- **Freshness score** (0–100) with an animated SVG gauge and colour states.
- Grouping: *Worth updating*, *Self-updating*, *Up to date*, *Not tracked*, *Mac App Store*.
- **Severity** badges (major / minor / patch) from version-gap analysis.
- **Batch `brew` command** copy for all actionable apps.
- **Diff since last scan** and **resume last scan** via IndexedDB.
- **Calendar reminder** (`.ics`) download to re-check in two weeks.
- **PWA**: manifest, service worker (offline app shell), generated icons; installable to the macOS Dock.
- Drag-and-drop `.json` input; sample-data mode.
- Light/dark themes, reduced-motion support, keyboard/screen-reader accessibility.

### Fixed
- **Name normalisation bug** caught in testing: `String.normalize("NFKD")` decomposed the
  trademark symbol `™` (U+2122) into the letters "TM" *before* the symbol-strip step, so an
  app named "Something™" normalised to `somethingtm` and failed to match its cask. Symbols are
  now stripped before NFKD, and combining diacritics are removed (`café` → `cafe`).
  See `docs/TESTING.md`.

### Notes
- Project evolved from research (see `docs/DECISIONS.md`): two earlier concepts (a code-typing
  game and a pairwise ranker) were rejected as saturated; the MacUpdater shutdown was identified
  as a validated, unoccupied gap.
