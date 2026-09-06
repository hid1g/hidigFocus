#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
CONFIGURATION="${HIDIGFOCUS_BUILD_CONFIGURATION:-debug}"
BUILD_DIR="$PROJECT_DIR/.build-app"

swift build --scratch-path "$BUILD_DIR" -j 2 -c "$CONFIGURATION" --product hidigFocus
BIN_DIR="$(swift build --scratch-path "$BUILD_DIR" -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/hidigFocus.app"
EXTENSION_DIR="$PROJECT_DIR/dist/hidigFocus Browser Extension"
SAFARI_SOURCE_DIR="$PROJECT_DIR/dist/hidigFocus Safari Extension Source"
APP_ARCHIVE="$PROJECT_DIR/dist/hidigFocus-mac.zip"
EXTENSION_ARCHIVE="$PROJECT_DIR/dist/hidigFocus-browser-extension.zip"
SAFARI_SOURCE_ARCHIVE="$PROJECT_DIR/dist/hidigFocus-safari-extension-source.zip"
LEGACY_SAFARI_APP="$PROJECT_DIR/dist/hidigFocus Safari.app"
LEGACY_SAFARI_ARCHIVE="$PROJECT_DIR/dist/hidigFocus-safari-extension.zip"

rm -rf "$APP_DIR"
rm -rf "$EXTENSION_DIR"
rm -rf "$SAFARI_SOURCE_DIR"
rm -rf "$LEGACY_SAFARI_APP"
rm -f "$LEGACY_SAFARI_ARCHIVE"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/hidigFocus" "$APP_DIR/Contents/MacOS/hidigFocus"
cp "$PROJECT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"

if [ -d "$BIN_DIR/hidigFocus_hidigFocus.bundle" ]; then
    cp -R "$BIN_DIR/hidigFocus_hidigFocus.bundle" "$APP_DIR/Contents/Resources/"
    rm -rf "$APP_DIR/Contents/Resources/hidigFocus_hidigFocus.bundle/SafariExtension"
fi

if [ -f "$PROJECT_DIR/Resources/hidigFocus.icns" ]; then
    cp "$PROJECT_DIR/Resources/hidigFocus.icns" "$APP_DIR/Contents/Resources/hidigFocus.icns"
fi

codesign --force --deep --sign - "$APP_DIR"
cp -R "$PROJECT_DIR/BrowserExtension" "$EXTENSION_DIR"
rm -f "$APP_ARCHIVE" "$EXTENSION_ARCHIVE" "$SAFARI_SOURCE_ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$APP_ARCHIVE"
ditto -c -k --keepParent "$EXTENSION_DIR" "$EXTENSION_ARCHIVE"
echo "$APP_DIR"
echo "$EXTENSION_DIR"
