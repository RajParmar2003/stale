# Design System

> The visual language of Stale. Goal: sharp, editorial, precise — reads perfectly at
> first glance and the thousandth. No fluff.

## Type

**Geist** (SIL OFL, bundled in `assets/fonts/` for offline parity) — a sharp neo-grotesque,
deliberately *not* rounded/friendly. **Geist Mono** for commands and version numbers.

- Headings: weight 600, tight tracking (`-0.03em`–`-0.04em`), short.
- Body: 15px, `-0.01em`, `font-feature-settings: "cv01","ss03"` (open digits, sharper a/g).
- Micro-labels (summary counts, gauge cap): UPPERCASE, `0.06em`–`0.16em` tracking, 9.5–10.5px.

## Color

Near-monochrome graphite surfaces; **one cool accent** (blue) used sparingly. Semantic color
is reserved for *state*, not decoration:

| Token | Meaning |
|---|---|
| `--amber` | stale / worth updating |
| `--green` | fresh / up to date |
| `--red` | major version gap |
| `--blue` | links, focus rings, App Store |
| graphite `--text` | primary buttons (monochrome, not blue) |

Light = clean paper + graphite ink. Dark = near-black graphite (`#0d0d0f`) with crisp hairlines.
The soft radial-gradient background was removed for a flat, sharp surface.

## Shape & space

- Tight corners: `--radius-sm 6px` (buttons, pills), `--radius 9px` (cards, inputs),
  `--radius-lg 12px` (window).
- Hairline borders (`--line` / `--line2`) instead of heavy shadows.
- The freshness gauge remains the one expressive flourish.

## Accessibility (audited)

WCAG AA verified on the live UI (contrast ratios against their actual backgrounds):

| Element | Ratio | AA (4.5 / 3.0) |
|---|---|---|
| Result headline | 16.44 | ✅ |
| App name | 15.46 | ✅ |
| Muted text / summary labels | 6.55 | ✅ |

Focus-visible rings on all controls; `prefers-reduced-motion` honoured; semantic HTML + ARIA
retained from prior versions.

## Audit-of-the-audit (second pass)

- Primary action is monochrome graphite, not blue — keeps blue meaningful (links/state) and
  reads sharper. Verified it still has strong contrast in both themes.
- Removed decorative gradient + softened the only “friendly” cues (rounded font, big radii) to
  match the “sharp at every glance” brief.
- Copy trimmed: hero lede 2 lines → 1; privacy line shortened; disclaimer ~60 words → ~25.
