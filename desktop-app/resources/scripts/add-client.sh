#!/usr/bin/env bash
#
# add-client.sh — добавить нового клиента (устройство) к WireGuard-серверу.
#
# Создаёт пару ключей + отдельный preshared-ключ (доп. симметричный слой,
# защищает записанный трафик даже от будущих квантовых атак), прописывает пира
# в конфиг сервера и выдаёт готовый .conf + QR-код для телефона.
#
# Запуск:  sudo bash add-client.sh <имя_клиента>
#
set -euo pipefail

WG_DIR="/etc/wireguard"
C_GREEN='\033[0;32m'; C_RED='\033[0;31m'; C_OFF='\033[0m'
log() { echo -e "${C_GREEN}[+]${C_OFF} $*"; }
die() { echo -e "${C_RED}[x]${C_OFF} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запусти от root:  sudo bash $0 <имя>"
[[ -f "$WG_DIR/params.env" ]] || die "Сначала запусти install-server.sh"
# shellcheck disable=SC1091
source "$WG_DIR/params.env"

NAME="${1:-}"
[[ -n "$NAME" ]] || { read -rp "Имя клиента (например phone, laptop): " NAME; }
[[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Имя: только буквы, цифры, - и _"

CLIENT_DIR="$WG_DIR/clients"
mkdir -p "$CLIENT_DIR"
CONF="$CLIENT_DIR/$NAME.conf"
[[ -f "$CONF" ]] && die "Клиент '$NAME' уже существует: $CONF"

### --- Находим свободный IP в подсети ---
BASE_V4="${WG_SRV_V4%.*}"          # 10.66.66
LAST=1
while grep -qs "${BASE_V4}.$((LAST+1))/32" "$WG_DIR/$WG_IFACE.conf"; do LAST=$((LAST+1)); done
CLIENT_NUM=$((LAST+1))
[[ $CLIENT_NUM -le 254 ]] || die "Свободных адресов в подсети не осталось."
CLIENT_V4="${BASE_V4}.${CLIENT_NUM}"
CLIENT_V6="${WG_SRV_V6%::*}::${CLIENT_NUM}"

### --- Ключи клиента и preshared-ключ ---
umask 077
CLIENT_PRIV="$(wg genkey)"
CLIENT_PUB="$(echo "$CLIENT_PRIV" | wg pubkey)"
PSK="$(wg genpsk)"

### --- Добавляем пира в конфиг сервера и применяем без разрыва туннеля ---
cat >>"$WG_DIR/$WG_IFACE.conf" <<EOF

# client: ${NAME}
[Peer]
PublicKey    = ${CLIENT_PUB}
PresharedKey = ${PSK}
AllowedIPs   = ${CLIENT_V4}/32, ${CLIENT_V6}/128
EOF

# Применяем на лету (без обрыва соединений других клиентов)
wg set "$WG_IFACE" peer "$CLIENT_PUB" preshared-key <(echo "$PSK") \
    allowed-ips "${CLIENT_V4}/32,${CLIENT_V6}/128"

### --- Конфиг клиента ---
# DNS = адрес сервера в туннеле → запросы уходят в наш приватный unbound
cat >"$CONF" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address    = ${CLIENT_V4}/24, ${CLIENT_V6}/64
DNS        = ${WG_SRV_V4}, ${WG_SRV_V6}

[Peer]
PublicKey    = ${SRV_PUB}
PresharedKey = ${PSK}
Endpoint     = ${PUB_IP}:${WG_PORT}
# 0.0.0.0/0 + ::/0 = весь трафик через VPN (full tunnel, защита от утечек)
AllowedIPs   = 0.0.0.0/0, ::/0
PersistentKeepalive = ${KEEPALIVE}
EOF
chmod 600 "$CONF"

echo
log "Клиент '${NAME}' создан."
echo "    Файл конфигурации: ${CONF}"
echo "    Адрес в VPN      : ${CLIENT_V4}"
echo
echo "  QR-код для телефона (WireGuard → '+' → Сканировать QR):"
echo
qrencode -t ansiutf8 <"$CONF"
echo
echo "  Скачать конфиг на свой компьютер:"
echo "    scp root@${PUB_IP}:${CONF} ."
