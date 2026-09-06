#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

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
mkdir -p "$OUTPUT_DIR"

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
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    build

mkdir -p "$PROJECT_DIR/dist"
rm -rf "$DIST_PRODUCT"
rm -f "$PROJECT_DIR/dist/hidigFocus-safari-extension.zip"
ditto "$PRODUCT" "$DIST_PRODUCT"

ditto -c -k --sequesterRsrc --keepParent "$DIST_PRODUCT" "$PROJECT_DIR/dist/hidigFocus-safari-extension.zip"

echo "$DIST_PRODUCT"
echo "$PROJECT_DIR/dist/hidigFocus-safari-extension.zip"
