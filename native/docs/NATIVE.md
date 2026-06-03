# Native App: Architecture, Build & Notarization

> Everything about the **App entity** — how it's built, what's verified, and the exact
> steps to ship it to other Macs. Last updated: 2026-05-30.

## 1. Architecture

A thin Swift shell hosting the shared web UI. Three reasons it's structured this way:

1. **Reuse** — 100% of the tested `../stale` UI/engine is reused; the native side only
   supplies data the browser can't reach.
2. **Custom scheme, not `file://`** — assets are served over `stale://app/...` by a
   `WKURLSchemeHandler`, giving the page a stable secure origin so IndexedDB / fetch /
   service-worker behave like a normal site.
3. **One narrow bridge** — a single `staleScan` message handler. JS asks; Swift runs
   `system_profiler` off the main thread and calls `window.__staleReceiveScan(json)`.

```
Sources/main.swift
├── WebAssetSchemeHandler   serves Resources/web over stale://
├── Scanner.scan()          /usr/sbin/system_profiler SPApplicationsDataType -json
└── AppController
    ├── NSStatusItem        menu bar 🍂 (Open / Scan Now / Launch at Login / Quit)
    ├── NSWindow + WKWebView the UI
    ├── staleScan handler    JS → Swift → JSON back to JS (base64 to avoid escaping)
    ├── UNUserNotification   "N apps have gone stale"
    └── SMAppService         launch at login (macOS 13+)
```

## 2. What's verified ✅

- **Compiles clean** — `swiftc -O` against AppKit/WebKit/UserNotifications/ServiceManagement,
  exit 0, no warnings.
- **Signs & verifies** — `codesign --verify` → *"valid on disk / satisfies its Designated
  Requirement"* with `Apple Development: Rajwinder Parmar`, Team `2A43Y27843`.
- **Bundle complete** — 26 files; `Resources/web/index.html` + `app.js` present; native
  bridge present in bundled JS (`staleScan` ×4); `scanBtn` present in bundled HTML.
- **Launches & stays alive** — `open Stale.app` → process running, **no crash report**.
- **JS app-entity path** (verified in-browser via `?build=app`):
  `build="app"`, `isNative=true`, separate `stale-app` IndexedDB, green **App** badge
  (`rgb(48,209,88)`), scan button visible, Terminal steps hidden.

## 3. What's NOT yet verified (honest gaps)

- **Live Swift↔JS scan round-trip in the running .app window** — the build + bridge are in
  place and the JS half is proven, but a visual confirmation of the auto-scan rendering
  inside the actual app window wasn't captured this session (the screenshot channel was
  flaky). To confirm manually: launch the app; it should auto-show your real freshness
  score within ~1s of the DB loading. Menu bar → **Scan Now** re-runs it.
- **Notifications / Launch-at-Login** — wired and compiled, not yet click-tested.

## 4. Distribution: notarizing for other Macs

Running locally only needs the Apple Development signature (done). To let *anyone* open it
without Gatekeeper blocking it, you must notarize. You have the Apple Developer Program, so:

### One-time setup
1. **Create a "Developer ID Application" certificate**
   (Xcode → Settings → Accounts → Manage Certificates → ⊕ → *Developer ID Application*),
   or at developer.apple.com → Certificates. This is different from the *Apple Development*
   cert already in your keychain.
2. **Create an app-specific password** at appleid.apple.com (Sign-In & Security →
   App-Specific Passwords) for `notarytool`.
3. **Store credentials** once:
   ```sh
   xcrun notarytool store-credentials stale-notary \
     --apple-id "you@example.com" \
     --team-id 2A43Y27843 \
     --password "xxxx-xxxx-xxxx-xxxx"   # the app-specific password
   ```

### Each release
```sh
# 1. Build signed with the Developer ID cert + hardened runtime
./build.sh --release

# 2. Zip and submit for notarization (waits for the result)
ditto -c -k --keepParent build/Stale.app build/Stale.zip
xcrun notarytool submit build/Stale.zip --keychain-profile stale-notary --wait

# 3. Staple the ticket so it works offline / first-launch
xcrun stapler staple build/Stale.app
xcrun stapler validate build/Stale.app

# 4. (optional) package a .dmg for download
hdiutil create -volname Stale -srcfolder build/Stale.app -ov -format UDZO build/Stale.dmg
```

After stapling, `Stale.app` (or the `.dmg`) opens on any Mac with no warnings.

### Or ship via Homebrew (fitting, since Stale reads Homebrew)
Once a notarized `.dmg`/`.zip` is hosted (e.g. a GitHub Release), publish a Cask so users
`brew install --cask stale`. (Requires a public download URL + SHA256; straightforward once
a release exists.)

## 5. Requirements recap

| Need | Status |
|---|---|
| Xcode / Swift toolchain | ✅ Xcode 26.4.1, Swift 6.3.1 |
| Apple Developer Program | ✅ (yours) |
| Apple Development cert (local run) | ✅ in keychain |
| Developer ID Application cert (distribution) | ⏳ create when ready to ship |
| App-specific password for notarytool | ⏳ create when ready to ship |
