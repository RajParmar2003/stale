# What Works ✅

> Things verified to work, with the evidence. Mirrors `LIMITATIONS.md` (what doesn't).
> Last verified: 2026-05-29 against the live Homebrew API and the author's real Mac.

## Core engine

### ✅ Homebrew DB loads from the browser (no backend, no proxy)
Verified empirically: `fetch("https://formulae.brew.sh/api/cask.json")` → HTTP 200, CORS
passes, **7,669 casks**, ~400 ms, ~15 MB JSON. Cached in IndexedDB (12 h TTL) for instant
repeat loads and offline use; falls back to a stale cached copy if the network is down.

### ✅ Matching is accurate on real data
Pilot run against the author's **actual installed apps**, verified against a ground-truth file
(`md5 1ea7861c`, read independently with Python) — reproducible signature
**`353/93/1/6/9/24/11`** (`parsed/score/action/self/ok/unknown/mas`), confirmed across repeated runs:
- Parsed **365 → 353 after dedupe** (12 duplicate entries removed — real exports contain them).
- **Freshness score: 93** ("Looking good" — this Mac is well-kept).
- Matched **16** third-party apps to Homebrew casks (1 worth updating + 6 self-updating + 9 up to date);
  **24** correctly marked "Not tracked"; **11** routed to "Mac App Store"; Apple's 307 bundled apps
  correctly excluded.
- "Worth updating" (real, non-self-updating, behind): **LibreOffice** `26.2.0.3 → 26.2.3` (patch).
- Self-updating-but-behind correctly de-emphasised: Chrome, VS Code, ChatGPT Atlas, Antigravity, etc.
- **No app appeared in more than one group** (`OVERLAPS=0`) — routing is exclusive.

> Note: earlier drafts cited other numbers (312/67, or Cursor/Notion). Those came from **stale data
> files / a test race** — see `TESTING.md §4`. The figures above are the ground-truth-verified run.

### ✅ Version comparison handles the tricky cases
Unit assertions (all pass):
- `1.10` > `1.9` (numeric, not lexical) ✔
- `1.2.0` == `1.2` ✔
- comma-build `1.2,99` == `1.2` (cask `version,build` form) ✔
- non-numeric / empty → `null` (undecidable, flagged rather than guessed) ✔

### ✅ Name normalisation (after the bug fix — see TESTING.md)
- `Visual Studio Code.app` → `visualstudiocode` ✔
- `Foo™ Bar®` → `foobar` ✔ (was the bug; now fixed)
- `Café` → `cafe` ✔ (accent folding)
- `Thing℠` → `thing` ✔

### ✅ Dedupe keeps the best duplicate
Two `Epic Games Launcher` / two `Cursor.app` entries collapse to one, preferring the entry
that has a version, then the higher version.

### ✅ Freshness score behaves sensibly
- Real Mac → **93** ("Looking good"). Sample data → **73** ("Looking good").
- Empty list → `null`; all-App-Store list → `null` (nothing checkable). Handled, no crash.
- Self-updating apps are cushioned so they don't tank the score unfairly.

## Features

- ✅ **Animated gauge** — count-up + colour (green ≥80 / amber ≥50 / red <50), respects `prefers-reduced-motion`.
- ✅ **Grouping UI** — action / self-updating / ok / not-tracked / App Store, with severity badges, brew pills, homepage links.
- ✅ **Batch brew command** — `data-batch` builds `brew install --cask <tokens…>`; verified copy for the action group.
- ✅ **Search/filter** — `filter "chrome"` narrows to matching apps and auto-opens groups; clearing restores all.
- ✅ **Summary chips jump** to their group.
- ✅ **Calendar reminder** — `buildICS()` output validated: `BEGIN/END:VCALENDAR`, `VEVENT`, `VALARM`, CRLF line endings, `DTSTART:YYYYMMDDThhmmssZ` 2 weeks out.
- ✅ **Sample-data mode** — one click renders a full, realistic report (great for first-run + testing).
- ✅ **Clean console** — no errors or warnings during load, scan, filter, or render.

## Platform / professional

- ✅ **PWA installs** — `manifest.webmanifest` valid; icons generated (192/512/maskable/apple-touch) and visually verified; service worker caches the app shell resiliently (`Promise.allSettled`, won't fail install on one missing asset).
- ✅ **Light & dark** via `prefers-color-scheme`; **reduced-motion** honoured; semantic HTML + ARIA + `:focus-visible`.
- ✅ **Buildless** — runs from any static server; `python3 -m http.server` for dev.
- ✅ **Repo hygiene** — git, MIT license, `.gitignore` (excludes real user data via `*.test.json`), README, CHANGELOG, structured `docs/`.
- ✅ **Privacy by construction** — only outbound request is the Homebrew GET; user data stays in memory + local IndexedDB.
