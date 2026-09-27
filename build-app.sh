#!/bin/zsh
# Build Realign.app — a self-contained menu bar app bundle.
#
#   ./build-app.sh            build the bundle here, signed with realign-dev
#   ./build-app.sh install    copy it to /Applications and relaunch
#   ./build-app.sh release    sign with Developer ID, notarize, staple, and
#                             zip to dist/Realign-<version>.zip
#
# Release mode needs a "Developer ID Application" identity in the keychain
# and notarytool credentials stored once with:
#   xcrun notarytool store-credentials realign-notary \
#     --apple-id <apple-id> --team-id <team-id>
# Override the identity with REALIGN_DEVELOPER_ID and the profile name with
# REALIGN_NOTARY_PROFILE.
#
set -eu
cd "$(dirname "$0")"

APP="Realign.app"
CONTENTS="$APP/Contents"
INSTALL_DIR="/Applications"
DEV_SIGNING_NAME="realign-dev"
NOTARY_PROFILE="${REALIGN_NOTARY_PROFILE:-realign-notary}"

MODE="${1:-}"
case "$MODE" in
  ""|install|release) ;;
  *)
    echo "Usage: ./build-app.sh [install|release]" >&2
    exit 2
    ;;
esac

has_identity() {
  security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$1\""
}

if [[ "$MODE" == "release" ]]; then
  if [[ -n "${REALIGN_DEVELOPER_ID:-}" ]]; then
    RELEASE_IDENTITY="$REALIGN_DEVELOPER_ID"
  else
    RELEASE_IDENTITY="$(
      security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1
    )"
  fi
  if [[ -z "$RELEASE_IDENTITY" ]] || ! has_identity "$RELEASE_IDENTITY"; then
    echo "No 'Developer ID Application' identity in the keychain." >&2
    echo "Create one in Xcode → Settings → Apple Accounts → Manage Certificates," >&2
    echo "or set REALIGN_DEVELOPER_ID to the identity's full name." >&2
    exit 1
  fi
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
  DIST_DIR="dist"
  ZIP="$DIST_DIR/Realign-$VERSION.zip"
fi

echo "→ Building release binary…"
SWIFT_BUILD_ARGUMENTS=(-c release)
BINARY=".build/release/Realign"
if [[ "$MODE" == "release" ]]; then
  # Universal binary so Intel Macs on macOS 14+ can run the download.
  SWIFT_BUILD_ARGUMENTS+=(--arch arm64 --arch x86_64)
  BINARY=".build/apple/Products/Release/Realign"
fi
if [[ "${REALIGN_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  SWIFT_BUILD_ARGUMENTS+=(--disable-sandbox)
fi
swift build "${SWIFT_BUILD_ARGUMENTS[@]}"

echo "→ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"
cp "$BINARY" "$CONTENTS/MacOS/Realign"
cp "Info.plist" "$CONTENTS/Info.plist"
mkdir -p "$CONTENTS/Resources"
cp assets/AppIcon.icns assets/MenuBarIcon.png assets/MenuBarIcon@2x.png "$CONTENTS/Resources/"

# The bundle holds one Mach-O and no nested code, so no --deep.
if [[ "$MODE" == "release" ]]; then
  echo "→ Signing with Developer ID: $RELEASE_IDENTITY"
  codesign --force --timestamp --options runtime \
    --entitlements Realign.entitlements \
    --sign "$RELEASE_IDENTITY" "$APP"
elif has_identity "$DEV_SIGNING_NAME"; then
  echo "→ Signing with stable identity: $DEV_SIGNING_NAME"
  codesign --force --options runtime \
    --entitlements Realign.entitlements \
    --sign "$DEV_SIGNING_NAME" "$APP"
else
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "WARNING: '$DEV_SIGNING_NAME' is absent; using an ad-hoc signature."
  echo "macOS Tahoe may require Accessibility approval again after EVERY build."
  echo "Run ./make-dev-cert.sh once, then rebuild for a stable TCC identity."
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo ""
  codesign --force --entitlements Realign.entitlements \
    --sign - "$APP"
fi

codesign --verify --deep --strict "$APP"
echo "✓ Built $(pwd)/$APP"

if [[ "$MODE" == "release" ]]; then
  mkdir -p "$DIST_DIR"
  rm -f "$ZIP"

  echo "→ Notarizing (profile: $NOTARY_PROFILE)…"
  ditto -c -k --keepParent "$APP" "$ZIP"
  if ! xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
    echo "" >&2
    echo "Notarization failed. If the profile is missing, store it with:" >&2
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE \\" >&2
    echo "    --apple-id <apple-id> --team-id <team-id>" >&2
    echo "For a rejected submission, see the log:" >&2
    echo "  xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE" >&2
    exit 1
  fi

  echo "→ Stapling the ticket and re-zipping…"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"

  echo "→ Gatekeeper check…"
  spctl --assess --type exec --verbose=2 "$APP"

  echo "✓ Release artifact: $(pwd)/$ZIP"
  echo "  Version:  $VERSION"
  echo "  Archs:    $(lipo -archs "$CONTENTS/MacOS/Realign")"
  echo "  SHA-256:  $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
elif [[ "$MODE" == "install" ]]; then
  echo "→ Installing to $INSTALL_DIR and relaunching…"
  pkill -x Realign 2>/dev/null || true
  sleep 0.4
  rm -rf "$INSTALL_DIR/$APP"
  cp -R "$APP" "$INSTALL_DIR/$APP"
  open "$INSTALL_DIR/$APP"
  echo "✓ Installed $INSTALL_DIR/$APP and relaunched"
else
  echo "  Run it:   open $APP"
  echo "  Install:  ./build-app.sh install"
  echo "  Release:  ./build-app.sh release"
fi
echo "  Restore:  ⌃⌥⌘R"
echo "  Save:     ⌃⌥⌘S"
