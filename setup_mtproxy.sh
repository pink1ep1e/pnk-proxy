#!/bin/bash
# ============================================
#   PNK Telegram Proxy — Auto Setup
#   Совместимость: Ubuntu 20.04 / 22.04 / Debian
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PINK='\033[0;35m'
BPINK='\033[1;35m'
BOLD='\033[1m'
NC='\033[0m'

PORT=${1:-443}
DOMAIN=${2:-"vk.ru"}
INSTALL_DIR="/opt/pnk-proxy"
SERVICE_NAME="pnk-proxy"

echo -e "${BPINK}"
echo "  ██████╗ ███╗   ██╗██╗  ██╗"
echo "  ██╔══██╗████╗  ██║██║ ██╔╝"
echo "  ██████╔╝██╔██╗ ██║█████╔╝ "
echo "  ██╔═══╝ ██║╚██╗██║██╔═██╗ "
echo "  ██║     ██║ ╚████║██║  ██╗"
echo "  ╚═╝     ╚═╝  ╚═══╝╚═╝  ╚═╝"
echo -e "${NC}"
echo -e "${BPINK}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BPINK}${BOLD}║       PNK  •  Telegram Proxy Setup       ║${NC}"
echo -e "${BPINK}${BOLD}║      Fast. Secure. Always Online.        ║${NC}"
echo -e "${BPINK}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo -e "${PINK}  MTProto FakeTLS Proxy Installer v1.0${NC}"
echo ""

# ── Root check ──────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[!] Запустите скрипт от root: sudo bash $0${NC}"
  exit 1
fi

# ── Detect arch ─────────────────────────────
ARCH=$(uname -m)
case $ARCH in
  x86_64)  MTG_ARCH="amd64" ;;
  aarch64) MTG_ARCH="arm64" ;;
  armv7*)  MTG_ARCH="arm"   ;;
  *)
    echo -e "${RED}[!] Неподдерживаемая архитектура: $ARCH${NC}"
    exit 1 ;;
esac

echo -e "${GREEN}[✓] Архитектура: $ARCH → mtg-$MTG_ARCH${NC}"

# ── Get public IP ────────────────────────────
echo -e "${BPINK}[→] Определяю публичный IP...${NC}"
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org \
         || curl -s --max-time 5 https://ifconfig.me \
         || curl -s --max-time 5 https://icanhazip.com)

if [[ -z "$SERVER_IP" ]]; then
  echo -e "${RED}[!] Не удалось получить IP. Проверьте интернет.${NC}"
  exit 1
fi
echo -e "${GREEN}[✓] Публичный IP: $SERVER_IP${NC}"

# ── Install dependencies ─────────────────────
echo -e "${BPINK}[→] Устанавливаю зависимости...${NC}"
apt-get update -qq
apt-get install -y -qq wget curl ufw 2>/dev/null || true

# ── Download mtg ────────────────────────────
echo -e "${BPINK}[→] Скачиваю движок прокси...${NC}"
mkdir -p "$INSTALL_DIR"

MTG_URL="https://github.com/9seconds/mtg/releases/latest/download/mtg-linux-${MTG_ARCH}"

wget -q --show-progress -O "$INSTALL_DIR/mtg" "$MTG_URL"
chmod +x "$INSTALL_DIR/mtg"

MTG_VERSION=$("$INSTALL_DIR/mtg" --version 2>/dev/null | head -1 || echo "unknown")
echo -e "${GREEN}[✓] Движок установлен: $MTG_VERSION${NC}"

# ── Generate FakeTLS secret ──────────────────
echo -e "${BPINK}[→] Генерирую FakeTLS secret (маскировка под $DOMAIN)...${NC}"
SECRET=$("$INSTALL_DIR/mtg" generate-secret --hex "$DOMAIN" 2>/dev/null \
      || "$INSTALL_DIR/mtg" generate-secret "$DOMAIN" 2>/dev/null)

if [[ -z "$SECRET" ]]; then
  echo -e "${RED}[!] Не удалось сгенерировать secret.${NC}"
  exit 1
fi
echo -e "${GREEN}[✓] Secret: $SECRET${NC}"

# ── Open firewall port ───────────────────────
echo -e "${BPINK}[→] Открываю порт $PORT/tcp в ufw...${NC}"
ufw allow "$PORT/tcp" >/dev/null 2>&1 || true
echo -e "${GREEN}[✓] Порт $PORT открыт${NC}"

# ── Create systemd service ───────────────────
echo -e "${BPINK}[→] Создаю systemd сервис...${NC}"

cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=PNK Telegram Proxy (MTProto)
After=network.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/mtg run ${SECRET} --bind 0.0.0.0:${PORT}
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
systemctl restart "$SERVICE_NAME"

sleep 2

if systemctl is-active --quiet "$SERVICE_NAME"; then
  echo -e "${GREEN}[✓] Сервис запущен и добавлен в автозагрузку${NC}"
else
  echo -e "${RED}[!] Сервис не запустился. Лог:${NC}"
  journalctl -u "$SERVICE_NAME" --no-pager -n 20
  exit 1
fi

# ── Save config ──────────────────────────────
CONFIG_FILE="/opt/pnk-proxy/proxy.conf"
cat > "$CONFIG_FILE" <<EOF
# PNK Telegram Proxy — config
# Создан: $(date)
SERVER=$SERVER_IP
PORT=$PORT
SECRET=$SECRET
DOMAIN=$DOMAIN
EOF

# ── Build tg:// link ─────────────────────────
TG_LINK="tg://proxy?server=${SERVER_IP}&port=${PORT}&secret=${SECRET}"
HTTPS_LINK="https://t.me/proxy?server=${SERVER_IP}&port=${PORT}&secret=${SECRET}"

echo ""
echo -e "${BPINK}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BPINK}${BOLD}║         💜  PNK PROXY ГОТОВ К РАБОТЕ  💜            ║${NC}"
echo -e "${BPINK}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}📡 Сервер:${NC}   $SERVER_IP"
echo -e "${BOLD}🔌 Порт:${NC}     $PORT"
echo -e "${BOLD}🔑 Secret:${NC}   $SECRET"
echo -e "${BOLD}🌐 Домен:${NC}    $DOMAIN (FakeTLS)"
echo ""
echo -e "${BPINK}${BOLD}🔗 Ссылка для Telegram (мобильный):${NC}"
echo -e "${PINK}$TG_LINK${NC}"
echo ""
echo -e "${BPINK}${BOLD}🔗 Ссылка (браузер / десктоп):${NC}"
echo -e "${PINK}$HTTPS_LINK${NC}"
echo ""
echo -e "${BOLD}💾 Конфиг сохранён:${NC} $CONFIG_FILE"
echo ""
echo -e "${BPINK}${BOLD}⚙️  Управление сервисом:${NC}"
echo -e "  systemctl status  $SERVICE_NAME"
echo -e "  systemctl restart $SERVICE_NAME"
echo -e "  systemctl stop    $SERVICE_NAME"
echo ""
echo -e "${BPINK}  ✦ PNK Telegram Proxy • Fast. Secure. Always Online. ✦${NC}"
echo ""
