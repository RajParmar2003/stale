# What Doesn't Work (and Why) ⚠️

> Honest, evidence-backed record of constraints, failure modes, and things deliberately
> not built. Each entry says **why**, with code or data. Mirrors `WINS.md`.
> Last updated: 2026-05-29.

Severity legend: 🔴 real limitation users will hit · 🟡 edge case / partial · ⚪ deliberate non-goal.

---

## 🔴 1. Coverage is limited to Homebrew Cask (~7,600 apps)

**What:** Apps not packaged as a Homebrew cask cannot be checked and land in **"Not in
Homebrew's database."**

**Evidence:** On the author's real Mac, **18 of 48** checkable third-party apps were unmatched
(internal/niche tools, some Microsoft apps, App-Store-only apps). The database is finite:
```js
// app.js — the match simply misses if no cask claims the app name
const cask = state.index.get(norm(app.file)) || state.index.get(norm(app.name));
if (!cask) { groups.unknown.push({ app, cask: null, status: "unknown" }); continue; }
```
**Why it can't be trivially fixed:** there is no single universal "latest version of every Mac
app" database. Homebrew is the largest open one. Sparkle appcasts (see §7) would extend coverage
but require per-app feed URLs and per-host CORS, which a static site can't reliably fetch.

**Mitigation:** "Not tracked" is shown as its own group and the disclaimer states explicitly
that *not tracked ≠ up to date.* We never imply coverage we don't have.

---

## 🔴 2. Version comparison is a heuristic, not authoritative

**What:** We compare dotted-numeric version components. This is correct for the vast majority of
apps but **cannot** resolve every real-world version string.

**Evidence / examples that are undecidable:**
```js
cmpVer("latest", "1.0")        // → null  (non-numeric)
cmpVer("2024.3", "24.3")       // → 1     (date-style vs semver — looks "newer" but may be same)
cmpVer("1.2-beta", "1.2")      // → 0     (pre-release suffix ignored: numbers equal)
```
The cask's version may also be formatted differently from what `system_profiler` reports
(e.g. cask `7.0.5.81138` for Zoom vs a shorter `CFBundleShortVersionString`).

**Why:** there is no universal version grammar across thousands of vendors. A full semver +
calendar-version + pre-release parser would add complexity and *still* mis-handle bespoke schemes.

**Mitigation:** when the comparison is undecidable we mark the app **"version differs"** and never
assert "outdated"/"current." The UI disclaimer says *always confirm before updating.* Pre-release
handling is a known soft spot (documented, not hidden).

---

## 🔴 3. Requires running one Terminal command (no auto-scan)

**What:** The user must run `system_profiler SPApplicationsDataType -json | pbcopy` and paste.

**Why:** A browser **cannot** read `/Applications` or app bundles — the sandbox forbids it.
This is the fundamental trade for "no install / fully private." A native app (what MacUpdater
was) can auto-scan; a web app cannot.

**Mitigation:** Stale copies the exact command for you and also accepts a dropped `.json` file.
Friction is one command, once per scan.

---

## 🟡 4. `auto_updates` is trusted from Homebrew, and can be stale

**What:** Apps with `auto_updates: true` are routed to "Self-updating" and cushioned in the score.
But an app that self-updates *only when launched* may genuinely be behind if you haven't opened it.

**Evidence:** Chrome/VS Code/Figma/Rectangle all report `auto_updates: true`; on the real Mac
several were behind yet correctly de-emphasised. That's usually right, occasionally not.

**Mitigation:** Self-updating apps are still listed with their version delta — just collapsed and
not counted as "worth updating." The user can expand and act.

---

## 🟡 5. First load downloads ~15 MB (the cask DB)

**What:** The initial DB fetch is ~15 MB JSON (gzipped far smaller over the wire; ~400 ms on a
fast link). Subsequent loads use the IndexedDB cache (12 h).

**Why:** We pull the whole cask list to match offline/instantly rather than making per-app calls
(which would be thousands of requests). Trade chosen intentionally.

**Mitigation:** cached after first load; offline fallback to the last copy.

---

## 🟡 6. `brew install --cask` assumes the user has/wants Homebrew

**What:** The batch command and per-app pills emit Homebrew commands. They're useless to someone
who doesn't use Homebrew, and `brew` may "adopt" an app installed manually.

**Mitigation:** Every app also has a **homepage link** (↗) as a brew-free path. The brew command
is an optional convenience, clearly labelled.

---

## ⚪ 7. Sparkle / vendor-feed coverage — not built

**What:** Many apps not in Homebrew expose a **Sparkle appcast** (XML) with their latest version.
Reading those would raise coverage.

**Why not yet:** each appcast is a different URL on a different host; static-site `fetch` hits CORS
walls per host, and there's no registry mapping app → appcast. Doing it well needs either a curated
map or a tiny proxy (which breaks the zero-server promise). Deferred deliberately.

---

## ⚪ 8. True background reminders — not possible from a static web app

**What:** Stale can't push a notification days later on its own.

**Why:** Web Push requires a service worker **and a push server**; a purely static, server-less app
has nowhere to send/trigger from. `Notification` alone doesn't fire when the tab is closed.

**Mitigation:** we ship a **`.ics` calendar reminder** (fires via the OS calendar) and a **resume**
banner that greets returning users with a diff — retention without a server.

---

## ⚪ 9. No crowd/percentile stats ("fresher than X% of Macs")

**Why not:** that needs collecting scans on a backend — directly contradicting the privacy promise
that nothing leaves the device. Out of scope by design.

---

## Tooling note (not a product flaw)

During testing, the **preview/eval harness intermittently duplicated or garbled returned output**
(e.g. emitting `"multiGroup":[],"multiGroup":[]`, or rendering screenshots as text). This is an
artifact of the testing environment, **not** the app. Correctness was confirmed by returning
single `JSON.stringify` payloads and cross-checking values; the app's own console was clean
throughout.
