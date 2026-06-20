#!/bin/bash
# Builds Alakeya and launches it as a proper .app bundle (no Terminal window).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
BINARY="$ROOT/.build/$CONFIG/Alakeya"
RESOURCE_BUNDLE="$ROOT/.build/$CONFIG/Alakeya_Alakeya.bundle"
APP="$ROOT/.build/Alakeya.app"

cd "$ROOT"

echo "▶ Building ($CONFIG)..."
swift build $([ "$CONFIG" = "release" ] && echo "-c release" || true)

echo "▶ Packaging $APP..."
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/Alakeya"
chmod +x "$APP/Contents/MacOS/Alakeya"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# App icon
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# SwiftPM resource bundle must sit next to the binary so Bundle.module resolves correctly.
if [ -d "$RESOURCE_BUNDLE" ]; then
    rm -rf "$APP/Contents/MacOS/Alakeya_Alakeya.bundle"
    cp -R "$RESOURCE_BUNDLE" "$APP/Contents/MacOS/"
fi

echo "▶ Launching Alakeya.app..."
open "$APP"
