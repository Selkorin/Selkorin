#!/bin/bash
# Builds Alakeya.app and installs it to /Applications.
# Usage: ./scripts/install_app.sh [debug|release]
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP_BUILD="$ROOT/.build/Alakeya.app"
APP_DEST="/Applications/Alakeya.app"

# Build and package first
bash "$ROOT/scripts/package_app.sh" "$CONFIG"

echo "▶ Installing to $APP_DEST…"

# Quit running instance gracefully
if pgrep -x Alakeya &>/dev/null; then
    echo "  Quitting running Alakeya…"
    osascript -e 'tell application "Alakeya" to quit' 2>/dev/null || \
        pkill -x Alakeya 2>/dev/null || true
    sleep 1
fi

# Replace existing app
if [ -d "$APP_DEST" ]; then
    rm -rf "$APP_DEST"
fi
cp -R "$APP_BUILD" "$APP_DEST"
chmod -R u+x "$APP_DEST/Contents/MacOS/"

echo "✓ Installed: $APP_DEST"
echo "▶ Launching Alakeya.app…"
open "$APP_DEST"
