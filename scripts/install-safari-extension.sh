#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$PROJECT_DIR/dist/hidigFocus Safari.app"
TARGET_APP="/Applications/hidigFocus Safari.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [ ! -d "$SOURCE_APP" ]; then
    echo "Сначала выполните ./scripts/build-safari-extension.sh" >&2
    exit 2
fi

codesign --verify --deep --strict "$SOURCE_APP"
STAGING_DIR="$(mktemp -d '/Applications/.hidigFocus-safari-stage.XXXXXX')"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$SOURCE_APP" "$STAGING_DIR/hidigFocus Safari.app"
codesign --verify --deep --strict "$STAGING_DIR/hidigFocus Safari.app"
if [ -e "$TARGET_APP" ]; then
    BACKUP_DIR="$PROJECT_DIR/SafariBuild/Backups/$(date '+%Y%m%d-%H%M%S')-installed-$$"
    mkdir -p "$BACKUP_DIR"
    mv "$TARGET_APP" "$BACKUP_DIR/hidigFocus Safari.app"
    echo "Предыдущая версия: $BACKUP_DIR/hidigFocus Safari.app"
fi
mv "$STAGING_DIR/hidigFocus Safari.app" "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"
# Xcode registers its build product automatically. Leave only the installed
# container registered so Safari does not display two identical extensions.
BUILD_APP="$PROJECT_DIR/SafariBuild/SignedDerivedData/Build/Products/Release/hidigFocus Safari.app"
if [ -d "$BUILD_APP" ]; then
    pluginkit -r "$BUILD_APP/Contents/PlugIns/hidigFocus Safari Extension.appex" || true
    "$LSREGISTER" -u "$BUILD_APP" || true
fi
"$LSREGISTER" -f -R -trusted "$TARGET_APP"
pluginkit -a "$TARGET_APP/Contents/PlugIns/hidigFocus Safari Extension.appex"
if [ "${HIDIGFOCUS_SAFARI_SKIP_OPEN:-0}" != "1" ]; then
    open "$TARGET_APP"
fi

echo "$TARGET_APP"
