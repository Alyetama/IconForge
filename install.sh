#!/usr/bin/env bash
# Build IconForge and install it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="IconForge"

./build_app.sh release

pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "/Applications/${APP_NAME}.app"
cp -R "build/${APP_NAME}.app" /Applications/

echo "✅ Installed /Applications/${APP_NAME}.app"
echo "   Launch: open -a ${APP_NAME}"
