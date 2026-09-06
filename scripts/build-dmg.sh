#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$PROJECT_DIR/dist/hidigFocus.app"
DMG="$PROJECT_DIR/dist/hidigFocus-mac.dmg"
STAGING="$(mktemp -d /private/tmp/hidigfocus-dmg.XXXXXX)"

cleanup() {
    rm -rf "$STAGING"
}
trap cleanup EXIT

if [ ! -d "$APP" ]; then
    echo "Сначала выполните ./scripts/build-app.sh" >&2
    exit 2
fi

ditto "$APP" "$STAGING/hidigFocus.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create \
    -volname "hidigFocus" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"

echo "$DMG"
