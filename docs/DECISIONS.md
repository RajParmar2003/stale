# Decisions & Research Trail

> Why Stale exists, and the evidence that it occupies a genuine gap. This is the
> "researched proof of non-existence" record.

## The brief

Build something **original** with **researched proof** that it doesn't already exist —
explicitly *not* "the millionth one doing something." Earlier explorations (a daily
code-typing game; a pairwise "rank anything" tool) were rejected by the stakeholder as
saturated. We switched method: **gap-first, validate before building.**

## Concepts tested and rejected (with evidence)

Twelve concepts were searched. Nearly all were saturated:

| Concept | Verdict | Evidence |
|---|---|---|
| Code-typing race | Saturated | Monkeytype, TypeRacer |
| Pairwise ranker | Saturated | dozens of "tier list / rank anything" tools |
| Private local-AI journal/vent | Saturated | Dottie, Enclave AI, Locally AI, Jan |
| AI party / social-deduction game | Saturated | imposter.ai, Impostor Who?, AI Against Humanity, cardyard.ai |
| "Simulated reader reactions" while writing | Taken | Grammarly "Reader Reactions" agent |
| AI debate / steelman | Saturated | ArguFight, Opinionate, Symbai, DebateAI |
| Internal-clock / time-perception test | Saturated | Inner Timer, Chronos, Dialed.gg, Clock Blockers |
| Text subtext decoder ("are they mad?") | Saturated (2025) | Subtext.ing, Decoded, Relationship AI |
| macOS `.icns` icon generator (web) | Saturated | icon.msgbyte.com, convertico |

**Meta-finding:** any concept expressible as *"[familiar genre] + AI"* or *"self-test toy"*
was already built in the 2023–2025 gold rush. Originality had to come from elsewhere.

## The gap we found

The stakeholder chose the **"Mac tool gap"** territory (easiest to *prove*). Research surfaced
a fresh, specific, evidence-backed opening:

- **MacUpdater was discontinued on 2026-01-01**, and *"no single app currently replicates
  everything MacUpdater did."*
  - [TidBITS — MacUpdater Shuts Down](https://tidbits.com/2026/01/09/macupdater-shuts-down-leaving-users-searching-for-alternatives/)
  - [TheSweetBits — Discontinued, what now](https://thesweetbits.com/macupdater-discontinued-what-happens-now-and-what-are-the-alternatives/)
  - [Nektony — top updaters 2026](https://nektony.com/reviews/top-updaters-for-mac)
- Every alternative (**Latest, MacUpdate Desktop, App Cleaner**) is a **native install**.
  A search for a **browser-based, no-install** "paste your apps, check for updates" tool
  returned **nothing**. → the web form is unoccupied.

## Why it's now technically possible (the enabling primitives)

1. **Homebrew's official JSON API is browser-fetchable.** `https://formulae.brew.sh/api/cask.json`
   is `brew info --json=v2 --cask` for ~7,600 casks, CORS-open.
   - [Homebrew API docs](https://formulae.brew.sh/docs/api/)
   - Empirically verified from the browser: HTTP 200, CORS passes, ~7,669 entries, ~400 ms,
     each cask carries `token`, `name`, `version`, `homepage`, `auto_updates`, `artifacts`.
2. **macOS Safari 17 / Sonoma "Add to Dock"** turns any web page into a Dock app.
   - [Apple Support — Use Safari web apps on Mac](https://support.apple.com/en-us/104996)
   - This is what lets a *web* tool legitimately target the Dock.

## Key product decisions

- **Separate "self-updating" from "worth updating."** Real data shows most popular apps
  (`auto_updates: true`: Chrome, VS Code, Figma, Rectangle, Zoom…) fix themselves. MacUpdater's
  real value was the **long tail that doesn't**. Surfacing those first is the core insight.
- **Zero backend, ever.** The privacy story ("your app list never leaves your Mac") is the
  product's moat vs. native incumbents. Features that would need a server (crowd percentile
  stats) are deliberately deferred to preserve it.
- **Buildless static app.** Auditable by anyone — important for a privacy tool.
- **Honesty over false confidence.** Version compare is heuristic; undecidable comparisons are
  flagged ("version differs"), never guessed. Unmatched apps are "Not tracked," explicitly *not*
  "up to date."

## Honest caveat on "proof of non-existence"

Absolute proof is impossible. The standard met here is *diligent search across web + app stores
returned no direct competitor in the web/no-install/private form*, plus a freshly-vacated
incumbent (MacUpdater). That is the strongest defensible "first" available.
