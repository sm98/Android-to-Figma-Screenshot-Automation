#!/bin/bash
# Builds the Swift package and packages it as a minimal ScreenshotSync.app bundle, then signs
# it with a stable local self-signed identity ("ScreenshotSync Local Dev", set up once via
# security import — see mac-app/README dev notes). A real .app + Info.plist (vs. a bare binary)
# is required for TCC to grant Accessibility at all, and signing with a STABLE identity (not
# ad-hoc `-`, which hashes the binary and changes every build) is required for TCC to remember
# Keychain/Accessibility grants across rebuilds instead of re-prompting every time.
set -euo pipefail
cd "$(dirname "$0")"

swift build

APP_DIR="ScreenshotSync.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp .build/debug/ScreenshotSync "$MACOS_DIR/ScreenshotSync"
cp Info.plist "$CONTENTS_DIR/Info.plist"

xattr -cr "$APP_DIR"
codesign --force --sign "ScreenshotSync Local Dev" "$APP_DIR"

echo "Built $APP_DIR"
