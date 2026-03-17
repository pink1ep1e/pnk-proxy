#!/bin/bash
# ============================================
#   PNK Telegram Proxy — Auto Setup v2.0
#   Совместимость: Ubuntu 20.04 / 22.04 / Debian
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BPINK='\033[1;37m'
PINK='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/pnk-proxy"
SERVICE_NAME="pnk-proxy"
CONFIG_FILE="$INSTALL_DIR/proxy.conf"

print_logo() {
  clear
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
  echo -e "${PINK}  MTProto FakeTLS Proxy Installer v2.0${NC}"
  echo ""
}

is_installed() {
  [[ -f "$CONFIG_FILE" ]] && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

show_links() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}[!] Прокси не установлен${NC}"; return
  fi
  local IP PORT SECRET DOMAIN
  IP=$(grep "^SERVER=" "$CONFIG_FILE" | cut -d= -f2)
  PORT=$(grep "^PORT=" "$CONFIG_FILE" | cut -d= -f2)
  SECRET=$(grep "^SECRET=" "$CONFIG_FILE" | cut -d= -f2)
  DOMAIN=$(grep "^DOMAIN=" "$CONFIG_FILE" | cut -d= -f2)
  echo ""
  echo -e "${BPINK}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${BPINK}${BOLD}║              ◼  ДАННЫЕ ПРОКСИ  ◼                    ║${NC}"
  echo -e "${BPINK}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BOLD}📡 Сервер:${NC}   $IP"
  echo -e "${BOLD}🔌 Порт:${NC}     $PORT"
  echo -e "${BOLD}🔑 Secret:${NC}   $SECRET"
  echo -e "${BOLD}🌐 Домен:${NC}    $DOMAIN (FakeTLS)"
  echo ""
  echo -e "${BPINK}${BOLD}🔗 Ссылка (мобильный):${NC}"
  echo -e "${PINK}tg://proxy?server=${IP}&port=${PORT}&secret=${SECRET}${NC}"
  echo ""
  echo -e "${BPINK}${BOLD}🔗 Ссылка (браузер / десктоп):${NC}"
  echo -e "${PINK}https://t.me/proxy?server=${IP}&port=${PORT}&secret=${SECRET}${NC}"
  echo ""
}

