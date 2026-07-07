#!/usr/bin/env bash
# Сборка Selkorin (клиент) на macOS. Требуется macOS + Node.js 18+.
# Запуск: bash build.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "==> [1/4] Зависимости (скачается рантайм Electron ~90 МБ)..."
npm install

echo "==> [2/4] Иконка .icns..."
npm run make-icon

echo "==> [3/4] Встроенный Xray-core (для VLESS/Reality)..."
mkdir -p resources/xray/arm64 resources/xray/x64
if [[ ! -f resources/xray/arm64/xray ]]; then
  curl -fsSL -o /tmp/xray-arm64.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-macos-arm64-v8a.zip"
  unzip -o /tmp/xray-arm64.zip xray -d resources/xray/arm64
fi
if [[ ! -f resources/xray/x64/xray ]]; then
  curl -fsSL -o /tmp/xray-x64.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-macos-64.zip"
  unzip -o /tmp/xray-x64.zip xray -d resources/xray/x64
fi
chmod +x resources/xray/arm64/xray resources/xray/x64/xray

echo "==> [4/4] Сборка .app (arm64 + x64)..."
npm run pack:mac-arm
npm run pack:mac-x64

echo
echo "Готово:"
echo "  dist/Selkorin-darwin-arm64/Selkorin.app   (M1–M4)"
echo "  dist/Selkorin-darwin-x64/Selkorin.app     (Intel)"
echo "Первый запуск: xattr -cr \"/Applications/Selkorin.app\""
