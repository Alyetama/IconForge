#!/usr/bin/env bash
# Build IconForge.app and wrap it in a compressed disk image for download.
#
# The image is ad-hoc signed, not Developer ID signed and not notarized, so
# Gatekeeper will refuse it on first launch. docs/index.html explains the
# right-click-Open route to anyone who downloads it.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="IconForge"
VOLUME_NAME="IconForge"
DMG_PATH="docs/IconForge.dmg"
APP_DIR="build/${APP_NAME}.app"

./build_app.sh release

echo "▶ Staging…"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_DIR" "$STAGE/${APP_NAME}.app"
# The usual drag-to-install target, so the window explains itself.
ln -s /Applications "$STAGE/Applications"

echo "▶ Building ${DMG_PATH}…"
mkdir -p "$(dirname "$DMG_PATH")"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO -quiet \
    "$DMG_PATH"

SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"
echo "✅ Built ${DMG_PATH} (${SIZE})"
echo "   Unsigned: first launch needs right-click ▸ Open, or Settings ▸ Privacy & Security."