# ── Подсчёт активных подключений ────────────
get_connections() {
  local PORT
  PORT=$(grep "^PORT=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
  [[ -z "$PORT" ]] && echo "0" && return
  # Считаем установленные TCP соединения на порту прокси
  local TOTAL UNIQUE_IPS
  TOTAL=$(ss -tn state established "( dport = :${PORT} or sport = :${PORT} )" 2>/dev/null | grep -c "ESTAB" || echo 0)
  # Уникальные IP (каждый клиент открывает несколько соединений)
  UNIQUE_IPS=$(ss -tn state established "( dport = :${PORT} or sport = :${PORT} )" 2>/dev/null \
    | awk 'NR>1 {print $5}' | cut -d: -f1 | sort -u | grep -v "^$" | wc -l || echo 0)
  echo "$TOTAL $UNIQUE_IPS"
}

show_status() {
  echo ""
  echo -e "${BPINK}${BOLD}── Статус сервиса ──────────────────────────────────────${NC}"
  if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "${GREEN}[✓] Сервис запущен и работает${NC}"
    local UPTIME
    UPTIME=$(systemctl show "$SERVICE_NAME" --property=ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)
    echo -e "${BOLD}⏱  Запущен:${NC}  $UPTIME"

    # Подключения
    local CONN_DATA TOTAL UNIQUE
    CONN_DATA=$(get_connections)
    TOTAL=$(echo "$CONN_DATA" | awk '{print $1}')
    UNIQUE=$(echo "$CONN_DATA" | awk '{print $2}')
    echo -e "${BOLD}👥 Пользователей:${NC} ${GREEN}${UNIQUE}${NC} (соединений: ${TOTAL})"

    # Список IP подключённых пользователей
    local PORT
    PORT=$(grep "^PORT=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
    local IPS
    IPS=$(ss -tn state established "( dport = :${PORT} or sport = :${PORT} )" 2>/dev/null \
      | awk 'NR>1 {print $5}' | cut -d: -f1 | sort -u | grep -v "^$")
    if [[ -n "$IPS" ]]; then
      echo -e "${BOLD}🌍 Активные IP:${NC}"
      while IFS= read -r ip; do
        echo -e "   ${PINK}• $ip${NC}"
      done <<< "$IPS"
    fi
  else
    echo -e "${RED}[✗] Сервис не запущен${NC}"
  fi

  # Статистика из логов — сколько всего было соединений за сессию
  echo ""
  echo -e "${BPINK}${BOLD}── Статистика из логов ─────────────────────────────────${NC}"
  local TOTAL_CONN UNIQUE_CLIENTS
  TOTAL_CONN=$(journalctl -u "$SERVICE_NAME" --no-pager -n 1000 2>/dev/null \
    | grep -c "client-ip" || echo 0)
  UNIQUE_CLIENTS=$(journalctl -u "$SERVICE_NAME" --no-pager -n 1000 2>/dev/null \
    | grep "client-ip" | grep -oP '"client-ip":"[^"]+' | sort -u | wc -l || echo 0)
  echo -e "${BOLD}📈 Соединений в логах:${NC} $TOTAL_CONN"
  echo -e "${BOLD}👤 Уникальных клиентов:${NC} $UNIQUE_CLIENTS"

  echo ""
  echo -e "${BPINK}${BOLD}── Последние логи ──────────────────────────────────────${NC}"
  journalctl -u "$SERVICE_NAME" --no-pager -n 8 2>/dev/null || echo "Логи недоступны"
  echo ""
}

regenerate_secret() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}[!] Прокси не установлен${NC}"; return
  fi
  local PORT DOMAIN IP
  PORT=$(grep "^PORT=" "$CONFIG_FILE" | cut -d= -f2)
  DOMAIN=$(grep "^DOMAIN=" "$CONFIG_FILE" | cut -d= -f2)
  IP=$(grep "^SERVER=" "$CONFIG_FILE" | cut -d= -f2)
  echo -e "${BPINK}[→] Генерирую новый FakeTLS secret...${NC}"
  local DOMAIN_HEX RANDOM_HEX SECRET
  DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p | tr -d '\n')
  RANDOM_HEX=$(openssl rand -hex 16)
  SECRET="ee${RANDOM_HEX}${DOMAIN_HEX}"
  sed -i "s|simple-run 0.0.0.0:${PORT} .*|simple-run 0.0.0.0:${PORT} $SECRET|" /etc/systemd/system/${SERVICE_NAME}.service
  sed -i "s|^SECRET=.*|SECRET=$SECRET|" "$CONFIG_FILE"
  systemctl daemon-reload && systemctl restart "$SERVICE_NAME"
  sleep 1
  echo -e "${GREEN}[✓] Новый secret: $SECRET${NC}"
  echo ""
  echo -e "${BPINK}${BOLD}🔗 Новая ссылка:${NC}"
  echo -e "${PINK}https://t.me/proxy?server=${IP}&port=${PORT}&secret=${SECRET}${NC}"
  echo ""
}

