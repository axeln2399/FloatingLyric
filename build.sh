#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FloatingLyric"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"

# `swift test` needs XCTest, which ships with Xcode but not the Command Line
# Tools. Point at Xcode when it is installed but not selected.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Optional Apple Developer signing. Without these the app is ad-hoc signed and
# Gatekeeper blocks the first launch (see README).
#   SIGN_IDENTITY  e.g. "Developer ID Application: Your Name (TEAM123456)"
#   NOTARY_PROFILE e.g. "floatinglyric" — a notarytool keychain profile
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

echo "==> Building universal release binary"
swift build -c release --arch arm64 --arch x86_64

BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
test -f "$BIN" || { echo "build produced no binary at $BIN"; exit 1; }

echo "==> Assembling $APP"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -n "$SIGN_IDENTITY" ]; then
  echo "==> Signing with Developer ID: $SIGN_IDENTITY"
  # Hardened runtime and a secure timestamp are both required for notarization.
  codesign --force --deep --options runtime --timestamp \
           --sign "$SIGN_IDENTITY" "$APP"
else
  echo "==> Ad-hoc signing (no SIGN_IDENTITY set)"
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --verbose "$APP"

echo "==> Building $DMG"
STAGE="$DIST/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "$SIGN_IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
  echo "==> Signing the DMG"
  codesign --force --sign "$SIGN_IDENTITY" "$DMG"

  echo "==> Notarizing (this usually takes 1-5 minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "==> Stapling the notarization ticket"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"

  echo
  echo "Done: $DMG (signed + notarized — opens with no warnings on any Mac)"
elif [ -n "$SIGN_IDENTITY" ]; then
  echo
  echo "Done: $DMG (signed, NOT notarized)"
  echo "Gatekeeper still warns on other Macs. Set NOTARY_PROFILE to notarize."
else
  echo
  echo "Done: $DMG (unsigned)"
  echo "First launch is blocked by Gatekeeper. Fix it with either:"
  echo "  right-click $APP_NAME -> Open -> Open"
  echo "  xattr -cr /path/to/$APP_NAME.app"
fi

echo
echo "Run it without installing:  open $APP"
