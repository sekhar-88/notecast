#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="v0.4.1"
BUILD_FLAGS=()

if [[ $# -gt 0 && "$1" != -* ]]; then
    VERSION="$1"
    shift
fi

while [[ $# -gt 0 ]]; do
    BUILD_FLAGS+=("$1")
    shift
done

ARCH="$(uname -m)"
BUNDLE_VERSION="${VERSION#v}"
if [[ ${#BUILD_FLAGS[@]} -gt 0 ]]; then
    APP_VERSION="$BUNDLE_VERSION" "$ROOT_DIR/scripts/build-app.sh" "${BUILD_FLAGS[@]}"
else
    APP_VERSION="$BUNDLE_VERSION" "$ROOT_DIR/scripts/build-app.sh"
fi

APP_BUNDLE="$ROOT_DIR/build/Notecast.app"
RELEASE_DIR="$ROOT_DIR/build/release"
ZIP_NAME="Notecast-${VERSION}-${ARCH}.zip"
DMG_NAME="Notecast-${VERSION}-${ARCH}.dmg"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
SUMS_PATH="$RELEASE_DIR/SHA256SUMS.txt"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "Creating $ZIP_NAME..."
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Creating $DMG_NAME..."
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notecast-dmg.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
cp -R "$APP_BUNDLE" "$STAGE_DIR/Notecast.app"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -volname "Notecast" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "Computing SHA-256 checksums..."
(
    cd "$RELEASE_DIR"
    shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > "$SUMS_PATH"
)

echo "Packaged release artifacts in $RELEASE_DIR:"
ls -lh "$RELEASE_DIR"
cat "$SUMS_PATH"