change_domain() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}[!] Прокси не установлен${NC}"; return
  fi
  echo ""
  echo -e "${BPINK}Выберите домен маскировки:${NC}"
  echo "  1) vk.com"
  echo "  2) ya.ru"
  echo "  3) ok.ru"
  echo "  4) mail.ru"
  echo "  5) Ввести свой"
  echo ""
  read -rp "Выбор [1-5]: " DOMAIN_CHOICE
  case $DOMAIN_CHOICE in
    1) NEW_DOMAIN="vk.com" ;;
    2) NEW_DOMAIN="ya.ru" ;;
    3) NEW_DOMAIN="ok.ru" ;;
    4) NEW_DOMAIN="mail.ru" ;;
    5) read -rp "Введите домен: " NEW_DOMAIN ;;
    *) echo -e "${RED}[!] Неверный выбор${NC}"; return ;;
  esac
  local PORT IP DOMAIN_HEX RANDOM_HEX SECRET
  PORT=$(grep "^PORT=" "$CONFIG_FILE" | cut -d= -f2)
  IP=$(grep "^SERVER=" "$CONFIG_FILE" | cut -d= -f2)
  DOMAIN_HEX=$(echo -n "$NEW_DOMAIN" | xxd -p | tr -d '\n')
  RANDOM_HEX=$(openssl rand -hex 16)
  SECRET="ee${RANDOM_HEX}${DOMAIN_HEX}"
  sed -i "s|simple-run 0.0.0.0:${PORT} .*|simple-run 0.0.0.0:${PORT} $SECRET|" /etc/systemd/system/${SERVICE_NAME}.service
  sed -i "s|^SECRET=.*|SECRET=$SECRET|" "$CONFIG_FILE"
  sed -i "s|^DOMAIN=.*|DOMAIN=$NEW_DOMAIN|" "$CONFIG_FILE"
  systemctl daemon-reload && systemctl restart "$SERVICE_NAME"
  sleep 1
  echo -e "${GREEN}[✓] Домен изменён на: $NEW_DOMAIN${NC}"
  echo ""
  echo -e "${BPINK}${BOLD}🔗 Новая ссылка:${NC}"
  echo -e "${PINK}https://t.me/proxy?server=${IP}&port=${PORT}&secret=${SECRET}${NC}"
  echo ""
}

restart_proxy() {
  echo -e "${BPINK}[→] Перезапускаю прокси...${NC}"
  systemctl restart "$SERVICE_NAME"
  sleep 1
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${GREEN}[✓] Прокси перезапущен${NC}"
  else
    echo -e "${RED}[!] Ошибка при перезапуске${NC}"
    journalctl -u "$SERVICE_NAME" --no-pager -n 5
  fi
  echo ""
}

remove_proxy() {
  echo ""
  echo -e "${RED}${BOLD}Вы уверены что хотите удалить PNK Proxy? [y/N]${NC}"
  read -rp "> " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Отменено."; return
  fi
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f /etc/systemd/system/${SERVICE_NAME}.service
  rm -rf "$INSTALL_DIR"
  systemctl daemon-reload
  echo -e "${GREEN}[✓] PNK Proxy удалён${NC}"
  echo ""
  exit 0
}

