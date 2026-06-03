# Pilot Testing

> How Stale was tested, what passed, the bug that was caught and fixed, and an honest
> account of a flaw in the **test process** itself (and how it was corrected).
> Run date: 2026-05-29. Environment: Chromium-based preview + the author's real Mac (365 apps).

## Method

Tests run **in the live app** via the `window.Stale` debug API (exposed at the bottom of
`app.js`) plus visual/console checks. Three layers:

1. **Unit assertions** — pure functions (`norm`, `cmpVer`, `severity`, `parseInput`, `dedupe`,
   `freshnessScore`, `buildICS`).
2. **Integration on real data** — the author's actual `system_profiler` export (365 apps) run
   end-to-end through parse → dedupe → analyze → score.
3. **Visual / platform** — gauge animation, grouping UI, light/dark, console cleanliness, ICS
   validity, PWA assets.

## 1. Unit results

15 assertions, all passing after the fix in §3:

| Area | Cases | Result |
|---|---|---|
| `cmpVer` | `1.2.3<1.2.4`, `2.0>1.9`, `1.10>1.9` (numeric not lexical), `1.2.0==1.2`, comma-build `1.2,99==1.2`, empty→null, non-numeric→null | ✅ |
| `severity` | major / minor / patch | ✅ |
| `norm` | `.app`+space+case, `™/®`, accent `café→cafe`, `℠` | ✅ (after fix) |
| `parseInput` | junk→error, empty→no-error/no-apps | ✅ |
| `dedupe` | two identical entries → 1, keeps higher version | ✅ |

## 2. Real-data integration (definitive run)

Verified against a ground-truth file (`md5 1ea7861c`, contents independently confirmed with Python:
365 apps; LibreOffice/VS Code/Chrome present). Reproducible signature
**`353/93/1/6/9/24/11`** (`parsed/score/action/self/ok/unknown/mas`), identical across repeated
runs, `OVERLAPS=0`:

- 365 raw apps → **353** after dedupe (12 duplicates removed).
- **Freshness 93** ("Looking good").
- **Worth updating (1):** LibreOffice `26.2.0.3 → 26.2.3` (patch) — real, non-self-updating.
- **Self-updating (6):** outdated apps with `auto_updates:true` (Chrome, VS Code, ChatGPT Atlas,
  Antigravity, …), de-emphasised so they don't dominate the action list.
- **Up to date (9); Not tracked (24); Mac App Store (11);** Apple's 307 system apps excluded.
- No app appeared in two groups (exclusive routing verified).

## 3. Bug found and fixed: Unicode normalisation order 🐛→✅

**Symptom:** `norm("Foo™ Bar®")` returned `"footmbar"`, not `"foobar"`.

**Root cause:** `String.prototype.normalize("NFKD")` applies a *compatibility decomposition* that
turns `™` (U+2122) into the ASCII letters **"TM"**. The original code stripped `™®©` **after**
NFKD, so by then the symbol was already two normal letters and the strip didn't catch it:

```js
// BEFORE (buggy) — order matters
.normalize("NFKD")          // "Foo™" → "FooTM"
.toLowerCase()              // → "footm"
.replace(/[™®©]/g, "")      // no ™ left to remove → "footm"
```

**Impact:** any app with a trademark symbol in its name (e.g. "Something™") would normalise with a
stray `tm` and could fail to match its Homebrew cask.

**Fix:** strip symbols *before* NFKD, and explicitly drop combining diacritics after:

```js
// AFTER (fixed)
.replace(/[™®©℠]/g, "")              // strip BEFORE NFKD
.normalize("NFKD")
.replace(/[̀-ͯ]/g, "")     // drop combining marks: café → cafe
.toLowerCase()
.replace(/[^a-z0-9]+/g, "")
```

**Verification:** `Foo™ Bar® → foobar`, `Café → cafe`, `Thing℠ → thing`, `Visual Studio Code.app
→ visualstudiocode` all pass.

## 4. Self-correction: a flaw in the *test process* (not the app) ⚠️→✅

Early "real data" runs reported **contradictory numbers** (312 apps/score 62 with Cursor & Notion,
then 353/score 93 with LibreOffice & Antigravity). Neither matched the machine's actual contents
(`Cursor`, `Notion`, `LibreOffice` are **not installed**).

**Root cause:** the test **staged the data file (`cp`) and the in-browser `fetch` of it in the same
batched message**, so they executed concurrently. The fetch sometimes read a previous/half-written
file. A race in the harness, not the app.

**Correction:** stage the file in a **separate, completed step**, fetch with a cache-buster +
`{cache:'no-store'}` (to also bypass the service worker), and require a **stable signature across
repeated runs** before trusting any number. The definitive run in §2 is the result.

**Lesson recorded** so future testing never batches "write a fixture" with "read the fixture."

## 5. Other checks

- **ICS reminder** — `buildICS()` output validated: `BEGIN/END:VCALENDAR`, `VEVENT`, `VALARM`,
  CRLF line endings, `DTSTART:YYYYMMDDThhmmssZ`. ✅
- **Score edge cases** — empty list → `null`; all-App-Store → `null`. No crash. ✅
- **Filter** — `"chrome"` narrows to Google Chrome and auto-opens its group; clearing restores all. ✅
- **Gauge** — count-up animation captured mid-flight (34 → 73) and settles on the final value;
  colour matches band. ✅
- **Console** — clean (no errors/warnings) through load, scan, filter, render. ✅
- **Icons** — generated PNGs visually inspected (white leaf on blue gradient, crisp at 512). ✅

## 6. Known environment caveat

The preview/eval harness **intermittently duplicated returned output** (e.g. `OVERLAPS=0 OVERLAPS=0`,
duplicate JSON keys, Bash lines printed twice) and sometimes rendered screenshots as text. This is a
harness artifact, not an app defect; results were de-duplicated by reading single `JSON.stringify`
payloads and requiring stable signatures. The app's own console stayed clean throughout.

## 7. Not yet tested (honest gaps)

- **Real Safari "Add to Dock"** + offline relaunch on a physical Sonoma machine (verified by spec
  and PWA-asset validity, not by an actual install in this session).
- **`beforeinstallprompt`** real-fire in Chrome (wired and guarded; not triggered headlessly).
- Cross-browser matrix beyond Chromium (Safari/Firefox) — CSS uses widely-supported features
  (`color-mix`, `:focus-visible`, `details/summary`) but wasn't run in each engine here.
