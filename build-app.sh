#!/bin/zsh
# Build Realign.app — a self-contained menu bar app bundle.
#
#   ./build-app.sh            build the bundle here
#   ./build-app.sh install    copy it to /Applications and relaunch
#
set -eu
cd "$(dirname "$0")"

APP="Realign.app"
CONTENTS="$APP/Contents"
INSTALL_DIR="/Applications"
SIGNING_NAME="realign-dev"

if [[ "${1:-}" != "" && "${1:-}" != "install" ]]; then
  echo "Usage: ./build-app.sh [install]" >&2
  exit 2
fi

echo "→ Building release binary…"
SWIFT_BUILD_ARGUMENTS=(-c release)
if [[ "${SPLIT_SCREEN_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  SWIFT_BUILD_ARGUMENTS+=(--disable-sandbox)
fi
swift build "${SWIFT_BUILD_ARGUMENTS[@]}"

echo "→ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"
cp ".build/release/Realign" "$CONTENTS/MacOS/Realign"
cp "Info.plist" "$CONTENTS/Info.plist"
mkdir -p "$CONTENTS/Resources"
cp assets/AppIcon.icns assets/MenuBarIcon.png assets/MenuBarIcon@2x.png "$CONTENTS/Resources/"

if security find-identity -v -p codesigning 2>/dev/null \
    | grep -Fq "\"$SIGNING_NAME\""; then
  echo "→ Signing with stable identity: $SIGNING_NAME"
  codesign --force --deep --options runtime \
    --entitlements Realign.entitlements \
    --sign "$SIGNING_NAME" "$APP"
else
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "WARNING: '$SIGNING_NAME' is absent; using an ad-hoc signature."
  echo "macOS Tahoe may require Accessibility approval again after EVERY build."
  echo "Run ./make-dev-cert.sh once, then rebuild for a stable TCC identity."
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo ""
  codesign --force --deep --entitlements Realign.entitlements \
    --sign - "$APP"
fi

codesign --verify --deep --strict "$APP"
echo "✓ Built $(pwd)/$APP"

if [[ "${1:-}" == "install" ]]; then
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
fi
echo "  Restore:  ⌃⌥⌘R"
echo "  Save:     ⌃⌥⌘S"
