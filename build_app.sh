#!/usr/bin/env bash
# Build IconForge.app from the Swift Package executable target.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="IconForge"
# Bundle identifier and version live in Info.plist, which is copied verbatim.

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
# Apple's codesign by absolute path. conda, miniforge and some cross-compile
# toolchains put their own `codesign` shim earlier on PATH, and that one cannot
# sign an .app bundle: it aborts with NotAMachOFileException and leaves the
# bundle unsigned, which macOS then refuses to launch.
/usr/bin/codesign --force --sign - "${APP_DIR}"

echo "✅ Built ${APP_DIR}"
echo "   Run:     open \"${APP_DIR}\""
echo "   Install: ./install.sh"
