#!/bin/bash
# Builds and packages Alakeya.app into .build/Alakeya.app
# Does NOT install to /Applications — use install_app.sh for that.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
BINARY="$ROOT/.build/$CONFIG/Alakeya"
RESOURCE_BUNDLE="$ROOT/.build/$CONFIG/Alakeya_Alakeya.bundle"
APP="$ROOT/.build/Alakeya.app"
ICNS="$ROOT/Resources/AppIcon.icns"

cd "$ROOT"

echo "▶ Building ($CONFIG)…"
swift build $([ "$CONFIG" = "release" ] && echo "-c release" || true)

echo "▶ Packaging $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/Alakeya"
chmod +x "$APP/Contents/MacOS/Alakeya"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# App icon
if [ -f "$ICNS" ]; then
    cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
    echo "  ✓ AppIcon.icns included"
else
    echo "  ⚠ AppIcon.icns not found — run scripts/make_icns.sh first"
fi

# SwiftPM resource bundle
if [ -d "$RESOURCE_BUNDLE" ]; then
    rm -rf "$APP/Contents/MacOS/Alakeya_Alakeya.bundle"
    cp -R "$RESOURCE_BUNDLE" "$APP/Contents/MacOS/"
fi

VERSION=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?.?.?")
echo "✓ $APP (v$VERSION)"
