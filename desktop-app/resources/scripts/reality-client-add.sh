#!/usr/bin/env bash
#
# reality-client-add.sh — выдать новый VLESS-ключ (пользователя) на уже
# установленном Xray Reality. Каждому пользователю — свой UUID, поэтому доступ
# можно отзывать по отдельности.
#
# Запуск:  sudo bash reality-client-add.sh <имя>
#
set -euo pipefail

CFG=/usr/local/etc/xray/config.json
ENVF=/usr/local/etc/xray/selkorin.env

die() { echo "SELKORIN_ERR=$*" >&2; echo "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запусти от root"
[[ -f "$CFG" ]] || { echo "SELKORIN_NOTINSTALLED"; exit 2; }
command -v jq >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq jq >/dev/null; }

NAME="${1:-}"
[[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Имя: только буквы, цифры, - и _"

load_meta() {
  [[ -f "$ENVF" ]] && . "$ENVF"
  : "${XRAY_PORT:=$(jq -r '.inbounds[0].port' "$CFG")}"
  : "${DEST_SITE:=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CFG")}"
  : "${SHORT_ID:=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CFG")}"
  if [[ -z "${PUB_KEY:-}" ]]; then
    local priv; priv="$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CFG")"
    PUB_KEY="$(xray x25519 -i "$priv" 2>/dev/null | awk '/Public/{print $NF}')"
  fi
  : "${PUB_IP:=$(curl -fsS4 https://api.ipify.org 2>/dev/null || curl -fsS4 https://ifconfig.me 2>/dev/null)}"
}
load_meta

# Уже есть такой пользователь?
if jq -e --arg e "$NAME" '.inbounds[0].settings.clients[]|select((.email // "default")==$e)' "$CFG" >/dev/null 2>&1; then
  echo "SELKORIN_EXISTS=$NAME"; exit 3
fi

UUID="$(xray uuid)"
TMP="$(mktemp)"
jq --arg id "$UUID" --arg e "$NAME" \
  '.inbounds[0].settings.clients += [{"id":$id,"flow":"xtls-rprx-vision","email":$e}]' \
  "$CFG" >"$TMP" && mv "$TMP" "$CFG"

systemctl restart xray
sleep 1
systemctl is-active --quiet xray || die "Xray не перезапустился после добавления ключа"

LINK="vless://${UUID}@${PUB_IP}:${XRAY_PORT}?encryption=none&security=reality&sni=${DEST_SITE}&fp=chrome&pbk=${PUB_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#${NAME}"
echo "SELKORIN_LINK=${LINK}"
