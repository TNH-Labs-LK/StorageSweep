#!/bin/bash
# Builds "Storage Sweep.app" into ./dist and zips it for sharing.
# Needs Xcode (or Xcode Command Line Tools) on macOS 13 or later.
#
# Optional, for public distribution (see README):
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Storage Sweep"
EXEC="StorageSweep"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building (release)…"
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
    echo "    Universal build (Apple silicon + Intel)"
else
    echo "    Universal build not available, building for this Mac only"
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXEC" "$APP/Contents/MacOS/$EXEC"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -d Resources/AppIcon.iconset ]; then
    iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> Signing"
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"   # ad-hoc signature: fine for you and friends
fi

echo "==> Zipping"
rm -f "$DIST/StorageSweep.zip"
ditto -c -k --keepParent "$APP" "$DIST/StorageSweep.zip"

echo
echo "Done!"
echo "  App: $APP"
echo "  Zip to share: $DIST/StorageSweep.zip"
echo "Open it with:  open \"$APP\""
