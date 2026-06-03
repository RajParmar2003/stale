# Stale.app — native macOS shell

The **App entity** of Stale: a real, double-clickable macOS app that wraps the same
web UI from [`../stale`](../stale) and adds the things a browser physically cannot do.

> Local / Web / **App** are three entities sharing one engine. See
> [`../stale/docs/ENTITIES.md`](../stale/docs/ENTITIES.md).

## What the native layer adds

| | Web / Local (browser) | **Native App** |
|---|---|---|
| Get your app list | copy command → run in Terminal → paste | **auto-scans on launch — zero steps** |
| Lives in | a browser tab | **menu bar 🍂 + Dock** |
| Alerts | none | **notification when apps go stale** |
| Start with Mac | n/a | **Launch at Login** toggle |
| Identity badge | Local / Web | green **App** |

The UI, matching engine, scoring, and grouping are **identical** — it's the exact
`../stale` web app, bundled into the `.app` and served to a `WKWebView`. Only the data
source differs: Swift runs `system_profiler` and hands the JSON to the page.

## How it works

```
WKWebView (the ../stale web UI, served over the stale:// scheme)
        │  window.webkit.messageHandlers.staleScan.postMessage("scan")
        ▼
Swift: Scanner.scan()  →  /usr/sbin/system_profiler SPApplicationsDataType -json
        │  webView.evaluateJavaScript("window.__staleReceiveScan(<json>)")
        ▼
JS detects IS_NATIVE → BUILD="app" → renders the same results, freshness score, groups
```

The page auto-detects it's inside the app (`window.webkit.messageHandlers.staleScan`
exists) and switches to the **App** entity: hides the Terminal steps, shows a single
**“Scan my Mac”** button, and kicks off a scan automatically once the Homebrew DB loads.

## Build & run

```sh
cd stale-native
./make-icon.sh      # once: generate AppIcon.icns from the shared 512px icon
./build.sh --run    # compile, bundle the web UI, sign (Apple Development), launch
```

Output: `build/Stale.app`. It's signed with your **Apple Development** identity, which is
enough to run locally. For distribution to other Macs you must notarize — see
[`docs/NATIVE.md`](docs/NATIVE.md).

## Files

| Path | Purpose |
|---|---|
| `Sources/main.swift` | The whole native app: menu bar, window, `WKWebView`, scheme handler, scanner, notifications, launch-at-login |
| `Info.plist` | Bundle metadata (id `com.rajparmar.stale`, v1.2.0, min macOS 13) |
| `Stale.entitlements` | **Not sandboxed** (must read `/Applications` + run `system_profiler`) |
| `build.sh` | Compile + assemble bundle + copy `../stale` web UI + sign |
| `make-icon.sh` | `icon-512.png` → `AppIcon.icns` via `iconutil` |

## Why not the Mac App Store?

MAS requires the **App Sandbox**, which blocks running `system_profiler` and reading
`/Applications` — the very things that make the native version worth having. That's why
MacUpdater, CleanMyMac, etc. all ship *outside* MAS. Stale distributes by **direct
download (.dmg)** or **Homebrew Cask**. Details in [`docs/NATIVE.md`](docs/NATIVE.md).
