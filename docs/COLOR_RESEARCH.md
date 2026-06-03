# Color Research — the top 25 Mac apps

> A data-driven look at the color schemes of 25 of the most-used / most-celebrated Mac apps,
> to sanity-check Stale's own palette. Method: fetch each app's real icon (Apple iTunes
> Search API, `artworkUrl512`), extract dominant hues with Pillow (hue-binned, saturation×value
> weighted, background-neutral filtered), then **cross-check against documented brand colors**
> (brand guidelines win where they exist; pixel data fills the rest). Date: 2026-06-03.

App pool drawn from 2026 "best Mac apps" roundups + the 2025 Apple Design Awards (sources below).

## The 25 apps and their colors

| App | Primary | Family | Accent(s) | Source |
|-----|---------|--------|-----------|--------|
| Google Chrome | `#4285F4` | Blue | `#34A853` `#FBBC05` `#EA4335` | brand |
| Spotify | `#1DB954` | Green | `#191414` (black) | brand |
| Zoom | `#0B5CFF` | Blue | — | brand |
| Slack | `#4A154B` | Aubergine | `#36C5F0` `#2EB67D` `#ECB22E` `#E01E5A` | brand |
| Notion | `#000000` | Neutral | `#FFFFFF` | brand |
| Figma | `#0ACF83` | Green | `#A259FF` `#F24E1E` `#FF7262` `#1ABCFE` | brand |
| Visual Studio Code | `#0065A9` | Blue | `#007ACC` | brand |
| WhatsApp | `#25D366` | Green | `#075E54` `#128C7E` | brand |
| Microsoft Word | `#2B7CD3` | Blue | `#1B5EBE` | brand |
| Things 3 | `#3A86FB` | Blue | `#1A4F9E` | pixel+brand |
| Raycast | `#FF6363` | Red | `#000000` | pixel |
| 1Password | `#0364D3` | Blue | `#1A8CFF` | brand |
| Discord | `#5865F2` | Blue (blurple) | `#404EED` | brand |
| Telegram | `#26A5E4` | Blue | `#0088CC` | brand |
| ChatGPT | `#000000` | Neutral | `#FFFFFF` (+legacy teal `#10A37F`) | brand |
| Craft | `#007AFF` | Blue | `#FF61FE` (magenta) | pixel |
| Bear | `#D7493A` | Red | `#F96161` | brand |
| Fantastical | `#F5402C` | Red | `#FF3B30` | brand |
| CleanMyMac | `#D613B6` | Magenta | `#867FD2` (violet) | pixel |
| Spark Mail | `#00A4FF` | Blue | `#FED909` (yellow) | pixel |
| Microsoft Excel | `#217346` | Green | `#33C481` | brand |
| VLC | `#FF8800` | Orange | `#222222` | brand |
| Arc | `#FE4F35` | Red→multi gradient | `#01E784` | pixel |
| iA Writer | `#00A8FE` | Cyan | `#000000` | pixel |
| Pixelmator Pro | `#FC6E11` | Orange | `#B62327` | pixel |

## What the data shows

**Primary-hue distribution (n = 25):**

```
Blue      ███████████  11   (44%)
Green     ████          4
Red       ████          4
Magenta   ██            2
Neutral   ██            2   (Notion, ChatGPT — pure black/white)
Orange    ██            2
```

1. **Blue dominates — 44% of top apps.** It's the default "trustworthy / utility / productivity"
   signal (Chrome, Zoom, VSCode, Word, Things, 1Password, Discord, Telegram, Craft, Spark, iA).
   A productivity/system utility that wants to feel native and trustworthy lives in this band.
2. **A vivid green vs. warm-red split for the rest.** Green = "go / healthy / fresh"
   (Spotify, WhatsApp, Figma, Excel). Warm red/orange = "energy / attention"
   (Fantastical, Bear, VLC, Arc, Pixelmator, Raycast).
3. **High saturation, mid-high value.** Almost every primary is a *saturated, bright* hue
   (S ≈ 70–100%, V ≈ 80–100%) — flat, confident, not muted. Pastels are absent at the top.
4. **Restraint in count.** Most use **one** saturated brand color + black/white/grey. The
   multi-color exceptions are deliberately "platform/canvas" brands (Google, Slack, Figma).
5. **Monochrome is a real, premium signal.** Notion and ChatGPT win on pure black/white —
   a viable "serious tool" alternative to a colored brand.
6. **Semantic color triad is consistent industry-wide:** green = good/updated, amber/orange =
   attention, red = urgent. (Matches how Stale already uses color for *state*.)

## How Stale's palette compares (validation)

Stale's current accents vs. the top-app medians:

| Token | Stale (light) | Top-app cluster | Verdict |
|-------|---------------|-----------------|---------|
| `--blue` (accent/links) | `#0a6dff` | `#0B5CFF`–`#4285F4` (the dominant family) | ✅ dead-center of the most-common hue |
| `--green` (fresh / up-to-date) | `#1aa35a` | `#1DB954` / `#25D366` / `#217346` | ✅ same "healthy green" band |
| `--amber` (worth updating) | `#e8820e` | `#FF8800` / `#ECB22E` | ✅ matches the "attention orange" |
| `--red` (major gap) | `#e22a20` | `#EA4335` / `#FF3B30` / `#D7493A` | ✅ standard urgent red |
| Graphite / monochrome surfaces + button | near-black + one accent | Notion / ChatGPT precedent | ✅ proven premium pattern |

**Conclusion:** Stale's palette is already aligned with how the best Mac apps use color — a
single trustworthy blue accent, the conventional green/amber/red semantic triad, and a
restrained monochrome base (the Notion/ChatGPT lane). No correction needed; the research
*confirms* the current direction rather than overturning it.

### Optional, evidence-backed tweaks (not required)
- Our light-mode `--green #1aa35a` is slightly darker than the top cluster's vivid greens
  (`#1DB954`). Nudging it toward `#1DB954` would read a touch fresher while staying on-brand.
  (Dark mode `#2fce72` is already in the vivid band.)
- The blue is spot-on; leave it.

## Method notes & honesty

- Pixel extraction is **best-effort**: icons that are gradients on white rounded squares can
  over-report the brightest gradient stop, and white-on-color glyph icons (Discord, 1Password)
  can read as the background. That's exactly why documented brand colors take precedence in the
  table above; pixel values are used only where no canonical brand color is published.
- "Top 25" is a curated blend of 2026 best-app roundups + Apple Design recognition, not a single
  ranked chart (no public unified Mac-install ranking exists). It's representative, not absolute.
- Reproducible: the extraction scripts live in this commit's history; re-run against the live
  iTunes API to refresh.

## Sources
- [Rize — Best Mac productivity apps 2026](https://rize.io/blog/best-mac-productivity-apps-2026)
- [Setapp — Best Mac apps 2026](https://setapp.com/app-reviews/top-best-reviewed-mac-apps)
- [SlashGear — 15 best Mac apps 2026](https://www.slashgear.com/2172654/best-mac-apps-improve-apple-experience-2026/)
- [Apple — 2025 Apple Design Award winners](https://www.apple.com/newsroom/2025/06/apple-unveils-winners-and-finalists-of-the-2025-apple-design-awards/)
- [Apple — 2025 App Store Award winners](https://www.apple.com/newsroom/2025/12/apple-unveils-the-winners-of-the-2025-app-store-awards/)
- Color data: each app's icon via the public **iTunes Search API** (`artworkUrl512`).
