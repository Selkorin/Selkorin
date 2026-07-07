#!/usr/bin/env bash
#
# reality-client-list.sh — список выданных VLESS-ключей + сколько клиентов
# сейчас реально подключено (установленные TCP-соединения к порту Xray).
#
# Формат вывода (машиночитаемый, парсится приложением):
#   <имя>\t<uuid>          — по строке на каждого пользователя
#   SELKORIN_META=<pbk>|<sid>|<sni>|<port>|<ip>
#   SELKORIN_ONLINE=<число>
#
set -euo pipefail

CFG=/usr/local/etc/xray/config.json
ENVF=/usr/local/etc/xray/selkorin.env

[[ $EUID -eq 0 ]] || { echo "SELKORIN_ERR=need root" >&2; exit 1; }
[[ -f "$CFG" ]] || { echo "SELKORIN_NOTINSTALLED"; exit 0; }
command -v jq >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq jq >/dev/null; }

[[ -f "$ENVF" ]] && . "$ENVF"
: "${XRAY_PORT:=$(jq -r '.inbounds[0].port' "$CFG")}"
: "${DEST_SITE:=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CFG")}"
: "${SHORT_ID:=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CFG")}"
if [[ -z "${PUB_KEY:-}" ]]; then
  PRIV="$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CFG")"
  PUB_KEY="$(xray x25519 -i "$PRIV" 2>/dev/null | awk '/Public/{print $NF}')"
fi
: "${PUB_IP:=$(curl -fsS4 https://api.ipify.org 2>/dev/null || curl -fsS4 https://ifconfig.me 2>/dev/null)}"

# Список пользователей
jq -r '.inbounds[0].settings.clients[] | ((.email // "default") + "\t" + .id)' "$CFG"

echo "SELKORIN_META=${PUB_KEY}|${SHORT_ID}|${DEST_SITE}|${XRAY_PORT}|${PUB_IP}"

# Живые подключения: установленные TCP-сессии с локальным портом Xray
ONLINE="$(ss -tn state established 2>/dev/null | awk -v P=":${XRAY_PORT}\$" '$3 ~ P {c++} END{print c+0}')"
echo "SELKORIN_ONLINE=${ONLINE}"
