#!/bin/bash
# =====================================================================
#  notarize.sh — build, notarize, staple, and package Stale.app for
#  distribution to ANY Mac (no "unidentified developer" warning).
#
#  Prerequisites (one-time, created by you in your Apple Developer account):
#    1. A "Developer ID Application" certificate in your login keychain.
#       Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸
#       "Developer ID Application"  (or developer.apple.com ▸ Certificates).
#    2. A notarytool credential profile named "stale-notary":
#         xcrun notarytool store-credentials stale-notary \
#           --apple-id "you@example.com" \
#           --team-id 2A43Y27843 \
#           --password "xxxx-xxxx-xxxx-xxxx"   # app-specific password
#       (App-specific password: appleid.apple.com ▸ Sign-In & Security.)
#
#  Usage:  ./notarize.sh            # full pipeline -> build/Stale.dmg
#          ./notarize.sh --profile myprofile   # use a different notary profile
#
#  Output: build/Stale.app (notarized + stapled) and build/Stale.dmg
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="stale-notary"
for a in "$@"; do case "$a" in --profile) shift; PROFILE="${1:-stale-notary}";; esac; done

APP="build/Stale.app"
ZIP="build/Stale.zip"
DMG="build/Stale.dmg"
TEAM="2A43Y27843"

echo "🍂  Stale — notarized release"
echo "────────────────────────────────────────────"

# --- 0. preflight: cert + profile present? ---
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  cat <<'MSG'
  ✗ No "Developer ID Application" certificate found in your keychain.
    Create it first (one-time):
      Xcode ▸ Settings ▸ Accounts ▸ (your Apple ID) ▸ Manage Certificates
      ▸ click + ▸ "Developer ID Application"
    Then re-run ./notarize.sh
MSG
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  cat <<MSG
  ✗ notarytool profile "$PROFILE" not found. Create it once:
      xcrun notarytool store-credentials $PROFILE \\
        --apple-id "you@example.com" --team-id $TEAM \\
        --password "xxxx-xxxx-xxxx-xxxx"   # app-specific password
MSG
  exit 1
fi

# --- 1. build + sign (Developer ID, hardened runtime, timestamp) ---
echo "▸ building signed release…"
./make-icon.sh >/dev/null
./build.sh --release

# --- 2. zip for submission (ditto preserves the bundle) ---
echo "▸ zipping for notarization…"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

# --- 3. submit + wait for Apple's verdict ---
echo "▸ submitting to Apple (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

# --- 4. staple the ticket so it works offline / first launch ---
echo "▸ stapling ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# --- 5. final Gatekeeper assessment ---
echo "▸ Gatekeeper assessment:"
spctl -a -vv "$APP" 2>&1 | sed 's/^/      /'

# --- 6. package a .dmg for download ---
echo "▸ building $DMG…"
rm -f "$DMG"
hdiutil create -volname "Stale" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
echo ""
echo "✅  Done."
echo "    Notarized app: $APP"
echo "    Distributable: $DMG"
echo "    This opens on any Mac with no Gatekeeper warning."
