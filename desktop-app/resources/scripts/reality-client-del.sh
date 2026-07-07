#!/usr/bin/env bash
#
# reality-client-del.sh — отозвать VLESS-ключ пользователя по имени.
#
# Запуск:  sudo bash reality-client-del.sh <имя>
#
set -euo pipefail

CFG=/usr/local/etc/xray/config.json
die() { echo "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запусти от root"
[[ -f "$CFG" ]] || die "Reality не установлен"
command -v jq >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq jq >/dev/null; }

NAME="${1:-}"
[[ -n "$NAME" ]] || die "Укажи имя пользователя"

BEFORE="$(jq '.inbounds[0].settings.clients | length' "$CFG")"
TMP="$(mktemp)"
jq --arg e "$NAME" \
  '(.inbounds[0].settings.clients) |= map(select((.email // "default") != $e))' \
  "$CFG" >"$TMP" && mv "$TMP" "$CFG"
AFTER="$(jq '.inbounds[0].settings.clients | length' "$CFG")"

[[ "$AFTER" -lt "$BEFORE" ]] || die "Пользователь '$NAME' не найден"

systemctl restart xray
sleep 1
systemctl is-active --quiet xray || die "Xray не перезапустился"
echo "SELKORIN_DELETED=$NAME"
