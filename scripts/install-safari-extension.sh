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

mkdir -p "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"
"$LSREGISTER" -f -R -trusted "$TARGET_APP"
pluginkit -a "$TARGET_APP/Contents/PlugIns/hidigFocus Safari Extension.appex"
open "$TARGET_APP"

echo "$TARGET_APP"
