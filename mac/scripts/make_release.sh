#!/bin/bash
# Builds a release archive of Alakeya.app and prints the release checklist.
# Usage: ./scripts/make_release.sh [version]
#
# TODO: Before public release:
#   1. Set up Developer ID Application certificate
#   2. codesign --deep --force --verify --sign "Developer ID Application: ..." Alakeya.app
#   3. xcrun notarytool submit Alakeya-VERSION.zip --apple-id ... --team-id ... --password ...
#   4. xcrun stapler staple Alakeya.app
#   5. Generate Sparkle EdDSA key pair (store private key in secure location, never in repo):
#      sign_update Alakeya-VERSION.zip --ed-key private_key
#   6. Update releases/appcast.json with new version + sparkle:edSignature
#   7. Upload zip + appcast to HTTPS server
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(defaults read "$ROOT/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")}"
BUILD=$(defaults read "$ROOT/Resources/Info.plist" CFBundleVersion 2>/dev/null || echo "0")
APP_BUILD="$ROOT/.build/Alakeya.app"
ARCHIVE="$ROOT/.build/Alakeya-${VERSION}.zip"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Alakeya Release Builder v${VERSION} (build ${BUILD})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Build + package
bash "$ROOT/scripts/package_app.sh" release

# 2. Create zip archive
echo "▶ Creating archive…"
rm -f "$ARCHIVE"
cd "$ROOT/.build"
zip -r --symlinks "Alakeya-${VERSION}.zip" "Alakeya.app"
cd "$ROOT"
echo "✓ $ARCHIVE"
echo "  Size: $(du -sh "$ARCHIVE" | cut -f1)"

# 3. Compute SHA256 (informational)
SHA256=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
echo "  SHA-256: $SHA256"

# 4. Print checklist
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  RELEASE CHECKLIST"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[ ] Code signing: codesign --deep --sign 'Developer ID Application: ...'"
echo "[ ] Notarization: xcrun notarytool submit + stapler staple"
echo "[ ] Sign archive for Sparkle: sign_update Alakeya-${VERSION}.zip --ed-key <key>"
echo "[ ] Update releases/appcast.json:"
echo "      version: ${VERSION}"
echo "      build:   ${BUILD}"
echo "      sha256:  ${SHA256}"
echo "      downloadURL: https://releases.selkorin.com/alakeya/Alakeya-${VERSION}.zip"
echo "[ ] Upload archive to HTTPS server"
echo "[ ] Upload appcast.json to https://updates.selkorin.com/alakeya/appcast.json"
echo "[ ] Tag release in git: git tag v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
