#!/usr/bin/env bash
#
# del-client.sh — отозвать доступ клиента (устройства).
# Удаляет пира из работающего туннеля и из конфига сервера.
#
# Запуск:  sudo bash del-client.sh <имя_клиента>
#
set -euo pipefail

WG_DIR="/etc/wireguard"
C_GREEN='\033[0;32m'; C_RED='\033[0;31m'; C_OFF='\033[0m'
log() { echo -e "${C_GREEN}[+]${C_OFF} $*"; }
die() { echo -e "${C_RED}[x]${C_OFF} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запусти от root: sudo bash $0 <имя>"
[[ -f "$WG_DIR/params.env" ]] || die "Сначала запусти install-server.sh"
# shellcheck disable=SC1091
source "$WG_DIR/params.env"

NAME="${1:-}"
[[ -n "$NAME" ]] || { read -rp "Имя клиента для удаления: " NAME; }
CONF="$WG_DIR/clients/$NAME.conf"
[[ -f "$CONF" ]] || die "Клиент '$NAME' не найден."

# Достаём публичный ключ клиента из его приватного ключа
CLIENT_PRIV="$(awk -F'= *' '/PrivateKey/{print $2; exit}' "$CONF")"
CLIENT_PUB="$(echo "$CLIENT_PRIV" | wg pubkey)"

# Убираем из живого туннеля
wg set "$WG_IFACE" peer "$CLIENT_PUB" remove || true

# Убираем блок [Peer] с комментарием "# client: <name>" из конфига сервера
tmp="$(mktemp)"
awk -v name="# client: ${NAME}" '
  $0==name {skip=1; next}
  skip && /^\[Peer\]/ {next}
  skip && (/^PublicKey/||/^PresharedKey/||/^AllowedIPs/) {next}
  skip && (/^$/||/^\[/||/^# client:/) {skip=0}
  {print}
' "$WG_DIR/$WG_IFACE.conf" >"$tmp"
mv "$tmp" "$WG_DIR/$WG_IFACE.conf"
chmod 600 "$WG_DIR/$WG_IFACE.conf"

rm -f "$CONF"
log "Клиент '${NAME}' отозван и удалён."
