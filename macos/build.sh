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

# Failing a Developer ID, fall back to the local certificate from
# make-signing-cert.sh if it is installed. It buys one thing: a stable code
# identity, so the Keychain stops asking about your Spotify token after every
# rebuild. Gatekeeper is unmoved by it.
LOCAL_IDENTITY="FloatingLyric Local Signing"
LOCAL_SIGNING=""
if [ -z "$SIGN_IDENTITY" ] &&
   security find-identity -v -p codesigning 2>/dev/null | grep -qF "$LOCAL_IDENTITY"; then
  SIGN_IDENTITY="$LOCAL_IDENTITY"
  LOCAL_SIGNING="yes"
fi

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

if [ -n "$LOCAL_SIGNING" ]; then
  echo "==> Signing with the local certificate: $SIGN_IDENTITY"
  # No hardened runtime or timestamp here: both exist to serve notarization,
  # which a self-signed certificate cannot reach anyway.
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
elif [ -n "$SIGN_IDENTITY" ]; then
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

if [ -n "$LOCAL_SIGNING" ]; then
  echo
  echo "Done: $DMG (signed with a local certificate)"
  echo "Every future build now has the same identity, so the Keychain will stop"
  echo "asking about your Spotify token. Gatekeeper still warns on other Macs."
elif [ -n "$SIGN_IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
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
  echo "Tip: ./make-signing-cert.sh stops the Keychain asking about your"
  echo "     Spotify token after every rebuild."
  echo "First launch is blocked by Gatekeeper. Fix it with either:"
  echo "  right-click $APP_NAME -> Open -> Open"
  echo "  xattr -cr /path/to/$APP_NAME.app"
fi

echo
echo "Run it without installing:  open $APP"
