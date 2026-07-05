#!/usr/bin/env bash
#
# install-server.sh — установка усиленного WireGuard-сервера "под ключ".
#
# Что делает:
#   * Ставит WireGuard, unbound (свой приватный DNS), nftables, fail2ban, qrencode.
#   * Генерирует ключи сервера, поднимает интерфейс wg0.
#   * Включает NAT/маршрутизацию, настраивает файрвол по принципу "запрещено всё, кроме нужного".
#   * Усиливает ядро (sysctl) и SSH.
#   * Включает автоматические обновления безопасности.
#
# Поддержка: Ubuntu 20.04/22.04/24.04, Debian 11/12.
# Запуск:   sudo bash install-server.sh
#
set -euo pipefail

### --- Настройки (можно переопределить переменными окружения) ---
WG_IFACE="${WG_IFACE:-wg0}"
WG_PORT="${WG_PORT:-51820}"            # порт WireGuard (UDP)
WG_NET_V4="${WG_NET_V4:-10.66.66.0/24}"
WG_SRV_V4="${WG_SRV_V4:-10.66.66.1}"
WG_NET_V6="${WG_NET_V6:-fd42:66:66::/64}"
WG_SRV_V6="${WG_SRV_V6:-fd42:66:66::1}"
WG_DIR="/etc/wireguard"
KEEPALIVE="${KEEPALIVE:-25}"

C_GREEN='\033[0;32m'; C_YEL='\033[1;33m'; C_RED='\033[0;31m'; C_OFF='\033[0m'
log()  { echo -e "${C_GREEN}[+]${C_OFF} $*"; }
warn() { echo -e "${C_YEL}[!]${C_OFF} $*"; }
die()  { echo -e "${C_RED}[x]${C_OFF} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запусти скрипт от root:  sudo bash $0"

### --- Определяем внешний интерфейс и публичный IP ---
WAN_IFACE="$(ip -4 route show default | awk '/default/{print $5; exit}')"
[[ -n "$WAN_IFACE" ]] || die "Не удалось определить внешний сетевой интерфейс."
PUB_IP="$(curl -fsS4 https://api.ipify.org || curl -fsS4 https://ifconfig.me || true)"
[[ -n "$PUB_IP" ]] || { read -rp "Не смог узнать публичный IP. Введи вручную: " PUB_IP; }
log "Внешний интерфейс: ${WAN_IFACE}, публичный IP: ${PUB_IP}, порт WG: ${WG_PORT}/udp"

### --- Установка пакетов ---
log "Ставлю пакеты..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq wireguard wireguard-tools nftables unbound unbound-anchor \
    qrencode fail2ban curl iproute2 unattended-upgrades ca-certificates >/dev/null

### --- Включаем форвардинг пакетов + усиление ядра ---
log "Настраиваю параметры ядра (sysctl)..."
cat >/etc/sysctl.d/99-wireguard-hardening.conf <<EOF
# Маршрутизация трафика клиентов
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Защита от спуфинга адресов
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Игнорировать редиректы и source-routing (защита от MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Защита от SYN-флуда
net.ipv4.tcp_syncookies = 1

# Логировать марсианские пакеты
net.ipv4.conf.all.log_martians = 1

# TCP BBR — быстрее и стабильнее на дальних каналах
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl --system >/dev/null

### --- Генерация ключей сервера ---
umask 077
mkdir -p "$WG_DIR"
if [[ ! -f "$WG_DIR/server_private.key" ]]; then
    log "Генерирую ключи сервера..."
    wg genkey | tee "$WG_DIR/server_private.key" | wg pubkey >"$WG_DIR/server_public.key"
fi
SRV_PRIV="$(cat "$WG_DIR/server_private.key")"
SRV_PUB="$(cat "$WG_DIR/server_public.key")"

### --- Конфиг сервера wg0.conf ---
log "Пишу ${WG_DIR}/${WG_IFACE}.conf..."
cat >"$WG_DIR/$WG_IFACE.conf" <<EOF
# Конфиг WireGuard-сервера. Пиры добавляются скриптом add-client.sh
# NAT/маршрутизация вынесены в постоянный /etc/nftables.conf (переживает ребут).
[Interface]
Address    = ${WG_SRV_V4}/24, ${WG_SRV_V6}/64
ListenPort = ${WG_PORT}
PrivateKey = ${SRV_PRIV}
EOF
chmod 600 "$WG_DIR/$WG_IFACE.conf"

### --- Приватный DNS (unbound) — DNS-запросы не покидают наш сервер ---
log "Настраиваю приватный рекурсивный DNS (unbound)..."
cat >/etc/unbound/unbound.conf.d/wg-dns.conf <<EOF
server:
    verbosity: 0
    interface: 127.0.0.1
    interface: ${WG_SRV_V4}
    interface: ${WG_SRV_V6}
    ip-freebind: yes
    port: 53
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes
    # Доступ только для localhost и подсети VPN
    access-control: 127.0.0.0/8 allow
    access-control: ${WG_NET_V4} allow
    access-control: ${WG_NET_V6} allow
    access-control: 0.0.0.0/0 refuse
    access-control: ::/0 refuse
    # Приватность: не сохраняем и не отдаём лишнего
    hide-identity: yes
    hide-version: yes
    qname-minimisation: yes
    aggressive-nsec: yes
    prefetch: yes
    use-caps-for-id: yes
    cache-min-ttl: 300
    rrset-roundrobin: yes
    # Не отвечаем на приватные диапазоны из интернета (rebinding protection)
    private-address: 10.0.0.0/8
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: fd00::/8
    private-address: fe80::/10
EOF
systemctl enable unbound >/dev/null 2>&1 || true
systemctl restart unbound || warn "unbound не стартовал — проверь: journalctl -u unbound"

### --- Файрвол nftables: запрещено всё, кроме SSH, WG и трафика VPN ---
log "Настраиваю файрвол (nftables)..."
SSH_PORT="$(ss -tlnp 2>/dev/null | awk '/sshd/{split($4,a,":"); print a[length(a)]; exit}')"
SSH_PORT="${SSH_PORT:-22}"
cat >/etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        ct state established,related accept
        ct state invalid drop
        iif "lo" accept
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept

        tcp dport ${SSH_PORT} accept        # SSH
        udp dport ${WG_PORT} accept          # WireGuard

        # DNS только изнутри VPN-туннеля
        iifname "${WG_IFACE}" udp dport 53 accept
        iifname "${WG_IFACE}" tcp dport 53 accept
    }
    chain forward {
        type filter hook forward priority 0; policy drop;
        ct state established,related accept
        iifname "${WG_IFACE}" accept
        oifname "${WG_IFACE}" accept
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}

# NAT: выпускаем трафик клиентов VPN в интернет через внешний интерфейс.
# Здесь (а не в PostUp WireGuard) — чтобы правило переживало перезагрузку.
table inet nat {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname "${WAN_IFACE}" ip saddr ${WG_NET_V4} masquerade
        oifname "${WAN_IFACE}" ip6 saddr ${WG_NET_V6} masquerade
    }
}
EOF
systemctl enable nftables >/dev/null 2>&1 || true
systemctl restart nftables