show_menu() {
  while true; do
    print_logo
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
      echo -e "  Статус: ${GREEN}● Работает${NC}"
      # Счётчик подключений прямо в меню
      local CONN_DATA TOTAL UNIQUE
      CONN_DATA=$(get_connections)
      TOTAL=$(echo "$CONN_DATA" | awk '{print $1}')
      UNIQUE=$(echo "$CONN_DATA" | awk '{print $2}')
      echo -e "  Онлайн: ${GREEN}👥 ${UNIQUE} польз.${NC} / ${TOTAL} соед."
    else
      echo -e "  Статус: ${RED}● Остановлен${NC}"
    fi
    local IP PORT
    IP=$(grep "^SERVER=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
    PORT=$(grep "^PORT=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
    echo -e "  Сервер: ${BPINK}${IP}:${PORT}${NC}"
    echo ""
    echo -e "${BPINK}${BOLD}  ┌─────────────────────────────────┐${NC}"
    echo -e "${BPINK}${BOLD}  │         ГЛАВНОЕ МЕНЮ            │${NC}"
    echo -e "${BPINK}${BOLD}  ├─────────────────────────────────┤${NC}"
    echo -e "${BPINK}${BOLD}  │${NC}  1) 🔗 Показать ссылки          ${BPINK}${BOLD}│${NC}"
    echo -e "${BPINK}${BOLD}  │${NC}  2) 📊 Статус и логи            ${BPINK}${BOLD}│${NC}"
    echo -e "${BPINK}${BOLD}  │${NC}  3) 🔑 Новый secret             ${BPINK}${BOLD}│${NC}"
    echo -e "${BPINK}${BOLD}  │${NC}  4) 🌐 Сменить домен            ${BPINK}${BOLD}│${NC}"
    echo -e "${BPINK}${BOLD}  │${NC}  5) 🔄 Перезапустить            ${BPINK}${BOLD}│${NC}"
    echo -e "${BPINK}${BOLD}  │${NC}  6) 🗑  Удалить прокси          ${BPINK}${BOLD}│${NC}"
    echo -e "${BPINK}${BOLD}  │${NC}  0) 🚪 Выход                    ${BPINK}${BOLD}│${NC}"
    echo -e "${BPINK}${BOLD}  └─────────────────────────────────┘${NC}"
    echo ""
    read -rp "  Выбор [0-6]: " CHOICE
    case $CHOICE in
      1) print_logo; show_links; read -rp "  Нажмите Enter..." ;;
      2) print_logo; show_status; read -rp "  Нажмите Enter..." ;;
      3) print_logo; regenerate_secret; read -rp "  Нажмите Enter..." ;;
      4) print_logo; change_domain; read -rp "  Нажмите Enter..." ;;
      5) print_logo; restart_proxy; read -rp "  Нажмите Enter..." ;;
      6) print_logo; remove_proxy ;;
      0) echo ""; echo -e "${BPINK}  ✦ PNK Telegram Proxy • Fast. Secure. Always Online. ✦${NC}"; echo ""; exit 0 ;;
      *) echo -e "${RED}  [!] Неверный выбор${NC}"; sleep 1 ;;
    esac
  done
}

# ════════════════════════════════════════════
#   ТОЧКА ВХОДА
# ════════════════════════════════════════════

if is_installed; then
  show_menu
  exit 0
fi

# ── Установка ────────────────────────────────
set -e
print_logo

PORT=${1:-443}
DOMAIN=${2:-"vk.com"}

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[!] Запустите скрипт от root: sudo bash $0${NC}"; exit 1
fi

ARCH=$(uname -m)
case $ARCH in
  x86_64)  MTG_ARCH="amd64" ;;
  aarch64) MTG_ARCH="arm64" ;;
  armv7*)  MTG_ARCH="arm"   ;;
  *) echo -e "${RED}[!] Неподдерживаемая архитектура: $ARCH${NC}"; exit 1 ;;
esac
echo -e "${GREEN}[✓] Архитектура: $ARCH${NC}"

echo -e "${BPINK}[→] Определяю публичный IP...${NC}"
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org \
         || curl -s --max-time 5 https://ifconfig.me \
         || curl -s --max-time 5 https://icanhazip.com)
if [[ -z "$SERVER_IP" ]]; then
  echo -e "${RED}[!] Не удалось получить IP.${NC}"; exit 1
fi
echo -e "${GREEN}[✓] Публичный IP: $SERVER_IP${NC}"

echo -e "${BPINK}[→] Устанавливаю зависимости...${NC}"
apt-get update -qq
apt-get install -y -qq wget curl ufw xxd openssl 2>/dev/null || true

echo -e "${BPINK}[→] Устанавливаю движок прокси (mtg v2.1.7)...${NC}"
mkdir -p "$INSTALL_DIR"
MTG_TARGET_VERSION="v2.1.7"

is_valid_mtg() {
  local bin="$1"
  [[ -x "$bin" ]] || return 1
  local ver
  ver=$("$bin" --version 2>/dev/null | tr -d '[:space:]')
  [[ "$ver" =~ ^v2\.[0-9]+\.[0-9]+$ ]] || return 1
  return 0
}

DOWNLOADED=0
if is_valid_mtg "$INSTALL_DIR/mtg"; then
  echo -e "${GREEN}[✓] Найден валидный бинарник${NC}"; DOWNLOADED=1
