#!/bin/bash
# Builds a release ScreenshotSync.app (signed with the stable local dev identity) and packages
# it into a distributable ScreenshotSync.dmg with a drag-to-Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP_DIR="ScreenshotSync.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp .build/release/ScreenshotSync "$MACOS_DIR/ScreenshotSync"
cp Info.plist "$CONTENTS_DIR/Info.plist"

xattr -cr "$APP_DIR"
codesign --force --sign "ScreenshotSync Local Dev" "$APP_DIR"

echo "Built $APP_DIR (release)"

DMG_STAGING=$(mktemp -d)
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f ScreenshotSync.dmg
hdiutil create -volname "Screenshot Sync" -srcfolder "$DMG_STAGING" -ov -format UDZO ScreenshotSync.dmg
rm -rf "$DMG_STAGING"

echo "Built ScreenshotSync.dmg"
