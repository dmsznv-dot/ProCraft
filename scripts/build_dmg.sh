#!/usr/bin/env bash
# Builds "PixelCraft Pro.app" from source and packs it into a DMG.
# Usage: scripts/build_dmg.sh [version]   (run on macOS 14+ with Xcode 16 / Swift 6)
set -euo pipefail

VERSION="${1:-1.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
APP_NAME="PixelCraft Pro"
APP="$OUT/$APP_NAME.app"
DMG="$OUT/PixelCraftPro-$VERSION-macOS-arm64.dmg"

cd "$ROOT"
echo "==> Building release binary"
swift build -c release --arch arm64 --product PixelCraftApp
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "==> Assembling $APP_NAME.app"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PixelCraftApp" "$APP/Contents/MacOS/PixelCraftApp"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M)" "$APP/Contents/Info.plist"
# Metal shaders are compiled at runtime from embedded source; no resource bundle is needed.

echo "==> Ad-hoc code signing (required to launch on Apple Silicon)"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo "==> Creating DMG"
STAGING="$OUT/dmg-staging"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "==> Done: $DMG"
