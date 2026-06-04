# Roadmap

Planned work, in priority order. Current state: the app is functionally complete and fully
version-controlled. The web/local entities are usable today; the native app builds and runs
locally. What remains is **distribution** — letting a non-technical person download and run it.

## Next up

### 1. Distributable release — notarized `.dmg` + GitHub Release
**Why:** Today a cloner gets source only. The web version runs instantly (`./run.command`), but
the native `Stale.app` must be built from source (needs Xcode). A regular user needs a
double-clickable download. There is no released `.dmg` yet.

**The build/sign/notarize automation is already done** — `native/notarize.sh` runs the whole
pipeline in one command (see `native/docs/NATIVE.md`). It's blocked only on two one-time,
owner-only prerequisites (require the Apple ID):

1. Create a **"Developer ID Application"** certificate
   (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application).
2. Create an **app-specific password** (appleid.apple.com) and store it:
   ```sh
   xcrun notarytool store-credentials stale-notary \
     --apple-id "you@example.com" --team-id 2A43Y27843 --password "xxxx-xxxx-xxxx-xxxx"
   ```

Then:
```sh
cd native && ./notarize.sh        # → build/Stale.dmg (opens on any Mac, no warning)
```
Finally, publish a **GitHub Release** with the `.dmg` attached → a real download link.

### 2. Automated release pipeline (GitHub Actions)
Once #1 is done once manually, automate it: a workflow that, on a version tag, builds + signs +
notarizes + attaches the `.dmg` to a GitHub Release. Requires storing the Developer ID cert and
notary credentials as encrypted CI secrets. *(Deferred — manual release first.)*

### 3. Homebrew Cask (fitting, since Stale reads Homebrew)
After a notarized `.dmg`/`.zip` is hosted, publish a cask so users `brew install --cask stale`.
Needs the public download URL + SHA256.

## Ideas / backlog (not committed)
- Watch a **real** `brew upgrade` version bump end-to-end in the UI (all installed brew casks are
  currently already up to date, so only the no-op path has been observed live).
- Real Safari "Add to Dock" + offline relaunch verification on a physical machine.
- Sparkle-appcast coverage for apps Homebrew doesn't track.
- Cross-browser pass (Safari/Firefox) beyond the Chromium checks already done.
