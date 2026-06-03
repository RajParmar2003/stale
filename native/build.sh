#!/bin/bash
# =====================================================================
#  Stale.app — build script
#  Compiles the Swift sources, assembles the .app bundle, copies the web
#  UI from ../stale into Resources/web, generates the icon, and signs it.
#
#  Usage:
#    ./build.sh            # build + sign with your Apple Development identity (local run)
#    ./build.sh --run      # build, sign, then launch the app
#    ./build.sh --release  # build + sign with "Developer ID Application" (for notarization)
#
#  Output: ./build/Stale.app
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Stale"
BUNDLE_ID="com.rajparmar.stale"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
WEB_SRC=".."

RUN=false
RELEASE=false
for arg in "$@"; do
  case "$arg" in
    --run) RUN=true ;;
    --release) RELEASE=true ;;
  esac
done

echo "🍂  Building $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# ---- 1. Compile Swift ----
echo "  • compiling Swift…"
swiftc -O \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  Sources/main.swift \
  -framework AppKit -framework WebKit -framework UserNotifications -framework ServiceManagement \
  -target arm64-apple-macos13.0

# ---- 2. Bundle metadata ----
cp Info.plist "$APP/Contents/Info.plist"

# ---- 3. Copy the web UI (the shared engine) ----
echo "  • bundling web UI from $WEB_SRC…"
mkdir -p "$APP/Contents/Resources/web"
# Copy app assets but NOT git/docs/test cruft.
rsync -a --delete \
  --exclude ".git" --exclude "docs" --exclude "*.md" --exclude "run.command" \
  --exclude ".gitignore" --exclude "package.json" --exclude "LICENSE" \
  "$WEB_SRC"/ "$APP/Contents/Resources/web"/

# ---- 4. Icon ----
if [ -f "AppIcon.icns" ]; then
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "  • (no AppIcon.icns yet — run ./make-icon.sh first for a custom icon)"
fi

# ---- 5. Sign ----
if $RELEASE; then
  # `|| true` so a no-match grep doesn't trip `set -e`/pipefail before our friendly check.
  IDENTITY=$( (security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}') || true )
  if [ -z "$IDENTITY" ]; then
    echo "  ✗ No 'Developer ID Application' certificate found. Create one in your Apple Developer account."
    echo "    (For local runs, omit --release to sign with your Apple Development identity.)"
    exit 1
  fi
  echo "  • signing (release, hardened runtime + secure timestamp): $IDENTITY"
  # --timestamp is REQUIRED for notarization. --deep is deprecated by Apple; we sign the
  # single Mach-O bundle explicitly (no nested binaries to sign here).
  codesign --force --options runtime --timestamp \
    --entitlements Stale.entitlements \
    --sign "$IDENTITY" "$APP"
  echo "  • verifying signature…"
  codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/      /'
else
  IDENTITY=$( (security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk -F'"' '{print $2}') || true )
  if [ -z "$IDENTITY" ]; then
    echo "  • no signing identity found — building UNSIGNED (will still run locally)"
  else
    echo "  • signing (local): $IDENTITY"
    codesign --force --deep \
      --entitlements Stale.entitlements \
      --sign "$IDENTITY" "$APP" || echo "  • (sign failed; app still runs locally unsigned)"
  fi
fi

echo "✅  Built $APP"
codesign -dv "$APP" 2>&1 | sed 's/^/     /' || true

if $RUN; then
  echo "🚀  Launching…"
  open "$APP"
fi