fi

if [[ $DOWNLOADED -eq 0 ]]; then
  MIRRORS=(
    "https://raw.githubusercontent.com/pink1ep1e/pnk-proxy/main/mtg-2.1.7-linux-${MTG_ARCH}.tar.gz"
    "https://github.com/9seconds/mtg/releases/download/${MTG_TARGET_VERSION}/mtg-linux-${MTG_ARCH}"
    "https://ghproxy.com/https://github.com/9seconds/mtg/releases/download/${MTG_TARGET_VERSION}/mtg-linux-${MTG_ARCH}"
    "https://mirror.ghproxy.com/https://github.com/9seconds/mtg/releases/download/${MTG_TARGET_VERSION}/mtg-linux-${MTG_ARCH}"
  )
  for MIRROR in "${MIRRORS[@]}"; do
    echo -e "${BPINK}[→] $(echo "$MIRROR" | cut -c1-62)...${NC}"
    TMPFILE="$INSTALL_DIR/mtg.tmp"
    wget -q --timeout=30 --tries=2 -O "$TMPFILE" "$MIRROR" 2>/dev/null || true
    if [[ ! -s "$TMPFILE" ]]; then
      echo -e "${RED}[✗] Пусто${NC}"; rm -f "$TMPFILE"; continue
    fi
    if file "$TMPFILE" | grep -q "gzip\|tar"; then
      tar -xzf "$TMPFILE" -C "$INSTALL_DIR" 2>/dev/null || true
      rm -f "$TMPFILE"
      MTG_BIN=$(find "$INSTALL_DIR" -maxdepth 2 -name "mtg" -type f 2>/dev/null | head -1)
      [[ -n "$MTG_BIN" && "$MTG_BIN" != "$INSTALL_DIR/mtg" ]] && mv "$MTG_BIN" "$INSTALL_DIR/mtg"
    elif file "$TMPFILE" | grep -q "ELF"; then
      mv "$TMPFILE" "$INSTALL_DIR/mtg"
    else
      echo -e "${RED}[✗] Неизвестный формат${NC}"; rm -f "$TMPFILE"; continue
    fi
    chmod +x "$INSTALL_DIR/mtg" 2>/dev/null || true
    if is_valid_mtg "$INSTALL_DIR/mtg"; then
      echo -e "${GREEN}[✓] Бинарник готов${NC}"; DOWNLOADED=1; break
    fi
    rm -f "$INSTALL_DIR/mtg"
    echo -e "${RED}[✗] Не прошёл проверку${NC}"
  done
fi

if [[ $DOWNLOADED -eq 0 ]]; then
  echo -e "${BPINK}[→] Собираю из исходников через Go...${NC}"
  GO_OK=0
  if command -v go &>/dev/null; then
    GO_MINOR=$(go version | grep -oP 'go1\.\K[0-9]+' | head -1)
    [[ "${GO_MINOR:-0}" -ge 18 ]] && GO_OK=1
  fi
  if [[ $GO_OK -eq 0 ]]; then
    GO_TAR="go1.22.4.linux-amd64.tar.gz"
    cd /tmp
    wget -q --timeout=60 -O "$GO_TAR" "https://go.dev/dl/$GO_TAR" 2>/dev/null \
      || wget -q --timeout=60 -O "$GO_TAR" "https://golang.google.cn/dl/$GO_TAR" 2>/dev/null || true
    if [[ -s "$GO_TAR" ]]; then
      rm -rf /usr/local/go
      tar -C /usr/local -xzf "$GO_TAR" && rm -f "$GO_TAR"
      export PATH="/usr/local/go/bin:$PATH"
      GO_OK=1
    fi
    cd - >/dev/null
  fi
  if [[ $GO_OK -eq 1 ]]; then
    export GOPATH="/tmp/gopath-mtg"
    export PATH="$PATH:/usr/local/go/bin"
    export GOPROXY="https://goproxy.cn,https://goproxy.io,direct"
    export GONOSUMCHECK="*"
    export GOFLAGS="-mod=mod"
    mkdir -p "$GOPATH"
    unset GOBIN
    if go install "github.com/9seconds/mtg/v2@${MTG_TARGET_VERSION}" 2>&1 | tail -3; then
      MTG_BIN=$(find "$GOPATH/bin" /root/go/bin "$HOME/go/bin" \
                     -maxdepth 2 \( -name "mtg" -o -name "v2" \) \
                     -type f 2>/dev/null | head -1)
      if [[ -n "$MTG_BIN" && -x "$MTG_BIN" ]]; then
        cp "$MTG_BIN" "$INSTALL_DIR/mtg"
        chmod +x "$INSTALL_DIR/mtg"
        "$INSTALL_DIR/mtg" --help 2>&1 | grep -q "simple-run" && DOWNLOADED=1
      fi
    fi
    rm -rf /tmp/gopath-mtg
  fi
