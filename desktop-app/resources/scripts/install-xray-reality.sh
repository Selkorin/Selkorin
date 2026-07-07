#!/usr/bin/env bash
#
# install-xray-reality.sh — установка Xray (VLESS + Vision + Reality).
#
# Зачем: если провайдер/DPI режет WireGuard, этот протокол маскирует твой
# трафик под обычное TLS-соединение к реальному крупному сайту. Со стороны
# наблюдателя это неотличимо от захода на www.microsoft.com — нет "отпечатка"
# VPN, нечего блокировать. Это текущий эталон обхода блокировок.
#
# Поддержка: Ubuntu/Debian. Запуск: sudo bash install-xray-reality.sh
#
set -euo pipefail

# Сайт-маскировка: должен работать по TLS 1.3 + HTTP/2 и быть не заблокирован.
# Хорошие варианты: www.microsoft.com, www.cloudflare.com, dl.google.com, www.samsung.com
DEST_SITE="${DEST_SITE:-www.microsoft.com}"
XRAY_PORT="${XRAY_PORT:-443}"

C_GREEN='\033[0;32m'; C_YEL='\033[1;33m'; C_RED='\033[0;31m'; C_OFF='\033[0m'
log()  { echo -e "${C_GREEN}[+]${C_OFF} $*"; }
warn() { echo -e "${C_YEL}[!]${C_OFF} $*"; }
die()  { echo -e "${C_RED}[x]${C_OFF} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запусти от root: sudo bash $0"

log "Ставлю Xray-core (официальный установщик)..."
apt-get update -qq && apt-get install -y -qq curl qrencode ca-certificates jq >/dev/null
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null

PUB_IP="$(curl -fsS4 https://api.ipify.org || curl -fsS4 https://ifconfig.me)"

log "Генерирую ключи Reality и идентификаторы..."
KEYS="$(xray x25519)"
PRIV_KEY="$(echo "$KEYS" | awk '/Private/{print $NF}')"
PUB_KEY="$(echo "$KEYS"  | awk '/Public/{print $NF}')"
UUID="$(xray uuid)"
SHORT_ID="$(openssl rand -hex 8)"

log "Пишу конфиг /usr/local/etc/xray/config.json (маскировка под ${DEST_SITE})..."
cat >/usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "${UUID}", "flow": "xtls-rprx-vision", "email": "default" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST_SITE}:443",
          "xver": 0,
          "serverNames": ["${DEST_SITE}"],
          "privateKey": "${PRIV_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF

# Сохраняем параметры для генератора ключей (reality-client-*.sh)
cat >/usr/local/etc/xray/selkorin.env <<EOF
PUB_IP=${PUB_IP}
XRAY_PORT=${XRAY_PORT}
DEST_SITE=${DEST_SITE}
PUB_KEY=${PUB_KEY}
SHORT_ID=${SHORT_ID}
EOF
chmod 600 /usr/local/etc/xray/selkorin.env

systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray
sleep 1
systemctl is-active --quiet xray || { journalctl -u xray -n 20 --no-pager; die "Xray не запустился"; }

# Готовая ссылка для импорта в клиент (v2rayNG / Nekoray / Streisand / v2box / Hiddify)
LINK="vless://${UUID}@${PUB_IP}:${XRAY_PORT}?encryption=none&security=reality&sni=${DEST_SITE}&fp=chrome&pbk=${PUB_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#Reality-${PUB_IP}"

echo
log "Готово! Xray VLESS+Reality работает."
echo "-------------------------------------------------------------"
echo "  Сервер (endpoint) : ${PUB_IP}:${XRAY_PORT}"
echo "  UUID              : ${UUID}"
echo "  Public key (pbk)  : ${PUB_KEY}"
echo "  Short ID (sid)    : ${SHORT_ID}"
echo "  SNI (маскировка)  : ${DEST_SITE}"
echo "-------------------------------------------------------------"
echo
echo "  Ссылка для импорта в приложение (скопируй целиком):"
echo
echo "  ${LINK}"
echo
echo "  QR-код (импорт в v2rayNG/Hiddify: '+' → Сканировать QR):"
echo
qrencode -t ansiutf8 <<<"$LINK"
echo
echo "  Сохрани ссылку — второй раз она не показывается."
