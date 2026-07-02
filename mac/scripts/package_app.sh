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
mkdir -p "$APP/Contents/Resources/scripts"

cp "$BINARY" "$APP/Contents/MacOS/Alakeya"
chmod +x "$APP/Contents/MacOS/Alakeya"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [ -f "$ROOT/scripts/browser_agent_extract.py" ]; then
    cp "$ROOT/scripts/browser_agent_extract.py" "$APP/Contents/Resources/scripts/browser_agent_extract.py"
    chmod +x "$APP/Contents/Resources/scripts/browser_agent_extract.py"
fi

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

# ── Code signing ─────────────────────────────────────────────
# TCC (Accessibility / Screen Recording) keys grants to the app's code
# signature. An unsigned/ad-hoc build gets a NEW identity on every
# rebuild, so macOS silently drops previously granted permissions:
# the checkbox in System Settings stays ON, but access stops working.
# Sign with a stable identity to keep permissions across updates.
#
# Set CODESIGN_IDENTITY to your "Developer ID Application: ..." (or a
# self-signed code-signing certificate created once in Keychain Access —
# also stable). Without it we fall back to ad-hoc and warn.
IDENTITY="${CODESIGN_IDENTITY:-}"
ENTITLEMENTS="$ROOT/Alakeya.entitlements"

if [ -n "$IDENTITY" ]; then
    echo "▶ Signing with identity: $IDENTITY"
    codesign --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --identifier "com.selkorin.alakeya" \
        --sign "$IDENTITY" "$APP"
    codesign --verify --deep "$APP" && echo "  ✓ Signature valid"
else
    echo "▶ Signing ad-hoc (no CODESIGN_IDENTITY set)"
    codesign --force --deep \
        --entitlements "$ENTITLEMENTS" \
        --identifier "com.selkorin.alakeya" \
        --sign - "$APP"
    echo "  ⚠ Ad-hoc signature: macOS привяжет разрешения к ЭТОЙ сборке."
    echo "  ⚠ После каждого обновления Accessibility/Запись экрана слетят —"
    echo "  ⚠ сбросьте их в Alakeya → Настройки → Разрешения и выдайте заново,"
    echo "  ⚠ либо задайте CODESIGN_IDENTITY для стабильной подписи:"
    echo "  ⚠   CODESIGN_IDENTITY='Developer ID Application: ...' $0"
fi

VERSION=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?.?.?")
echo "✓ $APP (v$VERSION)"
