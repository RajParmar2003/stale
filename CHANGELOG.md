# Changelog

All notable changes to Stale are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); this project uses semantic versioning.

## [Unreleased]

### Added — real app logos
- The native app now shows each app's **real icon** instead of a colored letter tile.
  A `stale-icon://` scheme handler renders `NSWorkspace.icon(forFile:)` to PNG on demand
  (lazy per visible row, in-process cache), keyed by the app's on-disk path.
- **Security:** the icon handler only serves paths under standard app directories
  (`/Applications`, `/System/Applications`, `/System/Library`, `/Library`) — verified a
  traversal probe (`/etc/passwd`) is rejected.
- **Web/Local fallback:** rows render an `<img>` that falls back to the colored initial on
  error, so non-native contexts degrade cleanly (verified: no broken images).
- Avatar keeps a hairline ring when showing a real logo so pale/transparent icons retain an edge.

### Changed — UI redesign (sharp / minimal)
- **Typography:** adopted **Geist** + **Geist Mono** (SIL OFL), bundled in `assets/fonts/`
  for offline parity. Replaces the rounded system font with a sharp neo-grotesque; tighter
  tracking on headings, uppercase tracked micro-labels.
- **Surfaces:** tighter corner radii (6/9/12px), hairline borders over heavy shadows, flat
  graphite background (removed decorative radial gradients), retuned light + dark palettes.
- **Actions:** primary buttons are now monochrome graphite (blue reserved for links/state).
- **Copy:** trimmed hero, privacy line, and disclaimer for a to-the-point read.
- New `docs/DESIGN.md` documents the system + the accessibility/second-pass audit.
- Avatar markup now supports real `<img>` logos (wired in a later PR).



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
