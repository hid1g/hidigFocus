#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING_IDENTITY="${HIDIGFOCUS_SAFARI_SIGNING_IDENTITY:--}"
SIGNING_TEAM="${HIDIGFOCUS_SAFARI_DEVELOPMENT_TEAM:-}"

if [ -d /Applications/Xcode.app/Contents/Developer ] &&
   ! xcrun --find safari-web-extension-packager >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

PACKAGER_OUTPUT="$(xcrun --find safari-web-extension-packager 2>&1 || true)"
PACKAGER="$(printf '%s\n' "$PACKAGER_OUTPUT" | tail -n 1)"

if [[ "$PACKAGER_OUTPUT" == *"not agreed to the Xcode license"* ]]; then
    echo "Xcode установлен, но лицензия ещё не принята. Откройте Xcode и подтвердите лицензию, затем повторите сборку." >&2
    exit 2
fi

if [ -z "$PACKAGER" ] || [ ! -x "$PACKAGER" ]; then
    echo "Не найден safari-web-extension-packager. Установите полный Xcode из App Store." >&2
    exit 2
fi

OUTPUT_DIR="$PROJECT_DIR/SafariBuild"
GENERATED_DIR="$OUTPUT_DIR/hidigFocus Safari"
PROJECT_PATH="$GENERATED_DIR/hidigFocus Safari.xcodeproj"
DERIVED_DATA="$OUTPUT_DIR/SignedDerivedData"
PRODUCT="$DERIVED_DATA/Build/Products/Release/hidigFocus Safari.app"
DIST_PRODUCT="$PROJECT_DIR/dist/hidigFocus Safari.app"
DIST_ARCHIVE="$PROJECT_DIR/dist/hidigFocus-safari-extension.zip"
BACKUP_DIR="$OUTPUT_DIR/Backups/$(date '+%Y%m%d-%H%M%S')-$$"
mkdir -p "$OUTPUT_DIR"

# Keep the previous generated project and app for rollback. Do not touch the
# separately running hidigFocus.app or any of its settings/data.
if [ -d "$GENERATED_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    ditto "$GENERATED_DIR" "$BACKUP_DIR/generated-project"
fi
if [ -d "$PRODUCT" ]; then
    mkdir -p "$BACKUP_DIR"
    ditto "$PRODUCT" "$BACKUP_DIR/previous-build.app"
fi

"$PACKAGER" "$PROJECT_DIR/SafariExtension" \
    --project-location "$OUTPUT_DIR" \
    --app-name "hidigFocus Safari" \
    --bundle-identifier "com.hidig.focus.safari" \
    --swift \
    --macos-only \
    --copy-resources \
    --no-open \
    --no-prompt \
    --force

# Xcode 26.6 can derive the containing app identifier from the app name even
# when an explicit identifier is supplied. Keep it as the prefix of the appex.
perl -pi -e 's/com\.hidig\.focus\.hidigFocus-Safari/com.hidig.focus.safari/g' \
    "$PROJECT_PATH/project.pbxproj"

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "hidigFocus Safari" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$SIGNING_TEAM" \
    build

codesign --verify --deep --strict "$PRODUCT"
mkdir -p "$PROJECT_DIR/dist"
STAGING_DIR="$(mktemp -d "$PROJECT_DIR/dist/.safari-stage.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$PRODUCT" "$STAGING_DIR/hidigFocus Safari.app"
codesign --verify --deep --strict "$STAGING_DIR/hidigFocus Safari.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGING_DIR/hidigFocus Safari.app" "$STAGING_DIR/hidigFocus-safari-extension.zip"

if [ -d "$DIST_PRODUCT" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$DIST_PRODUCT" "$BACKUP_DIR/previous-distribution.app"
fi
if [ -f "$DIST_ARCHIVE" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$DIST_ARCHIVE" "$BACKUP_DIR/previous-distribution.zip"
fi
mv "$STAGING_DIR/hidigFocus Safari.app" "$DIST_PRODUCT"
mv "$STAGING_DIR/hidigFocus-safari-extension.zip" "$DIST_ARCHIVE"

if [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "Сборка ad hoc: Safari потребует разрешить неподписанные расширения заново после выхода из Safari." >&2
fi

echo "$DIST_PRODUCT"
echo "$DIST_ARCHIVE"
