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
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# PNK = чёрный бренд → белый/светлый на тёмном терминале
BPINK='\033[1;37m'
PINK='\033[0;37m'

PORT=${1:-443}
DOMAIN=${2:-"vk.com"}
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

# ── Download / build mtg ─────────────────────
echo -e "${BPINK}[→] Устанавливаю движок прокси...${NC}"
mkdir -p "$INSTALL_DIR"

# ── Шаг 0: уже установлен с прошлого запуска? ──
DOWNLOADED=0
EXISTING_PATHS=(
  "$INSTALL_DIR/mtg"
  "$HOME/go/bin/mtg"
  "/root/go/bin/mtg"
  "/usr/local/bin/mtg"
)
for BIN in "${EXISTING_PATHS[@]}"; do
  if [[ -x "$BIN" ]] && "$BIN" --version &>/dev/null; then
    echo -e "${GREEN}[✓] Найден готовый бинарник: $BIN${NC}"
    [[ "$BIN" != "$INSTALL_DIR/mtg" ]] && cp "$BIN" "$INSTALL_DIR/mtg"
    DOWNLOADED=1
    break
  fi
done

# ── Шаг 1: скачать готовый бинарник с зеркал ──
if [[ $DOWNLOADED -eq 0 ]]; then
  MTG_VERSION_TAG=$(curl -s --max-time 8 https://api.github.com/repos/9seconds/mtg/releases/latest \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4)
  MTG_VERSION_TAG=${MTG_VERSION_TAG:-"v2.2.1"}
  echo -e "${BPINK}[→] Версия: $MTG_VERSION_TAG${NC}"

  MIRRORS=(
    "https://github.com/9seconds/mtg/releases/download/${MTG_VERSION_TAG}/mtg-linux-${MTG_ARCH}"
    "https://ghproxy.com/https://github.com/9seconds/mtg/releases/download/${MTG_VERSION_TAG}/mtg-linux-${MTG_ARCH}"
    "https://mirror.ghproxy.com/https://github.com/9seconds/mtg/releases/download/${MTG_VERSION_TAG}/mtg-linux-${MTG_ARCH}"
    "https://gh.api.99988866.xyz/https://github.com/9seconds/mtg/releases/download/${MTG_VERSION_TAG}/mtg-linux-${MTG_ARCH}"
  )

  for MIRROR in "${MIRRORS[@]}"; do
    echo -e "${BPINK}[→] Зеркало: $(echo "$MIRROR" | cut -c1-55)...${NC}"
    wget -q --timeout=25 --tries=2 -O "$INSTALL_DIR/mtg" "$MIRROR" 2>/dev/null || true
    if [[ -s "$INSTALL_DIR/mtg" ]] && file "$INSTALL_DIR/mtg" 2>/dev/null | grep -q "ELF"; then
      echo -e "${GREEN}[✓] Бинарник скачан${NC}"
      DOWNLOADED=1
      break
    fi
    echo -e "${RED}[✗] Не удалось, пробую следующее...${NC}"
    rm -f "$INSTALL_DIR/mtg"
  done
fi

# ── Шаг 2: собрать из исходников через Go ──────
if [[ $DOWNLOADED -eq 0 ]]; then
  echo -e "${BPINK}[→] Зеркала недоступны. Собираю из исходников (3–7 мин)...${NC}"

  GO_OK=0

  # Проверяем версию Go — нужна >= 1.21
  if command -v go &>/dev/null; then
    GO_MINOR=$(go version | grep -oP 'go1\.\K[0-9]+' | head -1)
    [[ "${GO_MINOR:-0}" -ge 19 ]] && GO_OK=1
  fi

  # Если Go нет или старый — ставим свежий через официальный архив
  if [[ $GO_OK -eq 0 ]]; then
    echo -e "${BPINK}[→] Устанавливаю Go 1.22 (официальный архив)...${NC}"
    GO_TAR="go1.22.4.linux-amd64.tar.gz"
    GO_URL="https://go.dev/dl/$GO_TAR"
    # Зеркало для РФ
    GO_MIRROR="https://golang.google.cn/dl/$GO_TAR"

    cd /tmp
    wget -q --timeout=60 --show-progress -O "$GO_TAR" "$GO_URL" 2>/dev/null \
      || wget -q --timeout=60 --show-progress -O "$GO_TAR" "$GO_MIRROR" 2>/dev/null \
      || true

    if [[ -s "$GO_TAR" ]]; then
      rm -rf /usr/local/go
      tar -C /usr/local -xzf "$GO_TAR"
      rm -f "$GO_TAR"
      export PATH="/usr/local/go/bin:$PATH"
      echo -e "${GREEN}[✓] Go $(go version | awk '{print $3}') установлен${NC}"
      GO_OK=1
    else
      echo -e "${RED}[✗] Не удалось скачать Go${NC}"
    fi
    cd -
  fi

  if [[ $GO_OK -eq 1 ]]; then
    export GOPATH="$HOME/go"
    export PATH="$PATH:$GOPATH/bin:/usr/local/go/bin"
    export GOPROXY="https://goproxy.cn,https://goproxy.io,direct"
    export GONOSUMCHECK="*"

    echo -e "${BPINK}[→] Компилирую mtg...${NC}"
    if go install github.com/9seconds/mtg/v2@latest 2>&1; then
      MTG_BIN=$(find "$HOME/go/bin" /root/go/bin -name "mtg" 2>/dev/null | head -1)
      if [[ -n "$MTG_BIN" && -x "$MTG_BIN" ]]; then
        cp "$MTG_BIN" "$INSTALL_DIR/mtg"
        DOWNLOADED=1
        echo -e "${GREEN}[✓] Скомпилировано успешно${NC}"
      fi
    else
      echo -e "${RED}[✗] Компиляция не удалась${NC}"
    fi
  fi
fi

# ── Финальная проверка ─────────────────────────
if [[ $DOWNLOADED -eq 0 ]]; then
  echo -e "${RED}"
  echo "  [!] Не удалось установить движок автоматически."
  echo "  Скачайте бинарник на другой машине и загрузите на сервер:"
  echo "    wget -O mtg https://github.com/9seconds/mtg/releases/download/v2.2.1/mtg-linux-amd64"
  echo "    scp mtg root@${SERVER_IP}:${INSTALL_DIR}/mtg"
  echo "  Затем запустите скрипт снова."
  echo -e "${NC}"
  exit 1
fi

chmod +x "$INSTALL_DIR/mtg"
MTG_VER=$("$INSTALL_DIR/mtg" --version 2>/dev/null | head -1 || echo "unknown")
echo -e "${GREEN}[✓] Движок готов: $MTG_VER${NC}"

# ── Generate FakeTLS secret ──────────────────
echo -e "${BPINK}[→] Генерирую FakeTLS secret (маскировка под $DOMAIN)...${NC}"

# mtg v2: generate-secret --hex <domain>
SECRET=$("$INSTALL_DIR/mtg" generate-secret --hex "$DOMAIN" 2>/dev/null)

# Если --hex не поддерживается (старая версия) — пробуем без флага
if [[ -z "$SECRET" ]]; then
  SECRET=$("$INSTALL_DIR/mtg" generate-secret "$DOMAIN" 2>/dev/null)
fi

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
# mtg v2: используем simple-run <bind-to> <secret> (без конфиг-файла)
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
