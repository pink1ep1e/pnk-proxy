#!/bin/bash
# ============================================
#   PNK Telegram Proxy — Auto Setup
#   Совместимость: Ubuntu 20.04 / 22.04 / Debian
#   © PNK Telegram Proxy
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# PNK = чёрный бренд → белый/светлый на тёмном терминале
BPINK='\033[1;37m'
PINK='\033[0;37m'

PORT=${1:-443}
DOMAIN=${2:-"web.max.ru"}
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

# ── Download / build mtg v2.1.7 ──────────────
echo -e "${BPINK}[→] Устанавливаю движок прокси (mtg v2.1.7)...${NC}"
mkdir -p "$INSTALL_DIR"
MTG_TARGET_VERSION="v2.1.7"

# Функция: проверить что бинарник именно v2.1.7 (не dev-сборка)
is_valid_mtg() {
  local bin="$1"
  [[ -x "$bin" ]] || return 1
  local ver
  ver=$("$bin" --version 2>/dev/null | tr -d '[:space:]')
  # Принимаем только релизные версии (v2.x.x), отвергаем "dev"
  [[ "$ver" =~ ^v2\.[0-9]+\.[0-9]+$ ]] || return 1
  return 0
}

DOWNLOADED=0

# ── Шаг 0: уже есть валидный бинарник? ──────
if is_valid_mtg "$INSTALL_DIR/mtg"; then
  echo -e "${GREEN}[✓] Найден валидный бинарник: $("$INSTALL_DIR/mtg" --version 2>/dev/null)${NC}"
  DOWNLOADED=1
fi

# ── Шаг 1: скачать готовый бинарник с зеркал ──
if [[ $DOWNLOADED -eq 0 ]]; then
  echo -e "${BPINK}[→] Пробую скачать готовый бинарник...${NC}"
  MIRRORS=(
    "https://github.com/9seconds/mtg/releases/download/${MTG_TARGET_VERSION}/mtg-linux-${MTG_ARCH}"
    "https://ghproxy.com/https://github.com/9seconds/mtg/releases/download/${MTG_TARGET_VERSION}/mtg-linux-${MTG_ARCH}"
    "https://mirror.ghproxy.com/https://github.com/9seconds/mtg/releases/download/${MTG_TARGET_VERSION}/mtg-linux-${MTG_ARCH}"
    "https://gh.api.99988866.xyz/https://github.com/9seconds/mtg/releases/download/${MTG_TARGET_VERSION}/mtg-linux-${MTG_ARCH}"
  )
  for MIRROR in "${MIRRORS[@]}"; do
    echo -e "${BPINK}[→] $(echo "$MIRROR" | cut -c1-58)...${NC}"
    wget -q --timeout=25 --tries=2 -O "$INSTALL_DIR/mtg.tmp" "$MIRROR" 2>/dev/null || true
    if [[ -s "$INSTALL_DIR/mtg.tmp" ]] && file "$INSTALL_DIR/mtg.tmp" | grep -q "ELF"; then
      mv "$INSTALL_DIR/mtg.tmp" "$INSTALL_DIR/mtg"
      chmod +x "$INSTALL_DIR/mtg"
      if is_valid_mtg "$INSTALL_DIR/mtg"; then
        echo -e "${GREEN}[✓] Бинарник скачан: $("$INSTALL_DIR/mtg" --version 2>/dev/null)${NC}"
        DOWNLOADED=1
        break
      fi
    fi
    rm -f "$INSTALL_DIR/mtg.tmp" "$INSTALL_DIR/mtg"
    echo -e "${RED}[✗] Не удалось, пробую следующее...${NC}"
  done
fi

# ── Шаг 2: собрать из исходников через Go ──────
if [[ $DOWNLOADED -eq 0 ]]; then
  echo -e "${BPINK}[→] Зеркала недоступны. Собираю v2.1.7 из исходников...${NC}"

  GO_OK=0
  if command -v go &>/dev/null; then
    GO_MINOR=$(go version | grep -oP 'go1\.\K[0-9]+' | head -1)
    [[ "${GO_MINOR:-0}" -ge 18 ]] && GO_OK=1
  fi

  if [[ $GO_OK -eq 0 ]]; then
    echo -e "${BPINK}[→] Устанавливаю Go 1.22...${NC}"
    GO_TAR="go1.22.4.linux-amd64.tar.gz"
    cd /tmp
    wget -q --timeout=60 -O "$GO_TAR" "https://go.dev/dl/$GO_TAR" 2>/dev/null \
      || wget -q --timeout=60 -O "$GO_TAR" "https://golang.google.cn/dl/$GO_TAR" 2>/dev/null || true
    if [[ -s "$GO_TAR" ]]; then
      rm -rf /usr/local/go
      tar -C /usr/local -xzf "$GO_TAR" && rm -f "$GO_TAR"
      export PATH="/usr/local/go/bin:$PATH"
      GO_OK=1
      echo -e "${GREEN}[✓] Go установлен: $(go version | awk '{print $3}')${NC}"
    fi
    cd - >/dev/null
  fi

  if [[ $GO_OK -eq 1 ]]; then
    export GOPATH="/tmp/gopath-mtg"
    export GOBIN="$INSTALL_DIR"
    export PATH="$PATH:/usr/local/go/bin"
    export GOPROXY="https://goproxy.cn,https://goproxy.io,direct"
    export GONOSUMCHECK="*"
    export GOFLAGS="-mod=mod"

    echo -e "${BPINK}[→] Компилирую mtg ${MTG_TARGET_VERSION} (2–5 мин)...${NC}"
    # Устанавливаем строго v2.1.7, бинарник попадёт в $GOBIN/mtg
    if go install "github.com/9seconds/mtg/v2@${MTG_TARGET_VERSION}" 2>&1 | tail -3; then
      chmod +x "$INSTALL_DIR/mtg" 2>/dev/null || true
      if is_valid_mtg "$INSTALL_DIR/mtg"; then
        DOWNLOADED=1
        echo -e "${GREEN}[✓] Скомпилировано: $("$INSTALL_DIR/mtg" --version 2>/dev/null)${NC}"
      fi
    fi
    rm -rf /tmp/gopath-mtg
  fi
fi

if [[ $DOWNLOADED -eq 0 ]]; then
  echo -e "${RED}[!] Не удалось установить движок. Обратитесь в поддержку PNK Proxy.${NC}"
  exit 1
fi

chmod +x "$INSTALL_DIR/mtg"

# ── Generate FakeTLS secret ──────────────────
# mtg v2.1.7: generate-secret <hostname>  →  возвращает base64-secret
echo -e "${BPINK}[→] Генерирую FakeTLS secret (маскировка под $DOMAIN)...${NC}"
SECRET=$("$INSTALL_DIR/mtg" generate-secret "$DOMAIN" 2>/dev/null | tr -d '[:space:]')

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
# mtg v2.1.7 синтаксис: simple-run <bind-to> <secret>
echo -e "${BPINK}[→] Создаю systemd сервис...${NC}"

cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=PNK Telegram Proxy (MTProto)
After=network.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/mtg simple-run 0.0.0.0:${PORT} ${SECRET}
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
echo -e "${BPINK}${BOLD}║         ◼  PNK PROXY ГОТОВ К РАБОТЕ  ◼            ║${NC}"
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
