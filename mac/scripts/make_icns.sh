#!/bin/bash
# Generates AppIcon.icns from a source PNG.
# Output: Resources/AppIcon.icns
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/Sources/Alakeya/Resources/ALAKEYA_logo_transparent.png}"
OUT="$ROOT/Resources/AppIcon.icns"
TMPDIR_ICNS="$(mktemp -d)"
TMP="$TMPDIR_ICNS/AppIcon.iconset"
SQUARE="$TMPDIR_ICNS/square.png"

if [ ! -f "$SRC" ]; then
    echo "✗ Source image not found: $SRC"
    exit 1
fi

echo "▶ Source: $SRC"
mkdir -p "$TMP"

# --- Make a 1024×1024 square version ---
if command -v convert &>/dev/null; then
    # ImageMagick: pad to square with transparent background
    convert "$SRC" -gravity center -background none \
        -resize 1024x1024 \
        -extent 1024x1024 \
        "$SQUARE"
else
    # sips fallback: scale to fit 1024 wide, then make square canvas
    # (slight letterbox distortion — acceptable for dev icon)
    sips -z 1024 1024 "$SRC" --out "$SQUARE" &>/dev/null
fi

# --- Generate all required iconset sizes ---
generate() {
    local SIZE=$1
    local SUFFIX=$2
    local OUT_FILE="$TMP/icon_${SIZE}x${SIZE}${SUFFIX}.png"
    local PX=$3
    sips -z "$PX" "$PX" "$SQUARE" --out "$OUT_FILE" &>/dev/null
}

generate 16   ""   16
generate 16   "@2x" 32
generate 32   ""   32
generate 32   "@2x" 64
generate 128  ""   128
generate 128  "@2x" 256
generate 256  ""   256
generate 256  "@2x" 512
generate 512  ""   512
generate 512  "@2x" 1024

echo "▶ Building AppIcon.icns…"
iconutil -c icns "$TMP" -o "$OUT"

rm -rf "$TMPDIR_ICNS"
echo "✓ $OUT"
