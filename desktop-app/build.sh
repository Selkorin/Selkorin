#!/usr/bin/env bash
# Сборка Selkorin VPN.app на macOS.
# Требуется: macOS + Node.js 18+ (https://nodejs.org). Запуск: bash build.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "==> [1/4] Устанавливаю зависимости (скачается рантайм Electron ~90 МБ)..."
npm install

echo "==> [2/4] Генерирую иконку .icns..."
npm run make-icon

echo "==> [3/4] Собираю .app для Apple Silicon (arm64)..."
npm run pack:mac-arm

echo "==> [4/4] Собираю .app для Intel (x64)..."
npm run pack:mac-x64

APP_ARM="dist/Selkorin VPN-darwin-arm64/Selkorin VPN.app"
APP_X64="dist/Selkorin VPN-darwin-x64/Selkorin VPN.app"

echo
echo "======================================================================"
echo " Готово! Приложения собраны:"
echo "   • Apple Silicon (M1/M2/M3/M4):  $APP_ARM"
echo "   • Intel:                        $APP_X64"
echo
echo " Первый запуск (сборка без подписи Apple):"
echo "   1) Перетащи нужный .app в /Applications"
echo "   2) Сними карантин:  xattr -cr \"/Applications/Selkorin VPN.app\""
echo "   3) Открой обычным двойным кликом."
echo
echo " Для подключения самого Mac к VPN установи WireGuard-инструменты:"
echo "   brew install wireguard-tools"
echo "======================================================================"