### --- SSH-хардненинг (осторожно: не отключаем пароль, если нет ключей) ---
log "Усиливаю SSH..."
SSHD=/etc/ssh/sshd_config.d/99-hardening.conf
mkdir -p /etc/ssh/sshd_config.d
{
    echo "PermitRootLogin prohibit-password"
    echo "Protocol 2"
    echo "MaxAuthTries 3"
    echo "LoginGraceTime 20"
    echo "X11Forwarding no"
    echo "ClientAliveInterval 300"
    echo "ClientAliveCountMax 2"
} >"$SSHD"
# Отключаем вход по паролю только если у root уже есть ключ (иначе не заблокируем себя)
if [[ -s /root/.ssh/authorized_keys ]]; then
    echo "PasswordAuthentication no" >>"$SSHD"
    log "Найдены SSH-ключи — вход по паролю отключён."
else
    warn "SSH-ключей не найдено — оставляю вход по паролю. Добавь ключ и потом отключи пароль!"
fi
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

### --- fail2ban (защита SSH от перебора) ---
cat >/etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port    = ${SSH_PORT}
maxretry = 4
bantime  = 1h
findtime = 10m
EOF
systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban || warn "fail2ban не стартовал"

### --- Автообновления безопасности ---
log "Включаю автоматические обновления безопасности..."
echo 'APT::Periodic::Update-Package-Lists "1";'  >/etc/apt/apt.conf.d/20auto-upgrades
echo 'APT::Periodic::Unattended-Upgrade "1";'   >>/etc/apt/apt.conf.d/20auto-upgrades

### --- Запуск WireGuard ---
log "Поднимаю интерфейс ${WG_IFACE}..."
systemctl enable "wg-quick@${WG_IFACE}" >/dev/null 2>&1 || true
systemctl restart "wg-quick@${WG_IFACE}"

### --- Сохраняем параметры для add-client.sh ---
cat >"$WG_DIR/params.env" <<EOF
WG_IFACE=${WG_IFACE}
WG_PORT=${WG_PORT}
WG_NET_V4=${WG_NET_V4}
WG_SRV_V4=${WG_SRV_V4}
WG_NET_V6=${WG_NET_V6}
WG_SRV_V6=${WG_SRV_V6}
SRV_PUB=${SRV_PUB}
PUB_IP=${PUB_IP}
KEEPALIVE=${KEEPALIVE}
EOF
chmod 600 "$WG_DIR/params.env"

echo
log "Готово! Сервер WireGuard поднят."
echo "    Публичный ключ сервера : ${SRV_PUB}"
echo "    Endpoint для клиентов  : ${PUB_IP}:${WG_PORT}"
echo
echo "  Дальше добавь клиента:   sudo bash add-client.sh <имя>"
echo "  Например:                sudo bash add-client.sh phone"