fi

if [[ $DOWNLOADED -eq 0 ]]; then
  echo -e "${RED}[!] Не удалось установить движок.${NC}"; exit 1
fi

chmod +x "$INSTALL_DIR/mtg"

echo -e "${BPINK}[→] Генерирую FakeTLS secret (маскировка под $DOMAIN)...${NC}"
DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p | tr -d '\n')
RANDOM_HEX=$(openssl rand -hex 16)
SECRET="ee${RANDOM_HEX}${DOMAIN_HEX}"
echo -e "${GREEN}[✓] Secret: $SECRET${NC}"

echo -e "${BPINK}[→] Открываю порт $PORT/tcp...${NC}"
ufw allow "$PORT/tcp" >/dev/null 2>&1 || true
echo -e "${GREEN}[✓] Порт $PORT открыт${NC}"

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
  echo -e "${GREEN}[✓] Сервис запущен${NC}"
else
  echo -e "${RED}[!] Сервис не запустился:${NC}"
  journalctl -u "$SERVICE_NAME" --no-pager -n 10
  exit 1
fi

cat > "$CONFIG_FILE" <<EOF
# PNK Telegram Proxy — config
# Создан: $(date)
SERVER=$SERVER_IP
PORT=$PORT
SECRET=$SECRET
DOMAIN=$DOMAIN
EOF

TG_LINK="tg://proxy?server=${SERVER_IP}&port=${PORT}&secret=${SECRET}"
HTTPS_LINK="https://t.me/proxy?server=${SERVER_IP}&port=${PORT}&secret=${SECRET}"

echo ""
echo -e "${BPINK}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BPINK}${BOLD}║         ◼  PNK PROXY ГОТОВ К РАБОТЕ  ◼              ║${NC}"
echo -e "${BPINK}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}📡 Сервер:${NC}   $SERVER_IP"
echo -e "${BOLD}🔌 Порт:${NC}     $PORT"
echo -e "${BOLD}🔑 Secret:${NC}   $SECRET"
echo -e "${BOLD}🌐 Домен:${NC}    $DOMAIN (FakeTLS)"
echo ""
echo -e "${BPINK}${BOLD}🔗 Ссылка (мобильный):${NC}"
echo -e "${PINK}$TG_LINK${NC}"
echo ""
echo -e "${BPINK}${BOLD}🔗 Ссылка (браузер / десктоп):${NC}"
echo -e "${PINK}$HTTPS_LINK${NC}"
echo ""
echo -e "${BOLD}💡 Для управления запустите скрипт снова${NC}"
echo ""
echo -e "${BPINK}  ✦ PNK Telegram Proxy • Fast. Secure. Always Online. ✦${NC}"
echo ""

# После установки открываем меню
read -rp "  Открыть меню управления? [Y/n]: " OPEN_MENU
if [[ "$OPEN_MENU" != "n" && "$OPEN_MENU" != "N" ]]; then
  show_menu
fi
