#!/usr/bin/env bash
# Build IconForge.app from the Swift Package executable target.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="IconForge"
BUNDLE_ID="com.fcatus.iconforge"
VERSION="1.0.0"

CONFIG="${1:-release}"
BIN=".build/${CONFIG}/${APP_NAME}"
APP_DIR="build/${APP_NAME}.app"

echo "▶ Compiling (${CONFIG})…"
swift build -c "$CONFIG"
[[ -f "$BIN" ]] || { echo "✗ Build product not found at $BIN" >&2; exit 1; }

echo "▶ Assembling ${APP_NAME}.app…"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "$BIN" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"
cp Info.plist "${APP_DIR}/Contents/Info.plist"

if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

echo "▶ Signing (ad-hoc)…"
codesign --force --sign - "${APP_DIR}"

echo "✅ Built ${APP_DIR}"
echo "   Run:     open \"${APP_DIR}\""
echo "   Install: ./install.sh"
