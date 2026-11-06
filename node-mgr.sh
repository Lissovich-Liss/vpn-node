#!/usr/bin/env bash
# ==============================================================================
#  LissVPN Node Orchestrator & Diagnostic Toolkit v3.4.0 (node-mgr)
#  Repository: https://github.com/Lissovich-Liss/vpn-node
#  Remnawave API Auto-Deploy • Caddy Selfsteal • UFW (Strict ACL) • Fail2ban
#  Integrated 27-Point Node Diagnostic & Kernel/NIC/RPS/MSS/Zram Optimizer
# ==============================================================================

set -Eeuo pipefail

# Принудительная UTF-8 локаль без побайтового разрыва символов
if locale -a 2>/dev/null | grep -qiE '^C\.UTF-8$|^C\.utf8$'; then
    export LC_ALL=C.UTF-8 LANG=C.UTF-8
elif locale -a 2>/dev/null | grep -qiE '^en_US\.UTF-8$|^en_US\.utf8$'; then
    export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
fi

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Ошибка: требуется bash версии 4.0 или выше (текущая: $BASH_VERSION)" >&2
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════
#  Фирменная палитра LissVPN (Dark Graphite #151419 + Lava Orange #F56E0F)
# ═══════════════════════════════════════════════════════════════════
readonly ORANGE=$'\033[38;2;245;110;15m'
readonly GRAPHITE=$'\033[38;2;110;118;129m'
readonly SLATE=$'\033[38;2;175;184;193m'
readonly WHITE=$'\033[38;2;251;251;251m'
readonly GREEN=$'\033[38;2;46;204;113m'
readonly YELLOW=$'\033[38;2;241;196;15m'
readonly RED=$'\033[38;2;231;76;60m'
readonly NC=$'\033[0m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'

# ═══════════════════════════════════════════════════════════════════
#  Константы, пути и стейт диагностики
# ═══════════════════════════════════════════════════════════════════
readonly SCRIPT_VERSION="3.4.0"
readonly BIN_PATH="/usr/local/bin/node-mgr"
readonly REPO_RAW_URL="https://raw.githubusercontent.com/Lissovich-Liss/vpn-node/main/node-mgr.sh"
readonly INSTALL_LOG="/var/log/remnanode-install.log"

readonly ND_STATE_DIR="/var/lib/node-mgr"
readonly FINDINGS_FILE="${ND_STATE_DIR}/findings.env"
readonly FIX_LOG="${ND_STATE_DIR}/applied-fixes.log"
readonly API_STATE_FILE="${ND_STATE_DIR}/remnawave-api.env"
readonly ND_DROPIN_PREFIX="99-lissvpn"
readonly ND_BOX_W=68

readonly INSTALL_DIR="/opt"
readonly REMNANODE_DIR="${INSTALL_DIR}/remnanode"
readonly REMNANODE_DATA_DIR="/var/lib/remnanode"
readonly CADDY_DIR="${INSTALL_DIR}/selfsteel"
readonly CADDY_HTML_DIR="${INSTALL_DIR}/html"
readonly CADDY_CONTAINER_NAME="caddy-remnawave"
readonly CADDY_DATA_VOL="selfsteel_caddy_data_selfsteal"
readonly CADDY_CONFIG_VOL="selfsteel_caddy_config_selfsteal"
readonly DEFAULT_PORT="9443"

mkdir -p "$(dirname "$INSTALL_LOG")" "$ND_STATE_DIR" 2>/dev/null || true
if [ -f "$INSTALL_LOG" ] && [ "$(stat -c%s "$INSTALL_LOG" 2>/dev/null || echo 0)" -gt 5242880 ]; then
    tail -n 2000 "$INSTALL_LOG" > "${INSTALL_LOG}.tmp" && mv -f "${INSTALL_LOG}.tmp" "$INSTALL_LOG"
fi
echo "--- Запуск LissVPN Node Orchestrator v${SCRIPT_VERSION}: $(date -u +'%Y-%m-%d %H:%M:%S UTC') ---" >> "$INSTALL_LOG" 2>/dev/null || true

TEMP_FILES=()

_cleanup_on_exit() {
    local exit_code=$?
    if [ "${_RESTORE_AUTO_UPDATES:-false}" = true ]; then
        restore_auto_updates 2>/dev/null || true
    fi
    for f in "${TEMP_FILES[@]}"; do
        rm -f "$f" 2>/dev/null || true
    done
    return $exit_code
}

trap 'log_error "Сбой на строке $LINENO (код: $?). Команда: $BASH_COMMAND"' ERR
trap '_cleanup_on_exit' EXIT

# ═══════════════════════════════════════════════════════════════════
#  Переменные окружения и Non-interactive параметры
# ═══════════════════════════════════════════════════════════════════
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
CONFIG_FILE="${CONFIG_FILE:-/etc/remnanode-install.conf}"

# Переменные для API-автоматизации Remnawave
REMNAWAVE_API_URL="${REMNAWAVE_API_URL:-}"
REMNAWAVE_API_TOKEN="${REMNAWAVE_API_TOKEN:-}"
NODE_NAME="${NODE_NAME:-}"
NODE_ADDRESS="${NODE_ADDRESS:-}"
SELF_STEAL_DOMAIN="${SELF_STEAL_DOMAIN:-}"
SELF_STEAL_PORT="${SELF_STEAL_PORT:-$DEFAULT_PORT}"

# Классические CFG_* переменные (совместимость)
CFG_SECRET_KEY="${CFG_SECRET_KEY:-}"
CFG_NODE_PORT="${CFG_NODE_PORT:-3000}"
CFG_PANEL_IP="${CFG_PANEL_IP:-}"
CFG_INSTALL_XRAY="${CFG_INSTALL_XRAY:-y}"
CFG_DOMAIN="${CFG_DOMAIN:-}"
CFG_CADDY_PORT="${CFG_CADDY_PORT:-$DEFAULT_PORT}"
CFG_APPLY_NETWORK="${CFG_APPLY_NETWORK:-y}"
CFG_SETUP_UFW="${CFG_SETUP_UFW:-y}"
CFG_INSTALL_FAIL2BAN="${CFG_INSTALL_FAIL2BAN:-y}"

STATUS_NETWORK="пропущен"
STATUS_DOCKER="пропущен"
STATUS_CADDY="пропущен"
STATUS_API="пропущен"
STATUS_REMNANODE="пропущен"
STATUS_UFW="пропущен"
STATUS_FAIL2BAN="пропущен"

DETAIL_REMNANODE_PORT=""
DETAIL_PANEL_IP=""
DETAIL_CADDY_DOMAIN=""
DETAIL_CADDY_PORT=""
DETAIL_NODE_UUID=""
DETAIL_PROFILE_UUID=""
DETAIL_HOST_UUID=""
NODE_IP=""
OS=""
PKG_MANAGER=""

# ═══════════════════════════════════════════════════════════════════
#  UI-примитивы (прямой вывод в TTY)
# ═══════════════════════════════════════════════════════════════════
_write_log() {
    printf '[%s] %s\n' "$(date +'%H:%M:%S')" "$*" >> "$INSTALL_LOG" 2>/dev/null || true
}

log_info()    { _write_log "[INFO] $*"; echo -e "  ${ORANGE}${BOLD}[i]${NC}  ${WHITE}$*${NC}"; }
log_success() { _write_log "[ OK ] $*"; echo -e "  ${GREEN}${BOLD}[+]${NC}  ${WHITE}$*${NC}"; }
log_warning() { _write_log "[WARN] $*"; echo -e "  ${YELLOW}${BOLD}[!]${NC}  ${YELLOW}$*${NC}"; }
log_error()   { _write_log "[FAIL] $*"; echo -e "  ${RED}${BOLD}[x]${NC}  ${RED}$*${NC}" >&2; }

ui_rule() {
    local char="${1:--}"
    local width="${2:-$ND_BOX_W}"
    printf "  %s" "${GRAPHITE}"
    for ((i=1; i<=width; i++)); do printf "%s" "$char"; done
    printf "%s\n" "${NC}"
}

box_top() {
    local title="$1"
    local tlen=${#title}
    local pad=$(( ND_BOX_W - tlen - 5 ))
    if [ $pad -lt 2 ]; then pad=2; fi
    printf "  %s┌─ %s%s%s " "${GRAPHITE}" "${ORANGE}${BOLD}" "$title" "${NC}${GRAPHITE}"
    for ((i=1; i<=pad; i++)); do printf "─"; done
    printf "┐%s\n" "${NC}"
}

box_row() {
    printf "  %s│%s %b\n" "${GRAPHITE}" "${NC}" "$1"
}

box_kv() {
    local key="$1"
    local val="$2"
    printf "  %s│%s  ${SLATE}%-22s${NC} %b\n" "${GRAPHITE}" "${NC}" "${key}:" "${WHITE}${val}${NC}"
}

box_bottom() {
    printf "  %s└" "${GRAPHITE}"
    for ((i=1; i<=ND_BOX_W; i++)); do printf "─"; done
    printf "┘%s\n" "${NC}"
}

print_header() {
    local title="$1"
    echo
    box_top "$title"
    box_bottom
    echo
}

detect_virt() {
    local v="bare-metal"
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        v=$(systemd-detect-virt 2>/dev/null || echo "bare-metal")
        if [ "$v" = "none" ]; then v="bare-metal"; fi
    fi
    echo "$v"
}

print_banner() {
    echo
    echo -e "  ${ORANGE}${BOLD}LISSVPN NODE ORCHESTRATOR${NC}  ${GRAPHITE}v${SCRIPT_VERSION} · node-mgr toolkit${NC}"
    ui_rule "─"
    echo -e "  ${GRAPHITE}$(date -u +'%Y-%m-%d %H:%M UTC') · $(hostname) · $(detect_virt) · IP: ${WHITE}${NODE_IP:-...}${NC}"
}

# ═══════════════════════════════════════════════════════════════════
#  Базовые хелперы и безопасные детекторы
# ═══════════════════════════════════════════════════════════════════
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_error "Требуются права суперпользователя (запустите через sudo или от root)"
        exit 1
    fi
}

self_install() {
    local src_script
    if [ -f "$0" ]; then
        src_script="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
        if [[ "$src_script" != "$BIN_PATH" ]] && [[ "$src_script" != /dev/fd/* ]] && [[ "$src_script" != /proc/* ]]; then
            if [ ! -f "$BIN_PATH" ] || ! cmp -s "$src_script" "$BIN_PATH"; then
                cp -f "$src_script" "$BIN_PATH"
                chmod 755 "$BIN_PATH"
                log_success "Утилита зарегистрирована глобально: ${ORANGE}node-mgr${NC}"
            fi
        fi
    fi
}

create_temp_file() {
    local tmp
    tmp=$(mktemp)
    TEMP_FILES+=("$tmp")
    echo "$tmp"
}

is_container_running() {
    local cname="$1"
    if ! command -v docker >/dev/null 2>&1; then
        return 1
    fi
    local st
    st=$(docker inspect -f '{{.State.Running}}' "$cname" 2>/dev/null || echo "false")
    if [ "$st" = "true" ]; then
        return 0
    fi
    return 1
}

is_caddy_running() {
    if is_container_running "$CADDY_CONTAINER_NAME" || is_container_running "caddy-selfsteal"; then
        return 0
    fi
    return 1
}

check_container_health() {
    local cname="$1"
    local max_wait="${2:-30}"
    local waited=0
    while [ $waited -lt "$max_wait" ]; do
        if is_container_running "$cname"; then
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    return 1
}

get_server_ip() {
    local ip=""
    ip=$(curl -s -4 --connect-timeout 3 --max-time 5 https://ifconfig.io 2>/dev/null | tr -d '[:space:]') || true
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        ip=$(curl -s -4 --connect-timeout 3 --max-time 5 https://icanhazip.com 2>/dev/null | tr -d '[:space:]') || true
    fi
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}') || true
    fi
    echo "${ip:-127.0.0.1}"
}

detect_default_iface() {
    ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

detect_ssh_port() {
    local port=""
    if [ -n "${SSH_CONNECTION:-}" ]; then
        port="$(awk '{print $4}' <<< "$SSH_CONNECTION")"
    fi
    if [ -z "$port" ] && command -v sshd >/dev/null 2>&1; then
        port="$(sshd -T 2>/dev/null | awk '/^port / {print $2; exit}' || true)"
    fi
    if [ -z "$port" ] && [ -f /etc/ssh/sshd_config ]; then
        port="$(grep -Ei '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $NF; exit}' || true)"
    fi
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        port="22"
    fi
    echo "$port"
}

validate_ip_or_cidr() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})(/([0-9]{1,2}))?$ ]]; then
        local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}" o3="${BASH_REMATCH[3]}" o4="${BASH_REMATCH[4]}" mask="${BASH_REMATCH[6]:-32}"
        if [ "$o1" -le 255 ] && [ "$o2" -le 255 ] && [ "$o3" -le 255 ] && [ "$o4" -le 255 ] && [ "$mask" -le 32 ]; then
            return 0
        fi
        return 1
    fi
    if [[ "$ip" =~ : ]]; then
        return 0
    fi
    return 1
}

resolve_host_to_ip() {
    local host="$1"
    host=$(echo "$host" | sed -E 's|^https?://||; s|/.*$||; s|:.*$||')
    if validate_ip_or_cidr "$host"; then
        echo "$host"
        return 0
    fi
    local resolved=""
    resolved=$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1; exit}' || true)
    if [ -z "$resolved" ] && command -v dig >/dev/null 2>&1; then
        resolved=$(dig +short "$host" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
    fi
    echo "$resolved"
}

get_saved_panel_ip() {
    local pip="${DETAIL_PANEL_IP:-${CFG_PANEL_IP:-}}"
    if [ -z "$pip" ] && [ -f "$REMNANODE_DIR/.env" ]; then
        pip=$(grep -E '^PANEL_IP=' "$REMNANODE_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    if [ -z "$pip" ] && [ -f "$API_STATE_FILE" ]; then
        pip=$(grep -E '^PANEL_IP=' "$API_STATE_FILE" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    echo "$pip"
}

get_saved_node_port() {
    local nport="${DETAIL_REMNANODE_PORT:-}"
    if [ -z "$nport" ] && [ -f "$REMNANODE_DIR/.env" ]; then
        nport=$(grep -E '^NODE_PORT=' "$REMNANODE_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    if [ -z "$nport" ] && [ -f "$REMNANODE_DIR/docker-compose.yml" ]; then
        nport=$(grep -E 'NODE_PORT=' "$REMNANODE_DIR/docker-compose.yml" 2>/dev/null | head -1 | sed -E 's/.*NODE_PORT=([0-9]+).*/\1/' | tr -d '[:space:]"'\''' || true)
    fi
    echo "${nport:-3000}"
}

get_saved_caddy_port() {
    local cport="${DETAIL_CADDY_PORT:-}"
    if [ -z "$cport" ] && [ -f "$CADDY_DIR/.env" ]; then
        cport=$(grep -E '^SELF_STEAL_PORT=' "$CADDY_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    if [ -z "$cport" ] && [ -f "/opt/caddy/.env" ]; then
        cport=$(grep -E '^SELF_STEAL_PORT=' "/opt/caddy/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    echo "${cport:-$DEFAULT_PORT}"
}

get_saved_caddy_domain() {
    local cdom="${DETAIL_CADDY_DOMAIN:-}"
    if [ -z "$cdom" ] && [ -f "$CADDY_DIR/.env" ]; then
        cdom=$(grep -E '^SELF_STEAL_DOMAIN=' "$CADDY_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    if [ -z "$cdom" ] && [ -f "/opt/caddy/.env" ]; then
        cdom=$(grep -E '^SELF_STEAL_DOMAIN=' "/opt/caddy/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    echo "$cdom"
}

spinner() {
    local pid=$1
    local msg="${2:-Выполнение...}"
    local -a frames=('|' '/' '-' '\')
    local i=0

    if [ "${NON_INTERACTIVE:-false}" = true ]; then
        wait "$pid" 2>/dev/null
        return $?
    fi

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${ORANGE}[%s]${NC} ${WHITE}%s${NC}" "${frames[$i]}" "$msg"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.12
    done
    printf "\r\033[K"
    wait "$pid" 2>/dev/null
    return $?
}

download_with_progress() {
    local url="$1"
    local output="$2"
    local msg="${3:-Скачивание...}"

    wget --timeout=60 --tries=5 --waitretry=2 "$url" -q -O "$output" &
    local pid=$!
    if spinner "$pid" "$msg"; then
        return 0
    fi
    return 1
}

prompt_choice() {
    local prompt="$1"
    local max="$2"
    local result_var="$3"
    local default="${4:-}"

    if [ "${NON_INTERACTIVE:-false}" = true ]; then
        printf -v "$result_var" '%s' "${default:-1}"
        return 0
    fi

    while true; do
        read -p "  ${ORANGE}>${NC} $prompt" -r _choice
        if [ -z "$_choice" ] && [ -n "$default" ]; then
            printf -v "$result_var" '%s' "$default"
            return 0
        fi
        if [[ "$_choice" =~ ^[0-9]+$ ]] && [ "$_choice" -ge 0 ] && [ "$_choice" -le "$max" ]; then
            printf -v "$result_var" '%s' "$_choice"
            return 0
        fi
        log_warning "Неверный выбор. Введите число от 0 до $max."
    done
}

prompt_yn() {
    local prompt="$1"
    local default="${2:-}"
    local config_val="${3:-}"

    if [ "${NON_INTERACTIVE:-false}" = true ]; then
        local val="${config_val:-$default}"
        if [[ "$val" =~ ^[Yy]$ ]]; then return 0; else return 1; fi
    fi

    while true; do
        read -p "  ${ORANGE}>${NC} $prompt" -r _answer
        _answer="${_answer:-$default}"
        if [[ "$_answer" =~ ^[Yy]$ ]]; then
            return 0
        elif [[ "$_answer" =~ ^[Nn]$ ]]; then
            return 1
        fi
        log_warning "Введите y или n."
    done
}

# ═══════════════════════════════════════════════════════════════════
#  Определение ОС и пакетный менеджер
# ═══════════════════════════════════════════════════════════════════
detect_os() {
    if [ -f /etc/os-release ]; then
        OS=$(awk -F= '/^NAME=/{print $2}' /etc/os-release | tr -d '"')
        if [[ "$OS" == "Amazon Linux"* ]]; then OS="Amazon"; fi
    elif [ -f /etc/lsb-release ]; then
        OS=$(grep -E '^DISTRIB_ID=' /etc/lsb-release | cut -d= -f2 | tr -d '"')
    elif [ -f /etc/redhat-release ]; then
        OS=$(awk '{print $1}' /etc/redhat-release)
    elif [ -f /etc/arch-release ]; then
        OS="Arch"
    else
        OS="Linux"
    fi
}

detect_arch() {
    local format="${1:-generic}"
    local arch
    arch=$(uname -m)

    case "$format" in
        xray)
            case "$arch" in
                x86_64) echo "64" ;;
                aarch64|arm64) echo "arm64-v8a" ;;
                armv7l|armv6l) echo "arm32-v7a" ;;
                *) log_error "Неподдерживаемая архитектура: $arch"; return 1 ;;
            esac
            ;;
        *)
            case "$arch" in
                x86_64) echo "amd64" ;;
                aarch64|arm64) echo "arm64" ;;
                armv7l|armv6l) echo "armv7" ;;
                *) log_error "Неподдерживаемая архитектура: $arch"; return 1 ;;
            esac
            ;;
    esac
}

detect_package_manager() {
    if [[ "$OS" == "Ubuntu"* ]] || [[ "$OS" == "Debian"* ]]; then
        PKG_MANAGER="apt-get"
    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "AlmaLinux"* ]] || [[ "$OS" == "Rocky"* ]] || [[ "$OS" == "Amazon"* ]]; then
        PKG_MANAGER="yum"
    elif [[ "$OS" == "Fedora"* ]]; then
        PKG_MANAGER="dnf"
    elif [[ "$OS" == "Arch"* ]]; then
        PKG_MANAGER="pacman"
    else
        PKG_MANAGER="apt-get"
    fi
}

_init_env() {
    check_root
    self_install
    if [ -z "${NODE_IP:-}" ]; then
        NODE_IP=$(get_server_ip)
    fi
    if [ -z "${OS:-}" ]; then
        detect_os
    fi
    if [ -z "${PKG_MANAGER:-}" ]; then
        detect_package_manager
    fi
}

is_dpkg_locked() {
    if pgrep -x 'dpkg' >/dev/null 2>&1 || \
       pgrep -x 'apt-get' >/dev/null 2>&1 || \
       pgrep -x 'apt' >/dev/null 2>&1 || \
       pgrep -f 'unattended-upgr' >/dev/null 2>&1; then
        return 0
    fi
    if command -v fuser >/dev/null 2>&1; then
        if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
           fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
           fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

wait_for_dpkg_lock() {
    local max_wait=180
    local waited=0
    if ! is_dpkg_locked; then return 0; fi
    log_warning "Ожидание освобождения пакетного менеджера APT..."
    while [ $waited -lt $max_wait ]; do
        if ! is_dpkg_locked; then
            if dpkg --configure -a >/dev/null 2>&1; then return 0; fi
        fi
        sleep 3
        waited=$((waited + 3))
    done
    return 1
}

ensure_package_manager_available() {
    if [[ "$PKG_MANAGER" != "apt-get" ]]; then return 0; fi
    local services_to_stop=("unattended-upgrades" "apt-daily.service" "apt-daily-upgrade.service")
    for svc in "${services_to_stop[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            systemctl stop "$svc" 2>/dev/null || true
        fi
    done
    if is_dpkg_locked; then
        if ! wait_for_dpkg_lock; then
            killall unattended-upgr apt-get apt 2>/dev/null || true
            rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock 2>/dev/null || true
            dpkg --configure -a >/dev/null 2>&1 || true
        fi
    fi
}

restore_auto_updates() {
    if [[ "${PKG_MANAGER:-}" != "apt-get" ]]; then return 0; fi
    systemctl start apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
}

install_package() {
    local package="$1"
    local install_log
    install_log=$(create_temp_file)
    local ok=false

    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        if is_dpkg_locked; then wait_for_dpkg_lock || true; fi
        if [ "${_APT_UPDATED:-}" != "true" ]; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq >"$install_log" 2>&1 || true
            _APT_UPDATED=true
        fi
        if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$package" >>"$install_log" 2>&1; then
            ok=true
        fi
    elif [[ "$PKG_MANAGER" == "yum" ]] || [[ "$PKG_MANAGER" == "dnf" ]]; then
        if $PKG_MANAGER install -y -q "$package" >"$install_log" 2>&1; then
            ok=true
        fi
    elif [[ "$PKG_MANAGER" == "pacman" ]]; then
        if pacman -S --noconfirm --quiet "$package" >"$install_log" 2>&1; then
            ok=true
        fi
    fi

    rm -f "$install_log"
    if [ "$ok" = true ]; then return 0; else return 1; fi
}

install_base_utilities() {
    log_info "Проверка и установка базовых системных утилит (curl, jq, openssl, ethtool)..."
    local -a required=("curl" "wget" "openssl" "tar" "jq" "ethtool" "iproute2" "ca-certificates")
    for pkg in "${required[@]}"; do
        local bin="$pkg"
        if [ "$pkg" = "iproute2" ]; then bin="ss"; fi
        if [ "$pkg" = "ca-certificates" ]; then bin="update-ca-certificates"; fi
        if ! command -v "$bin" >/dev/null 2>&1; then
            install_package "$pkg" >/dev/null 2>&1 || true
        fi
    done
}

check_disk_space() {
    local required_mb="${1:-500}"
    local target_dir="${2:-/opt}"
    mkdir -p "$target_dir" 2>/dev/null || true
    local available_mb
    available_mb=$(df -Pm "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$available_mb" ] && [ "$available_mb" -lt "$required_mb" ]; then
        log_error "Мало места на диске: ${available_mb} МБ (требуется >= ${required_mb} МБ)"
        return 1
    fi
    return 0
}

backup_existing_config() {
    local dir="$1"
    local backup_dir="${dir}.backup.$(date +%Y%m%d_%H%M%S)"
    if [ -d "$dir" ]; then
        mkdir -p "$backup_dir"
        for f in "$dir"/.env "$dir"/docker-compose.yml "$dir"/Caddyfile; do
            if [ -f "$f" ]; then cp -f "$f" "$backup_dir/" 2>/dev/null || true; fi
        done
        chmod 700 "$backup_dir"
        log_info "Бэкап сохранен: $backup_dir"
    fi
}

load_config_file() {
    local config_file="${1:-$CONFIG_FILE}"
    if [ -f "$config_file" ]; then
        log_info "Загрузка конфигурации из $config_file"
        local _allowed_vars="REMNAWAVE_API_URL REMNAWAVE_API_TOKEN NODE_NAME NODE_ADDRESS SELF_STEAL_DOMAIN SELF_STEAL_PORT CFG_SECRET_KEY CFG_NODE_PORT CFG_PANEL_IP CFG_INSTALL_XRAY CFG_DOMAIN CFG_CERT_TYPE CFG_CLOUDFLARE_TOKEN CFG_CADDY_PORT CFG_APPLY_NETWORK CFG_SETUP_UFW CFG_INSTALL_FAIL2BAN NON_INTERACTIVE"
        while IFS='=' read -r key value; do
            if [[ "$key" =~ ^[[:space:]]*# ]]; then continue; fi
            if [ -z "$key" ]; then continue; fi
            key=$(echo "$key" | xargs)
            value="${value#\"}" ; value="${value%\"}"
            value="${value#\'}" ; value="${value%\'}"
            if echo " $_allowed_vars " | grep -q " $key "; then
                printf -v "$key" '%s' "$value"
            fi
        done < "$config_file"
        NON_INTERACTIVE=true
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  МОДУЛЬ 1: ДИАГНОСТИКА НОДЫ (27 чеков, дашборд, findings, вердикт)
# ═══════════════════════════════════════════════════════════════════
run_diagnose() {
    _init_env
    local mode="${1:-full}"
    local pass_cnt=0 warn_cnt=0 fail_cnt=0

    cat > "$FINDINGS_FILE" << EOF
# Generated by node-mgr diagnose on $(date -u +'%Y-%m-%dT%H:%M:%SZ')
NEED_SYSCTL=0
NEED_LIMITS=0
NEED_RPS=0
NEED_NIC=0
NEED_MSS=0
NEED_IRQBALANCE=0
NEED_JOURNALD=0
NEED_ZRAM=0
NEED_UFW_FIX=0
NEED_F2B_FIX=0
EOF

    _mark_finding() {
        local key="$1"
        sed -i "s/^${key}=0/${key}=1/" "$FINDINGS_FILE" 2>/dev/null || true
    }

    _chk_ok()   { pass_cnt=$((pass_cnt + 1)); box_row "${GREEN}${BOLD}[ PASS ]${NC} $(printf '%-26s' "$1") ${SLATE}$2${NC}"; }
    _chk_warn() { warn_cnt=$((warn_cnt + 1)); box_row "${YELLOW}${BOLD}[ WARN ]${NC} $(printf '%-26s' "$1") ${YELLOW}$2${NC}"; }
    _chk_fail() { fail_cnt=$((fail_cnt + 1)); box_row "${RED}${BOLD}[ FAIL ]${NC} $(printf '%-26s' "$1") ${RED}$2${NC}"; }

    print_banner
    echo

    # ── Блок 1: Аппаратные ресурсы и ОС (Чеки 1-5) ─────────────────
    box_top "1/5 · СИСТЕМА И РЕСУРСЫ (ЧЕКИ 1–5)"

    local cores load1
    cores=$(nproc 2>/dev/null || echo 1)
    load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0.00")
    if awk "BEGIN {exit !($load1 < $cores * 1.5)}"; then
        _chk_ok "01. CPU & Load Average" "${cores} vCPU, LA 1m: ${load1}"
    else
        _chk_warn "01. CPU & Load Average" "Высокая нагрузка: LA ${load1} на ${cores} vCPU"
    fi

    local steal="0.0"
    if [ -r /proc/stat ]; then
        local s1 t1 s2 t2
        read -r _ u1 n1 sy1 id1 io1 ir1 so1 st1 _ < /proc/stat
        s1=${st1:-0}; t1=$((u1+n1+sy1+id1+io1+ir1+so1+s1))
        sleep 0.2
        read -r _ u2 n2 sy2 id2 io2 ir2 so2 st2 _ < /proc/stat
        s2=${st2:-0}; t2=$((u2+n2+sy2+id2+io2+ir2+so2+s2))
        local dt=$((t2 - t1)) ds=$((s2 - s1))
        if [ $dt -gt 0 ]; then
            steal=$(awk "BEGIN {printf \"%.1f\", ($ds * 100.0) / $dt}")
        fi
    fi
    if awk "BEGIN {exit !($steal < 5.0)}"; then
        _chk_ok "02. CPU Steal Time" "${steal}% (хост не перегружен)"
    elif awk "BEGIN {exit !($steal < 15.0)}"; then
        _chk_warn "02. CPU Steal Time" "${steal}% (заметен оверселлинг гипервизора)"
    else
        _chk_fail "02. CPU Steal Time" "${steal}% (критический Steal CPU у хостера!)"
    fi

    local ram_total ram_avail swap_total
    ram_total=$(free -m | awk '/^Mem:/ {print $2}')
    ram_avail=$(free -m | awk '/^Mem:/ {print $7}')
    swap_total=$(free -m | awk '/^Swap:/ {print $2}')
    if [ "${ram_avail:-0}" -ge 256 ]; then
        if [ "${swap_total:-0}" -gt 0 ]; then
            _chk_ok "03. Память RAM & Swap" "Доступно ${ram_avail}/${ram_total} МБ, Swap: ${swap_total} МБ"
        else
            _chk_warn "03. Память RAM & Swap" "RAM ${ram_avail}/${ram_total} МБ, Swap/Zram отсутствует"
            _mark_finding "NEED_ZRAM"
        fi
    else
        _chk_fail "03. Память RAM & Swap" "Критически мало свободной RAM: ${ram_avail} МБ"
        _mark_finding "NEED_ZRAM"
    fi

    local disk_mb inode_use
    disk_mb=$(df -Pm / | awk 'NR==2 {print $4}')
    inode_use=$(df -Pi / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    if [ "${disk_mb:-0}" -ge 1024 ] && [ "${inode_use:-0}" -lt 85 ]; then
        _chk_ok "04. Диск и Inodes (/)" "Свободно ${disk_mb} МБ, Inodes: ${inode_use}%"
    else
        _chk_warn "04. Диск и Inodes (/)" "Свободно ${disk_mb} МБ, Inodes: ${inode_use}%"
    fi

    local fs_max ulim_nofile
    fs_max=$(sysctl -n fs.file-max 2>/dev/null || echo 0)
    ulim_nofile=$(ulimit -n 2>/dev/null || echo 1024)
    if [ "$fs_max" -ge 1000000 ] && [ "$ulim_nofile" -ge 65535 ]; then
        _chk_ok "05. Лимиты дескрипторов" "fs.file-max=${fs_max}, ulimit -n=${ulim_nofile}"
    else
        _chk_warn "05. Лимиты дескрипторов" "fs.file-max=${fs_max}, ulimit=${ulim_nofile} (низкий лимит)"
        _mark_finding "NEED_LIMITS"
        _mark_finding "NEED_SYSCTL"
    fi
    box_bottom
    echo

    # ── Блок 2: Сетевой стек ядра sysctl (Чеки 6-13) ───────────────
    box_top "2/5 · СЕТЕВОЙ СТЕК ЯДРА И SYSCTL (ЧЕКИ 6–13)"

    local tcp_cc
    tcp_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "cubic")
    if [[ "$tcp_cc" =~ ^bbr ]]; then
        _chk_ok "06. TCP Congestion" "${tcp_cc} активен"
    else
        _chk_fail "06. TCP Congestion" "${tcp_cc} (требуется BBR / BBRv3)"
        _mark_finding "NEED_SYSCTL"
    fi

    local qdisc
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "pfifo_fast")
    if [[ "$qdisc" == "fq" ]] || [[ "$qdisc" == "fq_pie" ]] || [[ "$qdisc" == "cake" ]]; then
        _chk_ok "07. Дисциплина очереди" "default_qdisc = ${qdisc}"
    else
        _chk_warn "07. Дисциплина очереди" "default_qdisc = ${qdisc} (рекомендуется fq)"
        _mark_finding "NEED_SYSCTL"
    fi

    local rmem_max
    rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null || echo 0)
    if [ "$rmem_max" -ge 16777216 ]; then
        _chk_ok "08. Буферы сокетов BDP" "rmem_max = $((rmem_max / 1048576)) МБ"
    else
        _chk_warn "08. Буферы сокетов BDP" "rmem_max = $((rmem_max / 1024)) КБ (узкое окно)"
        _mark_finding "NEED_SYSCTL"
    fi

    local tfo ss_idle
    tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo 0)
    ss_idle=$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null || echo 1)
    if [ "$tfo" -ge 3 ] && [ "$ss_idle" -eq 0 ]; then
        _chk_ok "09. TFO & SlowStart Idle" "tcp_fastopen=${tfo}, slow_start_after_idle=0"
    else
        _chk_warn "09. TFO & SlowStart Idle" "fastopen=${tfo}, slow_start_after_idle=${ss_idle}"
        _mark_finding "NEED_SYSCTL"
    fi

    local tw_reuse port_range
    tw_reuse=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo 0)
    port_range=$(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null | tr '\t' ' ')
    if [ "$tw_reuse" -ge 1 ]; then
        _chk_ok "10. TIME_WAIT & Порты" "tw_reuse=${tw_reuse}, range: ${port_range}"
    else
        _chk_warn "10. TIME_WAIT & Порты" "tcp_tw_reuse=${tw_reuse} (риск исчерпания сокетов)"
        _mark_finding "NEED_SYSCTL"
    fi

    local somax syn_bl
    somax=$(sysctl -n net.core.somaxconn 2>/dev/null || echo 128)
    syn_bl=$(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null || echo 128)
    if [ "$somax" -ge 8192 ] && [ "$syn_bl" -ge 8192 ]; then
        _chk_ok "11. Очереди SYN/Accept" "somaxconn=${somax}, syn_backlog=${syn_bl}"
    else
        _chk_warn "11. Очереди SYN/Accept" "somaxconn=${somax}, syn_backlog=${syn_bl} (мало для пиков)"
        _mark_finding "NEED_SYSCTL"
    fi

    local mtu_p lowat
    mtu_p=$(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null || echo 0)
    lowat=$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null || echo 4294967295)
    if [ "$mtu_p" -ge 1 ] && [ "$lowat" -le 131072 ]; then
        _chk_ok "12. MTU Probing & Lowat" "mtu_probing=${mtu_p}, notsent_lowat=${lowat}"
    else
        _chk_warn "12. MTU Probing & Lowat" "mtu_probing=${mtu_p}, notsent_lowat не ограничен"
        _mark_finding "NEED_SYSCTL"
    fi

    local ct_max ct_cnt
    ct_max=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo 0)
    ct_cnt=$(sysctl -n net.netfilter.nf_conntrack_count 2>/dev/null || echo 0)
    if [ "$ct_max" -eq 0 ] || [ "$ct_max" -ge 262144 ]; then
        _chk_ok "13. Таблица nf_conntrack" "Активно: ${ct_cnt} / Лимит: ${ct_max:-модуль не загружен}"
    else
        _chk_warn "13. Таблица nf_conntrack" "Лимит мал: ${ct_cnt}/${ct_max}"
        _mark_finding "NEED_SYSCTL"
    fi
    box_bottom
    echo

    # ── Блок 3: Сетевой интерфейс, RPS, NIC, MSS, Сервисы (14-18) ──
    box_top "3/5 · СЕТЕВАЯ КАРТА, RPS, MSS И СИСТЕМНЫЕ СЛУЖБЫ (ЧЕКИ 14–18)"
    local iface
    iface=$(detect_default_iface)

    local rps_val=""
    if [ -n "$iface" ] && [ -r "/sys/class/net/${iface}/queues/rx-0/rps_cpus" ]; then
        rps_val=$(tr -d '0,\n ' < "/sys/class/net/${iface}/queues/rx-0/rps_cpus" 2>/dev/null || true)
    fi
    if [ "$cores" -le 1 ] || [ -n "$rps_val" ]; then
        _chk_ok "14. Балансировка RPS/RFS" "Активна на интерфейсе ${iface:-?}"
    else
        _chk_warn "14. Балансировка RPS/RFS" "RPS выключен на ${iface:-eth0} (сеть на 1 ядре)"
        _mark_finding "NEED_RPS"
    fi

    local txq="0"
    if [ -n "$iface" ] && [ -r "/sys/class/net/${iface}/tx_queue_len" ]; then
        txq=$(cat "/sys/class/net/${iface}/tx_queue_len" 2>/dev/null || echo 0)
    fi
    if [ "${txq:-0}" -ge 5000 ]; then
        _chk_ok "15. Очередь NIC (txqueuelen)" "${iface}: txqueuelen = ${txq}"
    else
        _chk_warn "15. Очередь NIC (txqueuelen)" "${iface:-eth0}: txqueuelen = ${txq} (рекомендуется >= 5000)"
        _mark_finding "NEED_NIC"
    fi

    if command -v iptables >/dev/null 2>&1 && iptables -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
        _chk_ok "16. TCPMSS Clamp to PMTU" "Правило mangle OUTPUT активно"
    else
        _chk_warn "16. TCPMSS Clamp to PMTU" "Не активно (возможны зависания TLS при узком MTU)"
        _mark_finding "NEED_MSS"
    fi

    if [ "$cores" -le 1 ] || systemctl is-active --quiet irqbalance 2>/dev/null; then
        _chk_ok "17. Служба irqbalance" "Активна"
    else
        _chk_warn "17. Служба irqbalance" "Не запущена (прерывания NIC не распределяются)"
        _mark_finding "NEED_IRQBALANCE"
    fi

    if [ -f "/etc/systemd/journald.conf.d/${ND_DROPIN_PREFIX}.conf" ] || grep -Eq '^[[:space:]]*SystemMaxUse=' /etc/systemd/journald.conf 2>/dev/null; then
        _chk_ok "18. Журнал systemd-journald" "Размер логов ограничен"
    else
        _chk_warn "18. Журнал systemd-journald" "SystemMaxUse не задан (логи могут занять диск)"
        _mark_finding "NEED_JOURNALD"
    fi
    box_bottom
    echo

    # ── Блок 4: Контейнеры RemnawaveNode и Caddy Selfsteal (19-23) ─
    box_top "4/5 · DOCKER, REMNANODE И CADDY SELFSTEAL (ЧЕКИ 19–23)"
    local node_port caddy_port caddy_domain
    node_port=$(get_saved_node_port)
    caddy_port=$(get_saved_caddy_port)
    caddy_domain=$(get_saved_caddy_domain)
    local ss_listening
    ss_listening=$(ss -tln 2>/dev/null || true)

    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        _chk_ok "19. Служба Docker Engine" "Работает ($(docker --version | awk '{print $3}' | tr -d ','))"
    else
        _chk_fail "19. Служба Docker Engine" "Docker не установлен или не запущен"
    fi

    if is_container_running "remnanode"; then
        if grep -qE ":${node_port}[[:space:]]" <<< "$ss_listening"; then
            _chk_ok "20. Контейнер RemnawaveNode" "Запущен, слушает порт ${node_port}/tcp"
        else
            _chk_warn "20. Контейнер RemnawaveNode" "Контейнер Up, но порт ${node_port}/tcp не отвечает"
        fi
    else
        _chk_fail "20. Контейнер RemnawaveNode" "Не установлен или остановлен"
    fi

    if is_caddy_running; then
        _chk_ok "21. Контейнер Caddy Selfsteal" "Запущен (домен: ${caddy_domain:-?})"
    else
        _chk_fail "21. Контейнер Caddy Selfsteal" "Не установлен или остановлен"
    fi

    if awk '{print $4}' <<< "$ss_listening" | grep -q "^127\.0\.0\.1:${caddy_port}$"; then
        _chk_ok "22. Изоляция Selfsteal сокета" "Слушает строго на 127.0.0.1:${caddy_port}"
    elif grep -qE ":${caddy_port}[[:space:]]" <<< "$ss_listening"; then
        _chk_fail "22. Изоляция Selfsteal сокета" "УТЕЧКА: порт ${caddy_port} слушает публично!"
    else
        _chk_warn "22. Изоляция Selfsteal сокета" "Порт 127.0.0.1:${caddy_port} не прослушивается"
    fi

    if is_caddy_running && [ -n "$caddy_domain" ]; then
        local clean_dom="${caddy_domain#\*.}"
        local active_cname="$CADDY_CONTAINER_NAME"
        if ! is_container_running "$active_cname"; then active_cname="caddy-selfsteal"; fi
        local cert_end=""
        cert_end=$(docker exec "$active_cname" sh -c "find /data/caddy/certificates -type f -name '*${clean_dom}*.crt' 2>/dev/null | head -1" 2>/dev/null || true)
        if [ -n "$cert_end" ]; then
            _chk_ok "23. TLS-сертификат маскировки" "Выпущен (${clean_dom})"
        else
            _chk_warn "23. TLS-сертификат маскировки" "Сертификат для ${clean_dom} еще не получен"
        fi
    else
        _chk_warn "23. TLS-сертификат маскировки" "Контейнер Caddy или домен не активен"
    fi
    box_bottom
    echo

    # ── Блок 5: Периметр безопасности и связность (Чеки 24-27) ────
    box_top "5/5 · ЗАЩИТА ПЕРИМЕТРА И СВЯЗНОСТЬ (ЧЕКИ 24–27)"
    local panel_ip ufw_out=""
    panel_ip=$(get_saved_panel_ip)
    if command -v ufw >/dev/null 2>&1; then
        ufw_out=$(ufw status 2>/dev/null || true)
    fi

    if grep -qi "Status: active" <<< "$ufw_out"; then
        _chk_ok "24. Межсетевой экран UFW" "Активен (политика deny incoming)"
    else
        _chk_fail "24. Межсетевой экран UFW" "UFW выключен!"
        _mark_finding "NEED_UFW_FIX"
    fi

    if grep -qi "Status: active" <<< "$ufw_out"; then
        if grep -E "^${node_port}(/tcp)?[[:space:]]+ALLOW[[:space:]]+Anywhere" <<< "$ufw_out" >/dev/null 2>&1; then
            _chk_fail "25. ACL порта RemnaNode" "УЯЗВИМОСТЬ: порт ${node_port} открыт всему миру (Anywhere)!"
            _mark_finding "NEED_UFW_FIX"
        elif [ -n "$panel_ip" ] && grep -F "${node_port}" <<< "$ufw_out" | grep -F "${panel_ip}" >/dev/null 2>&1; then
            _chk_ok "25. ACL порта RemnaNode" "Порт ${node_port}/tcp открыт ТОЛЬКО для ${panel_ip}"
        else
            _chk_warn "25. ACL порта RemnaNode" "Правило для панели (${panel_ip:-не задан}) не найдено в UFW"
            _mark_finding "NEED_UFW_FIX"
        fi
    else
        _chk_fail "25. ACL порта RemnaNode" "UFW неактивен, порт ${node_port} не защищен"
        _mark_finding "NEED_UFW_FIX"
    fi

    if command -v fail2ban-client >/dev/null 2>&1 && systemctl is-active --quiet fail2ban && fail2ban-client ping >/dev/null 2>&1; then
        local jails
        jails=$(fail2ban-client status 2>/dev/null | awk -F'Jail list:' '/Jail list:/ {gsub(/^[ \t]+/, "", $2); print $2}')
        _chk_ok "26. Защита Fail2ban" "Активен (Jails: ${jails:-нет})"
    else
        _chk_fail "26. Защита Fail2ban" "Fail2ban не запущен или аварийно остановился"
        _mark_finding "NEED_F2B_FIX"
    fi

    if [ "$mode" != "--no-net" ] && [ "$mode" != "-q" ]; then
        if curl -fsSIL --connect-timeout 4 --max-time 6 https://1.1.1.1 >/dev/null 2>&1; then
            _chk_ok "27. Внешняя связность TLS" "HTTPS до 1.1.1.1 работает штатно"
        else
            _chk_fail "27. Внешняя связность TLS" "Сбой исходящего HTTPS-соединения"
        fi
    else
        _chk_ok "27. Внешняя связность TLS" "Пропущено (${mode})"
    fi
    box_bottom
    echo

    box_top "ВЕРДИКТ ДИАГНОСТИКИ (27 ЧЕКОВ)"
    box_row "Успешно: ${GREEN}${BOLD}${pass_cnt}${NC}   |   Предупреждений: ${YELLOW}${BOLD}${warn_cnt}${NC}   |   Ошибок: ${RED}${BOLD}${fail_cnt}${NC}"
    if [ $fail_cnt -eq 0 ] && [ $warn_cnt -eq 0 ]; then
        box_row "${GREEN}${BOLD}Идеальное состояние! Узел полностью оптимизирован и защищен.${NC}"
    else
        box_row "${SLATE}Для авто-исправления находок запустите: ${ORANGE}${BOLD}node-mgr optimize --from-findings${NC}"
        box_row "${SLATE}Для полного профиля оптимизации:       ${ORANGE}${BOLD}node-mgr optimize --all${NC}"
    fi
    box_bottom
    echo
}

# ═══════════════════════════════════════════════════════════════════
#  МОДУЛЬ 2: ОПТИМИЗАЦИЯ УЗЛА (optimize / rollback / bbr3)
# ═══════════════════════════════════════════════════════════════════
_log_fix() {
    echo "$(date -u +'%Y-%m-%d %H:%M UTC') · $*" >> "$FIX_LOG"
}

opt_sysctl() {
    log_info "Применение адаптивного Highload-профиля sysctl и nf_conntrack..."
    local sysctl_file="/etc/sysctl.d/${ND_DROPIN_PREFIX}-sysctl.conf"
    rm -f /etc/sysctl.d/99-bbr.conf /etc/sysctl.d/99-xray-highload.conf /etc/sysctl.d/99-remnawave-tuning.conf 2>/dev/null || true

    local total_ram_mb rmem_max conntrack_max conntrack_buckets profile_tier
    total_ram_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 2048)

    if [ "$total_ram_mb" -lt 1800 ]; then
        profile_tier="Lite (1GB RAM)"
        rmem_max=16777216
        conntrack_max=262144
        conntrack_buckets=65536
    elif [ "$total_ram_mb" -lt 6000 ]; then
        profile_tier="Standard (2-4GB RAM)"
        rmem_max=33554432
        conntrack_max=524288
        conntrack_buckets=131072
    else
        profile_tier="Highload (8GB+ RAM)"
        rmem_max=67108864
        conntrack_max=1048576
        conntrack_buckets=262144
    fi

    local BBR_ALGO="bbr"
    if grep -q "bbr3" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        BBR_ALGO="bbr3"
    elif grep -q "bbr2" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || modprobe tcp_bbr2 2>/dev/null; then
        BBR_ALGO="bbr2"
    else
        modprobe tcp_bbr 2>/dev/null || true
        BBR_ALGO="bbr"
    fi

    modprobe nf_conntrack 2>/dev/null || true
    mkdir -p /etc/modules-load.d /etc/modprobe.d
    echo "nf_conntrack" > "/etc/modules-load.d/${ND_DROPIN_PREFIX}.conf"
    echo "options nf_conntrack hashsize=${conntrack_buckets}" > "/etc/modprobe.d/${ND_DROPIN_PREFIX}-conntrack.conf"
    if [ -w /sys/module/nf_conntrack/parameters/hashsize ]; then
        echo "$conntrack_buckets" > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null || true
    fi

    local reserved_node_port reserved_caddy_port
    reserved_node_port=$(get_saved_node_port)
    reserved_caddy_port=$(get_saved_caddy_port)

    cat > "$sysctl_file" << EOF
# LissVPN Node Diagnostic & Highload Kernel Profile (${profile_tier})
fs.file-max = 2097152
fs.nr_open = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 0
net.ipv4.ip_forward = 1

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = ${BBR_ALGO}
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384

net.core.rmem_max = ${rmem_max}
net.core.wmem_max = ${rmem_max}
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 131072 ${rmem_max}
net.ipv4.tcp_wmem = 4096 131072 ${rmem_max}
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

net.core.netdev_max_backlog = 65536
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 8000
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2

net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.ip_local_reserved_ports = ${reserved_node_port},${reserved_caddy_port}
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_max_orphans = 65536
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 3

-net.netfilter.nf_conntrack_max = ${conntrack_max}
-net.netfilter.nf_conntrack_buckets = ${conntrack_buckets}
-net.netfilter.nf_conntrack_tcp_timeout_established = 1800
-net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
-net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
-net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
-net.netfilter.nf_conntrack_udp_timeout = 15
-net.netfilter.nf_conntrack_udp_timeout_stream = 60

net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
vm.swappiness = 10
vm.overcommit_memory = 1
EOF

    sysctl --system >/dev/null 2>&1 || true
    _log_fix "sysctl profile applied (${profile_tier}, ${BBR_ALGO}, conntrack=${conntrack_max})"
    log_success "Профиль sysctl применен (${profile_tier}, ${BBR_ALGO})"
}

opt_limits() {
    log_info "Настройка системных лимитов дескрипторов (PAM & Systemd)..."
    mkdir -p /etc/security/limits.d /etc/systemd/system.conf.d
    cat > "/etc/security/limits.d/${ND_DROPIN_PREFIX}-limits.conf" << 'EOF'
*    soft nofile 1048576
*    hard nofile 1048576
*    soft nproc  65535
*    hard nproc  65535
root soft nofile 1048576
root hard nofile 1048576
root soft nproc  65535
root hard nproc  65535
EOF

    cat > "/etc/systemd/system.conf.d/${ND_DROPIN_PREFIX}-limits.conf" << 'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65535
EOF
    ulimit -n 1048576 2>/dev/null || true
    systemctl daemon-reexec 2>/dev/null || true
    _log_fix "FD limits set to 1048576"
    log_success "Лимиты файловых дескрипторов установлены (1048576)"
}

opt_rps() {
    log_info "Настройка Receive Packet Steering (RPS/RFS) по всем ядрам CPU..."
    cat > /usr/local/sbin/node-mgr-rps << 'EOF'
#!/usr/bin/env bash
cores=$(nproc 2>/dev/null || echo 1)
if [ "$cores" -le 1 ]; then exit 0; fi

full_groups=$(( cores / 32 ))
rem_bits=$(( cores % 32 ))
mask=""
if [ "$rem_bits" -gt 0 ]; then
    mask=$(printf '%x' $(( (1 << rem_bits) - 1 )))
fi
for ((g=0; g<full_groups; g++)); do
    if [ -n "$mask" ]; then
        mask="${mask},ffffffff"
    else
        mask="ffffffff"
    fi
done

entries=32768
sysctl -w net.core.rps_sock_flow_entries=$entries >/dev/null 2>&1 || true
for iface_dir in /sys/class/net/*; do
    iface=$(basename "$iface_dir")
    if [ "$iface" = "lo" ]; then continue; fi
    rx_queues=( "${iface_dir}/queues/rx-"* )
    if [ ! -d "${rx_queues[0]}" ]; then continue; fi
    rx_cnt=${#rx_queues[@]}
    flow_cnt=$(( entries / rx_cnt ))
    for q in "${rx_queues[@]}"; do
        echo "$mask" > "$q/rps_cpus" 2>/dev/null || true
        echo "$flow_cnt" > "$q/rps_flow_cnt" 2>/dev/null || true
    done
done
EOF
    chmod 755 /usr/local/sbin/node-mgr-rps
    /usr/local/sbin/node-mgr-rps || true

    cat > /etc/systemd/system/node-diagnostic-rps.service << 'EOF'
[Unit]
Description=LissVPN RPS/RFS Multi-Queue Packet Steering
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/node-mgr-rps
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node-diagnostic-rps.service >/dev/null 2>&1 || true
    _log_fix "RPS/RFS packet steering enabled"
    log_success "RPS/RFS распределение пакетов по ядрам активировано"
}

opt_nic() {
    log_info "Тюнинг сетевой карты (GRO/GSO/TSO offloads, txqueuelen 10000 & TCPMSS)..."
    if ! command -v ethtool >/dev/null 2>&1; then
        install_package ethtool >/dev/null 2>&1 || true
    fi
    cat > /usr/local/sbin/node-mgr-nic << 'EOF'
#!/usr/bin/env bash
iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
if [ -n "$iface" ]; then
    ip link set dev "$iface" txqueuelen 10000 2>/dev/null || true
    if command -v ethtool >/dev/null 2>&1; then
        ethtool -K "$iface" gro on gso on tso on 2>/dev/null || true
        ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
    fi
fi
if command -v iptables >/dev/null 2>&1; then
    if ! iptables -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
        iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    fi
    if ! iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
        iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    fi
fi
EOF
    chmod 755 /usr/local/sbin/node-mgr-nic
    /usr/local/sbin/node-mgr-nic || true

    cat > /etc/systemd/system/node-diagnostic-nic.service << 'EOF'
[Unit]
Description=LissVPN NIC Offloads, Queue & TCPMSS Clamp
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/node-mgr-nic
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node-diagnostic-nic.service >/dev/null 2>&1 || true
    _log_fix "NIC offloads (GRO/GSO/TSO), txqueuelen=10000 & TCPMSS applied"
    log_success "Аппаратные оффлоады NIC, txqueuelen=10000 и TCPMSS настроены"
}

opt_mss() {
    log_info "Включение iptables TCPMSS clamp to PMTU..."
    if command -v iptables >/dev/null 2>&1; then
        if ! iptables -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
            iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
        fi
        if ! iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
            iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
        fi
        _log_fix "iptables TCPMSS clamp-mss-to-pmtu enabled"
        log_success "Правило TCPMSS clamp-mss-to-pmtu активно"
    fi
}

opt_irqbalance() {
    local cores
    cores=$(nproc 2>/dev/null || echo 1)
    if [ "$cores" -le 1 ]; then
        return 0
    fi
    log_info "Установка и запуск службы irqbalance..."
    if ! command -v irqbalance >/dev/null 2>&1; then
        install_package irqbalance >/dev/null 2>&1 || true
    fi
    systemctl enable --now irqbalance >/dev/null 2>&1 || true
    _log_fix "irqbalance enabled"
    log_success "Служба irqbalance активна"
}

opt_journald() {
    log_info "Ограничение размера системного журнала systemd-journald (200M)..."
    mkdir -p /etc/systemd/journald.conf.d
    cat > "/etc/systemd/journald.conf.d/${ND_DROPIN_PREFIX}.conf" << 'EOF'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=100M
MaxRetentionSec=14day
Compress=yes
EOF
    systemctl restart systemd-journald >/dev/null 2>&1 || true
    journalctl --vacuum-size=200M >/dev/null 2>&1 || true
    _log_fix "journald capped at 200M"
    log_success "Журнал systemd-journald ограничен до 200 МБ"
}

opt_zram() {
    log_info "Настройка сжатого swap в памяти (Zram)..."
    if ! modprobe zram 2>/dev/null; then
        log_warning "Модуль ядра zram недоступен на данной виртуализации"
        return 0
    fi
    cat > /usr/local/sbin/node-mgr-zram << 'EOF'
#!/usr/bin/env bash
if ! modprobe zram num_devices=1 2>/dev/null; then exit 0; fi
swapoff /dev/zram0 2>/dev/null || true
echo 1 > /sys/block/zram0/reset 2>/dev/null || true
echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || true
ram_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
zram_bytes=$(( (ram_kb / 2) * 1024 ))
echo "$zram_bytes" > /sys/block/zram0/disksize
mkswap /dev/zram0 >/dev/null 2>&1
swapon -p 100 /dev/zram0
EOF
    chmod 755 /usr/local/sbin/node-mgr-zram
    /usr/local/sbin/node-mgr-zram || true

    cat > /etc/systemd/system/node-diagnostic-zram.service << 'EOF'
[Unit]
Description=LissVPN Zram Compressed Swap
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/node-mgr-zram
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node-diagnostic-zram.service >/dev/null 2>&1 || true
    _log_fix "zram-swap enabled (50% RAM)"
    log_success "Zram-swap успешно активирован"
}

run_optimize() {
    _init_env
    local flag="${1:---all}"
    print_header "ОПТИМИЗАЦИЯ И ТЮНИНГ УЗЛА (${flag})"

    case "$flag" in
        --all)
            opt_sysctl
            opt_limits
            opt_rps
            opt_nic
            opt_mss
            opt_irqbalance
            opt_journald
            STATUS_NETWORK="применены"
            ;;
        --from-findings)
            if [ ! -f "$FINDINGS_FILE" ]; then
                log_info "Файл находок не найден, запускаем предварительную диагностику..."
                run_diagnose "--no-net"
            fi
            if grep -q "^NEED_SYSCTL=1" "$FINDINGS_FILE" 2>/dev/null; then opt_sysctl; fi
            if grep -q "^NEED_LIMITS=1" "$FINDINGS_FILE" 2>/dev/null; then opt_limits; fi
            if grep -q "^NEED_RPS=1" "$FINDINGS_FILE" 2>/dev/null; then opt_rps; fi
            if grep -q "^NEED_NIC=1" "$FINDINGS_FILE" 2>/dev/null; then opt_nic; fi
            if grep -q "^NEED_MSS=1" "$FINDINGS_FILE" 2>/dev/null; then opt_mss; fi
            if grep -q "^NEED_IRQBALANCE=1" "$FINDINGS_FILE" 2>/dev/null; then opt_irqbalance; fi
            if grep -q "^NEED_JOURNALD=1" "$FINDINGS_FILE" 2>/dev/null; then opt_journald; fi
            if grep -q "^NEED_ZRAM=1" "$FINDINGS_FILE" 2>/dev/null; then opt_zram; fi
            if grep -q "^NEED_UFW_FIX=1" "$FINDINGS_FILE" 2>/dev/null; then setup_ufw; fi
            if grep -q "^NEED_F2B_FIX=1" "$FINDINGS_FILE" 2>/dev/null; then install_fail2ban; fi
            ;;
        --zram)       opt_zram ;;
        --sysctl)     opt_sysctl ;;
        --limits)     opt_limits ;;
        --rps)        opt_rps ;;
        --nic)        opt_nic ;;
        --mss)        opt_mss ;;
        --irqbalance) opt_irqbalance ;;
        --journald)   opt_journald ;;
        *)
            opt_sysctl
            opt_limits
            opt_rps
            opt_nic
            opt_mss
            opt_irqbalance
            opt_journald
            ;;
    esac
    echo
    log_success "Оптимизация завершена."
}

run_rollback() {
    _init_env
    print_header "ОТКАТ НАЛОЖЕННЫХ ОПТИМИЗАЦИЙ (ROLLBACK)"

    rm -f "/etc/sysctl.d/${ND_DROPIN_PREFIX}-sysctl.conf" \
          "/etc/security/limits.d/${ND_DROPIN_PREFIX}-limits.conf" \
          "/etc/systemd/system.conf.d/${ND_DROPIN_PREFIX}-limits.conf" \
          "/etc/modules-load.d/${ND_DROPIN_PREFIX}.conf" \
          "/etc/modprobe.d/${ND_DROPIN_PREFIX}-conntrack.conf" \
          "/etc/systemd/journald.conf.d/${ND_DROPIN_PREFIX}.conf" 2>/dev/null || true

    for svc in node-diagnostic-rps node-diagnostic-nic node-diagnostic-zram; do
        systemctl disable --now "${svc}.service" 2>/dev/null || true
        rm -f "/etc/systemd/system/${svc}.service"
    done
    rm -f /usr/local/sbin/node-mgr-rps /usr/local/sbin/node-mgr-nic /usr/local/sbin/node-mgr-zram

    if command -v iptables >/dev/null 2>&1; then
        iptables -t mangle -D OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
        iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    fi

    sysctl --system >/dev/null 2>&1 || true
    systemctl daemon-reload
    _log_fix "rollback executed"
    log_success "Все кастомные оптимизации сняты, восстановлены параметры ОС по умолчанию."
}

run_bbr3_xanmod() {
    _init_env
    print_header "УСТАНОВКА ЯДРА XANMOD (BBRv3)"

    if [ "$(uname -m)" != "x86_64" ] || [[ "$PKG_MANAGER" != "apt-get" ]]; then
        log_error "Ядро XanMod поддерживается только на Debian/Ubuntu x86_64"
        return 1
    fi

    local xanmod_level="x64v1"
    if grep -q "avx512" /proc/cpuinfo 2>/dev/null; then
        xanmod_level="x64v4"
    elif grep -q "avx2" /proc/cpuinfo 2>/dev/null; then
        xanmod_level="x64v3"
    elif grep -q "sse4_2" /proc/cpuinfo 2>/dev/null; then
        xanmod_level="x64v2"
    fi
    log_info "Текущее ядро: $(uname -r) | Выбран профиль CPU: ${ORANGE}${xanmod_level}${NC}"

    if ! prompt_yn "Установить пакет linux-xanmod-${xanmod_level} (потребуется перезагрузка)? (y/n): " "y"; then
        return 0
    fi

    if ! command -v gpg >/dev/null 2>&1; then install_package gnupg; fi
    local xanmod_key="/usr/share/keyrings/xanmod-archive-keyring.gpg"
    curl -fsSL https://dl.xanmod.org/archive.key | gpg --dearmor --yes -o "$xanmod_key"
    echo "deb [signed-by=$xanmod_key] http://deb.xanmod.org releases main" > /etc/apt/sources.list.d/xanmod-release.list
    apt-get update -qq >/dev/null 2>&1

    log_info "Установка linux-xanmod-${xanmod_level}..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "linux-xanmod-${xanmod_level}"; then
        _log_fix "XanMod kernel (${xanmod_level}) installed"
        log_success "Ядро XanMod (${xanmod_level}) успешно установлено!"
        log_warning "Выполните 'reboot' в удобное время для загрузки с ядром BBRv3."
    else
        log_error "Не удалось установить пакет ядра XanMod"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  МОДУЛЬ 3: DOCKER, CADDY (/opt/selfsteel), REMNAWAVE API & REMNANODE
# ═══════════════════════════════════════════════════════════════════
install_docker() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        log_success "Docker Engine уже установлен и работает"
        return 0
    fi

    if [[ "$PKG_MANAGER" == "apt-get" ]]; then wait_for_dpkg_lock || true; fi

    log_info "Установка официального Docker Engine и Docker Compose v2..."
    local docker_install_log docker_script
    docker_install_log=$(create_temp_file)
    docker_script=$(create_temp_file)

    if ! curl -fsSL https://get.docker.com -o "$docker_script" 2>/dev/null; then
        return 1
    fi
    sh "$docker_script" >"$docker_install_log" 2>&1 &
    spinner $! "Установка Docker Engine..."

    systemctl enable --now docker >/dev/null 2>&1 || true
    sleep 2
    if docker info >/dev/null 2>&1; then return 0; fi
    return 1
}

check_docker_compose() {
    local retries=0
    while [ $retries -lt 5 ]; do
        if docker compose version >/dev/null 2>&1; then return 0; fi
        sleep 2
        retries=$((retries + 1))
    done
    return 1
}

check_existing_remnanode() {
    if [ -d "$REMNANODE_DIR" ] && [ -f "$REMNANODE_DIR/docker-compose.yml" ]; then
        return 0
    fi
    return 1
}

check_existing_caddy() {
    if [ -d "$CADDY_DIR" ] && [ -f "$CADDY_DIR/docker-compose.yml" ]; then
        return 0
    fi
    return 1
}

setup_logrotate() {
    if ! command -v logrotate >/dev/null 2>&1; then
        install_package logrotate 2>/dev/null || true
    fi
    if command -v logrotate >/dev/null 2>&1; then
        cat > /etc/logrotate.d/remnanode << 'EOF'
/var/log/remnanode/*.log {
    size 50M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
EOF
    fi
}

install_xray_core() {
    log_info "Скачивание свежего релиза Xray-core с GitHub..."
    local ARCH
    ARCH=$(detect_arch xray) || return 1
    if ! command -v unzip >/dev/null 2>&1; then
        install_package unzip || return 1
    fi

    local api_response latest_release
    api_response=$(curl -s --connect-timeout 10 --max-time 25 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null) || true
    latest_release=$(echo "$api_response" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    if [ -z "$latest_release" ]; then return 1; fi

    local xray_filename="Xray-linux-$ARCH.zip"
    mkdir -p "$REMNANODE_DATA_DIR"
    if ! download_with_progress "https://github.com/XTLS/Xray-core/releases/download/${latest_release}/${xray_filename}" "${REMNANODE_DATA_DIR}/${xray_filename}" "Загрузка Xray-core ${latest_release}..."; then
        return 1
    fi

    unzip -o "${REMNANODE_DATA_DIR}/${xray_filename}" -d "$REMNANODE_DATA_DIR" >/dev/null 2>&1
    rm -f "${REMNANODE_DATA_DIR}/${xray_filename}"
    chmod +x "$REMNANODE_DATA_DIR/xray"
    log_success "Xray-core (${latest_release}) установлен в ${REMNANODE_DATA_DIR}/xray"
    return 0
}

# Генерация пары ключей X25519 (Private / Public) для Reality
generate_x25519_keypair() {
    local out=""
    if [ -x "$REMNANODE_DATA_DIR/xray" ]; then
        out=$("$REMNANODE_DATA_DIR/xray" x25519 2>/dev/null || true)
    fi
    if [ -z "$out" ] && command -v docker >/dev/null 2>&1; then
        out=$(docker run --rm ghcr.io/xtls/xray-core:latest x25519 2>/dev/null || true)
    fi
    local priv pub
    priv=$(echo "$out" | awk -F': ' '/Private key|PrivateKey/ {print $2; exit}' | tr -d '[:space:]')
    pub=$(echo "$out" | awk -F': ' '/Public key|PublicKey|Password/ {print $2; exit}' | tr -d '[:space:]')

    if [ -z "$priv" ] || [ -z "$pub" ]; then
        # Fallback генерация через openssl x25519
        local pem
        pem=$(openssl genpkey -algorithm X25519 2>/dev/null || true)
        if [ -n "$pem" ]; then
            priv=$(echo "$pem" | openssl pkey -outform DER 2>/dev/null | tail -c 32 | base64 | tr '+/' '-_' | tr -d '=')
            pub=$(echo "$pem" | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 | base64 | tr '+/' '-_' | tr -d '=')
        fi
    fi
    echo "${priv}:${pub}"
}

# ── Шаблоны маскировки в /opt/html ────────────────────────────────
TEMPLATES=(
    "10gag:Сайт мемов (10gag)"
    "503-1:Техническая страница 503 (v1)"
    "503-2:Техническая страница 503 (v2)"
    "convertit:Конвертер документов (Convertit)"
    "converter:Студия медиа-конвертации"
    "downloader:Загрузчик файлов"
    "filecloud:Облачное хранилище (FileCloud)"
    "games-site:Игровой ретро-портал"
    "modmanager:Менеджер модификаций"
    "speedtest:Измеритель скорости сети"
    "YouTube:Видео-шлюз с проверкой"
)

inject_antifingerprint_hash() {
    local target_html="$CADDY_HTML_DIR/index.html"
    if [ -f "$target_html" ]; then
        local fp_hash
        fp_hash=$(openssl rand -hex 6 2>/dev/null || echo "8a4f1c9e2b01")
        sed -i "s/<html/<html data-edge-rev=\"${fp_hash}\"/I" "$target_html" 2>/dev/null || true
        echo "<!-- edge-node-signature: ${fp_hash} -->" >> "$target_html"
        log_success "Внедрена уникальная anti-fingerprint сигнатура: ${fp_hash}"
    fi
}

create_default_fallback_html() {
    mkdir -p "$CADDY_HTML_DIR"
    cat > "$CADDY_HTML_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Edge AST Schema Gateway</title>
<style>body{background:#151419;color:#fbfbfb;font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}.box{border:1px solid #2b2933;padding:2rem 2.5rem;border-radius:10px;max-width:460px;text-align:center}.tag{color:#F56E0F;font-family:monospace;font-size:.85rem;margin-top:1rem}</style>
</head>
<body><div class="box"><h3>Edge Gateway Ready</h3><p>Deterministic payload inspection endpoint is active.</p><div class="tag">status: operational</div></div></body>
</html>
EOF
    inject_antifingerprint_hash
}

download_template() {
    local template_folder="$1"
    local template_label="${2:-$1}"
    log_info "Установка шаблона маскировки в ${CADDY_HTML_DIR}: ${template_label}..."

    mkdir -p "$CADDY_HTML_DIR"
    find "${CADDY_HTML_DIR:?}" -mindepth 1 -delete 2>/dev/null || true

    local base_url="https://raw.githubusercontent.com/Case211/remnanode-install/main/sni-templates/$template_folder"
    if curl -fsSL --connect-timeout 8 "$base_url/index.html" -o "$CADDY_HTML_DIR/index.html" 2>/dev/null; then
        curl -fsSL --connect-timeout 5 "$base_url/favicon.ico" -o "$CADDY_HTML_DIR/favicon.ico" 2>/dev/null || true
        inject_antifingerprint_hash
    else
        create_default_fallback_html
    fi
}

select_and_download_template() {
    echo -e "  ${WHITE}Выберите HTML-шаблон для маскировки Reality (${CADDY_HTML_DIR}):${NC}"
    local i=1
    for entry in "${TEMPLATES[@]}"; do
        printf "    ${ORANGE}%2d)${NC} %s\n" "$i" "${entry#*:}"
        i=$((i + 1))
    done
    printf "    ${ORANGE}%2d)${NC} ${YELLOW}Случайный шаблон${NC}\n" "$i"
    echo

    local tmpl_choice="$i"
    if [ "${NON_INTERACTIVE:-false}" != true ]; then
        prompt_choice "Номер шаблона [1-$i]: " "$i" tmpl_choice "$i"
    fi

    local entry
    if [ "$tmpl_choice" -eq "$i" ]; then
        entry="${TEMPLATES[$RANDOM % ${#TEMPLATES[@]}]}"
    else
        entry="${TEMPLATES[$((tmpl_choice - 1))]}"
    fi
    download_template "${entry%%:*}" "${entry#*:}"
}

# ── Ожидание выписки Let's Encrypt сертификата в томе Caddy ───────
wait_for_caddy_certificate() {
    local domain="$1"
    local max_wait="${2:-90}"
    local waited=0

    log_info "Ожидание выпуска Let's Encrypt сертификата для ${domain} (до ${max_wait} сек)..."
    while [ $waited -lt "$max_wait" ]; do
        if is_container_running "$CADDY_CONTAINER_NAME"; then
            local found_crt=""
            found_crt=$(docker exec "$CADDY_CONTAINER_NAME" sh -c "find /data/caddy/certificates -type f -name '${domain}.crt' 2>/dev/null | head -1" 2>/dev/null || true)
            if [ -n "$found_crt" ]; then
                log_success "Сертификат Let's Encrypt успешно получен: ${found_crt}"
                return 0
            fi
        fi
        sleep 3
        waited=$((waited + 3))
    done
    log_warning "Таймаут ожидания сертификата (${max_wait}с). Убедитесь, что DNS A-запись ${domain} указывает на ${NODE_IP} и порт 80 открыт."
    return 0
}

# ── Развертывание Caddy Selfsteal в /opt/selfsteel ────────────────
install_caddy_selfsteal() {
    print_header "РАЗВЕРТЫВАНИЕ CADDY SELFSTEAL (/opt/selfsteel)"

    if check_existing_caddy && [ "${NON_INTERACTIVE:-false}" != true ]; then
        log_warning "Caddy Selfsteal уже установлен в $CADDY_DIR"
        echo -e "    ${ORANGE}1)${NC} Пропустить   ${ORANGE}2)${NC} Перезаписать (с бэкапом)"
        local cc; prompt_choice "Выбор [1-2]: " 2 cc "1"
        if [ "$cc" = "1" ]; then
            STATUS_CADDY="уже установлен"
            DETAIL_CADDY_DOMAIN=$(get_saved_caddy_domain)
            DETAIL_CADDY_PORT=$(get_saved_caddy_port)
            return 0
        fi
        backup_existing_config "$CADDY_DIR"
        docker compose --project-directory "$CADDY_DIR" down 2>/dev/null || true
    fi

    local domain="${SELF_STEAL_DOMAIN:-${CFG_DOMAIN:-}}"
    if [ "${NON_INTERACTIVE:-false}" != true ] && [ -z "$domain" ]; then
        while [ -z "$domain" ]; do
            read -p "  ${ORANGE}>${NC} Домен для fallback/SNI (SELF_STEAL_DOMAIN): " -r domain
            domain=$(echo "$domain" | tr -d '[:space:]' | sed 's|^https\?://||;s|/.*$||')
            if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
                log_warning "Некорректный формат домена!"
                domain=""
            fi
        done
    fi
    SELF_STEAL_DOMAIN="$domain"
    DETAIL_CADDY_DOMAIN="$domain"

    local port="${SELF_STEAL_PORT:-${CFG_CADDY_PORT:-$DEFAULT_PORT}}"
    if [ "${NON_INTERACTIVE:-false}" != true ] && [ -z "${SELF_STEAL_PORT:-}" ]; then
        while true; do
            read -p "  ${ORANGE}>${NC} Внутренний порт fallback SELF_STEAL_PORT [${DEFAULT_PORT}]: " -r port
            port="${port:-$DEFAULT_PORT}"
            if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] && [ "$port" -ne 443 ]; then
                break
            fi
            log_warning "Укажите порт от 1024 до 65535 (кроме 443)."
        done
    fi
    SELF_STEAL_PORT="$port"
    DETAIL_CADDY_PORT="$port"

    # 1. Создание /opt/html/index.html и директории /opt/selfsteel
    mkdir -p "$CADDY_DIR" "$CADDY_HTML_DIR" "$CADDY_DIR/logs"
    touch "$CADDY_DIR/logs/access.log"
    chmod 644 "$CADDY_DIR/logs/access.log"

    if [ "${NON_INTERACTIVE:-false}" = true ]; then
        if [ ! -f "$CADDY_HTML_DIR/index.html" ]; then
            download_template "filecloud" "FileCloud"
        fi
    else
        select_and_download_template || create_default_fallback_html
    fi

    # 2. Генерация /opt/selfsteel/.env
    umask 077
    cat > "$CADDY_DIR/.env" << EOF
SELF_STEAL_DOMAIN=${SELF_STEAL_DOMAIN}
SELF_STEAL_PORT=${SELF_STEAL_PORT}
EOF
    chmod 600 "$CADDY_DIR/.env"
    umask 022

    # 3. Генерация /opt/selfsteel/Caddyfile (с поддержкой proxy_protocol + tls)
    cat > "$CADDY_DIR/Caddyfile" << 'EOF'
{
    https_port {$SELF_STEAL_PORT}
    default_bind 127.0.0.1
    servers {
        listener_wrappers {
            proxy_protocol {
                allow 127.0.0.1/32
            }
            tls
        }
    }
    auto_https disable_redirects
}

http://{$SELF_STEAL_DOMAIN} {
    bind 0.0.0.0
    redir https://{$SELF_STEAL_DOMAIN}{uri} permanent
}

https://{$SELF_STEAL_DOMAIN} {
    root * /var/www/html
    try_files {path} /index.html
    file_server
    log {
        output file /var/log/caddy/access.log {
            roll_size 10MB
            roll_keep 5
        }
        format json
    }
}

:{$SELF_STEAL_PORT} {
    tls internal
    respond 204
}

:80 {
    bind 0.0.0.0
    respond 204
}
EOF

    # 4. Генерация /opt/selfsteel/docker-compose.yml
    cat > "$CADDY_DIR/docker-compose.yml" << 'EOF'
services:
  caddy:
    image: caddy:latest
    container_name: caddy-remnawave
    restart: unless-stopped
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - /opt/html:/var/www/html
      - ./logs:/var/log/caddy
      - caddy_data_selfsteal:/data
      - caddy_config_selfsteal:/config
    env_file:
      - .env
    network_mode: "host"

volumes:
  caddy_data_selfsteal:
    name: selfsteel_caddy_data_selfsteal
  caddy_config_selfsteal:
    name: selfsteel_caddy_config_selfsteal
EOF

    # 5. Запуск контейнера Caddy и ожидание сертификата
    docker rm -f caddy-selfsteal "$CADDY_CONTAINER_NAME" 2>/dev/null || true
    docker compose --project-directory "$CADDY_DIR" pull --quiet 2>/dev/null || true
    docker compose --project-directory "$CADDY_DIR" up -d --remove-orphans

    if check_container_health "$CADDY_CONTAINER_NAME" 30; then
        log_success "Контейнер ${CADDY_CONTAINER_NAME} запущен (127.0.0.1:${SELF_STEAL_PORT})"
        wait_for_caddy_certificate "$SELF_STEAL_DOMAIN" 60
        STATUS_CADDY="установлен"
    else
        log_error "Контейнер ${CADDY_CONTAINER_NAME} не запустился. Проверьте: node-mgr logs caddy"
        STATUS_CADDY="ошибка"
        return 1
    fi
}

# ── Развертывание контейнера Remnanode с пробросом тома сертификатов ─
deploy_remnanode_container() {
    local node_port="$1"
    local secret_key="$2"
    local panel_ip="${3:-}"

    mkdir -p "$REMNANODE_DIR" "$REMNANODE_DATA_DIR" /var/log/remnanode
    DETAIL_REMNANODE_PORT="$node_port"
    if [ -n "$panel_ip" ]; then
        DETAIL_PANEL_IP="$panel_ip"
    fi

    # Сохраняем .env для диагностики и UFW ACL
    umask 077
    cat > "$REMNANODE_DIR/.env" << EOF
NODE_PORT=${node_port}
PANEL_IP=${panel_ip}
SECRET_KEY=${secret_key}
EOF
    chmod 600 "$REMNANODE_DIR/.env"
    umask 022

    # Убеждаемся, что внешний том сертификатов существует
    if ! docker volume inspect "$CADDY_DATA_VOL" >/dev/null 2>&1; then
        docker volume create "$CADDY_DATA_VOL" >/dev/null 2>&1 || true
    fi

    # Генерация /opt/remnanode/docker-compose.yml по спецификации
    cat > "$REMNANODE_DIR/docker-compose.yml" << EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${node_port}
      - SECRET_KEY=${secret_key}
    volumes:
      - ${CADDY_DATA_VOL}:/certs:ro
      - /var/log/remnanode:/var/log/remnanode
      - /dev/shm:/dev/shm

volumes:
  ${CADDY_DATA_VOL}:
    external: true
EOF

    setup_logrotate
    docker rm -f remnanode 2>/dev/null || true
    docker compose --project-directory "$REMNANODE_DIR" pull --quiet 2>/dev/null || true
    docker compose --project-directory "$REMNANODE_DIR" up -d --remove-orphans

    if check_container_health "remnanode" 30; then
        log_success "Контейнер remnanode успешно запущен (порт: ${node_port}, том сертификатов: /certs:ro)"
        STATUS_REMNANODE="установлен"
        return 0
    else
        log_error "Контейнер remnanode не вышел в статус Up"
        STATUS_REMNANODE="ошибка"
        return 1
    fi
}

# ── Ручная установка Remnanode (если API-токен не используется) ───
install_remnanode_manual() {
    print_header "РУЧНАЯ УСТАНОВКА REMNANODE (/opt/remnanode)"

    if check_existing_remnanode && [ "${NON_INTERACTIVE:-false}" != true ]; then
        log_warning "RemnawaveNode уже установлен в $REMNANODE_DIR"
        echo -e "    ${ORANGE}1)${NC} Пропустить   ${ORANGE}2)${NC} Перезаписать (с бэкапом)"
        local rc; prompt_choice "Выбор [1-2]: " 2 rc "1"
        if [ "$rc" = "1" ]; then
            STATUS_REMNANODE="уже установлен"
            DETAIL_REMNANODE_PORT=$(get_saved_node_port)
            DETAIL_PANEL_IP=$(get_saved_panel_ip)
            return 0
        fi
        backup_existing_config "$REMNANODE_DIR"
        docker compose --project-directory "$REMNANODE_DIR" down 2>/dev/null || true
    fi

    local SECRET_KEY_VALUE=""
    if [ "${NON_INTERACTIVE:-false}" = true ] && [ -n "$CFG_SECRET_KEY" ]; then
        SECRET_KEY_VALUE="$CFG_SECRET_KEY"
    else
        echo -e "  ${ORANGE}[KEY] Вставьте SECRET_KEY из панели Remnawave (нажмите ENTER на пустой строке для завершения):${NC}"
        while IFS= read -r line; do
            if [ -z "$line" ]; then break; fi
            SECRET_KEY_VALUE="${SECRET_KEY_VALUE}${line}"
        done
    fi
    if [ -z "$SECRET_KEY_VALUE" ]; then
        log_error "SECRET_KEY не может быть пустым!"
        STATUS_REMNANODE="ошибка"
        return 1
    fi

    local NODE_PORT="${CFG_NODE_PORT:-3000}"
    if [ "${NON_INTERACTIVE:-false}" != true ]; then
        while true; do
            read -p "  ${ORANGE}>${NC} Порт управления NODE_PORT [3000]: " -r NODE_PORT
            NODE_PORT=${NODE_PORT:-3000}
            if [[ "$NODE_PORT" =~ ^[0-9]+$ ]] && [ "$NODE_PORT" -ge 1 ] && [ "$NODE_PORT" -le 65535 ]; then
                break
            fi
            log_warning "Порт должен быть числом от 1 до 65535."
        done
    fi

    local PANEL_IP_VALUE="${CFG_PANEL_IP:-}"
    if [ "${NON_INTERACTIVE:-false}" != true ] || [ -z "$PANEL_IP_VALUE" ]; then
        local current_pip; current_pip=$(get_saved_panel_ip)
        while [ -z "$PANEL_IP_VALUE" ]; do
            read -p "  ${ORANGE}>${NC} Белый IP-адрес панели Remnawave (для ACL порта ${NODE_PORT})${current_pip:+ [Enter=$current_pip]}: " -r PANEL_IP_VALUE
            PANEL_IP_VALUE="${PANEL_IP_VALUE:-$current_pip}"
            PANEL_IP_VALUE=$(echo "$PANEL_IP_VALUE" | tr -d '[:space:]')
            if ! validate_ip_or_cidr "$PANEL_IP_VALUE"; then
                log_warning "Введите корректный IPv4-адрес панели!"
                PANEL_IP_VALUE=""
            fi
        done
    fi

    deploy_remnanode_container "$NODE_PORT" "$SECRET_KEY_VALUE" "$PANEL_IP_VALUE"
}

# ═══════════════════════════════════════════════════════════════════
#  АВТОМАТИЗАЦИЯ ЧЕРЕЗ REMNAWAVE API (cURL + jq)
# ═══════════════════════════════════════════════════════════════════
remnawave_api_request() {
    local method="$1"
    local endpoint="$2"
    local payload="${3:-}"
    local base_url="${REMNAWAVE_API_URL%/}"
    local url="${base_url}${endpoint}"

    local resp_file http_code
    resp_file=$(create_temp_file)

    if [ -n "$payload" ]; then
        http_code=$(curl -sS -w "%{http_code}" -o "$resp_file" \
            -X "$method" "$url" \
            -H "Authorization: Bearer ${REMNAWAVE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            --connect-timeout 10 --max-time 25 \
            -d "$payload" 2>/dev/null || echo "000")
    else
        http_code=$(curl -sS -w "%{http_code}" -o "$resp_file" \
            -X "$method" "$url" \
            -H "Authorization: Bearer ${REMNAWAVE_API_TOKEN}" \
            -H "Accept: application/json" \
            --connect-timeout 10 --max-time 25 2>/dev/null || echo "000")
    fi

    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        cat "$resp_file"
        return 0
    else
        log_error "API ${method} ${endpoint} вернул HTTP ${http_code}:"
        cat "$resp_file" >&2 || true
        echo >&2
        return 1
    fi
}

collect_api_inputs() {
    print_header "ПАРАМЕТРЫ АВТОМАТИЗАЦИИ REMNAWAVE API"

    if [ -z "$REMNAWAVE_API_URL" ]; then
        while [ -z "$REMNAWAVE_API_URL" ]; do
            read -p "  ${ORANGE}>${NC} URL панели (REMNAWAVE_API_URL, напр. https://panel.example.com): " -r REMNAWAVE_API_URL
            REMNAWAVE_API_URL=$(echo "$REMNAWAVE_API_URL" | tr -d '[:space:]' | sed 's|/$||')
            if [[ ! "$REMNAWAVE_API_URL" =~ ^https?:// ]]; then
                log_warning "URL должен начинаться с https:// или http://"
                REMNAWAVE_API_URL=""
            fi
        done
    fi

    if [ -z "$REMNAWAVE_API_TOKEN" ]; then
        while [ -z "$REMNAWAVE_API_TOKEN" ]; do
            read -s -p "  ${ORANGE}>${NC} API Bearer токен (REMNAWAVE_API_TOKEN): " -r REMNAWAVE_API_TOKEN
            echo
            REMNAWAVE_API_TOKEN=$(echo "$REMNAWAVE_API_TOKEN" | tr -d '\r\n ')
        done
    fi

    if [ -z "$NODE_NAME" ]; then
        local def_name
        def_name=$(hostname 2>/dev/null || echo "LissNode-01")
        read -p "  ${ORANGE}>${NC} Имя новой ноды (NODE_NAME) [${def_name}]: " -r NODE_NAME
        NODE_NAME="${NODE_NAME:-$def_name}"
    fi

    if [ -z "$NODE_ADDRESS" ]; then
        read -p "  ${ORANGE}>${NC} Внешний IP или домен ноды (NODE_ADDRESS) [${NODE_IP}]: " -r NODE_ADDRESS
        NODE_ADDRESS="${NODE_ADDRESS:-$NODE_IP}"
    fi

    if [ -z "$SELF_STEAL_DOMAIN" ]; then
        while [ -z "$SELF_STEAL_DOMAIN" ]; do
            read -p "  ${ORANGE}>${NC} Домен маскировки SNI (SELF_STEAL_DOMAIN): " -r SELF_STEAL_DOMAIN
            SELF_STEAL_DOMAIN=$(echo "$SELF_STEAL_DOMAIN" | tr -d '[:space:]' | sed 's|^https\?://||;s|/.*$||')
        done
    fi

    if [ -z "${SELF_STEAL_PORT:-}" ]; then
        SELF_STEAL_PORT="$DEFAULT_PORT"
    fi

    # Авто-резолв IP панели из REMNAWAVE_API_URL для UFW
    if [ -z "${CFG_PANEL_IP:-}" ]; then
        local resolved_pip
        resolved_pip=$(resolve_host_to_ip "$REMNAWAVE_API_URL")
        if [ -n "$resolved_pip" ] && validate_ip_or_cidr "$resolved_pip"; then
            CFG_PANEL_IP="$resolved_pip"
            DETAIL_PANEL_IP="$resolved_pip"
            log_info "IP панели определен автоматически: ${ORANGE}${CFG_PANEL_IP}${NC}"
        elif [ "${NON_INTERACTIVE:-false}" != true ]; then
            while [ -z "$CFG_PANEL_IP" ]; do
                read -p "  ${ORANGE}>${NC} Белый IP-адрес панели для UFW ACL: " -r CFG_PANEL_IP
                if ! validate_ip_or_cidr "$CFG_PANEL_IP"; then CFG_PANEL_IP=""; fi
            done
            DETAIL_PANEL_IP="$CFG_PANEL_IP"
        fi
    fi
}

automate_remnawave_api() {
    print_header "АВТОМАТИЧЕСКАЯ РЕГИСТРАЦИЯ В ПАНЕЛИ REMNAWAVE API"

    local cert_path="/certs/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${SELF_STEAL_DOMAIN}/${SELF_STEAL_DOMAIN}.crt"
    local key_path="/certs/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${SELF_STEAL_DOMAIN}/${SELF_STEAL_DOMAIN}.key"
    local inbound_tag="XHTTP-SELFSTEAL-${NODE_NAME//[^a-zA-Z0-9_-]/}"
    local profile_name="Profile-${NODE_NAME}"

    # Генерация ключей Reality и shortId на случай использования Reality-профиля
    local keypair priv_key pub_key short_id
    keypair=$(generate_x25519_keypair)
    priv_key="${keypair%%:*}"
    pub_key="${keypair##*:}"
    short_id=$(openssl rand -hex 8 2>/dev/null || echo "a1b2c3d4e5f60718")

    # ── 1. Создание или поиск Config Profile (Inbound xhttp + reality/certs) ──
    log_info "Шаг 1/3: Создание Inbound-профиля (xhttp / reality) в панели..."
    local profile_payload profile_resp profile_uuid="" inbound_uuid=""

    profile_payload=$(jq -n \
        --arg name "$profile_name" \
        --arg tag "$inbound_tag" \
        --arg dom "$SELF_STEAL_DOMAIN" \
        --arg dest "127.0.0.1:${SELF_STEAL_PORT}" \
        --arg cert "$cert_path" \
        --arg key "$key_path" \
        --arg pk "$priv_key" \
        --arg sid "$short_id" \
        '{
            name: $name,
            config: {
                log: { loglevel: "warning" },
                inbounds: [
                    {
                        tag: $tag,
                        port: 443,
                        protocol: "vless",
                        settings: {
                            clients: [],
                            decryption: "none"
                        },
                        streamSettings: {
                            network: "xhttp",
                            security: "reality",
                            xhttpSettings: {
                                path: "/",
                                mode: "auto"
                            },
                            tlsSettings: {
                                serverName: $dom,
                                certificates: [
                                    {
                                        certificateFile: $cert,
                                        keyFile: $key
                                    }
                                ]
                            },
                            realitySettings: {
                                show: false,
                                dest: $dest,
                                xver: 1,
                                serverNames: [$dom],
                                privateKey: $pk,
                                shortIds: [$sid]
                            }
                        },
                        sniffing: {
                            enabled: true,
                            destOverride: ["http", "tls", "quic"]
                        }
                    }
                ],
                outbounds: [
                    { tag: "DIRECT", protocol: "freedom" },
                    { tag: "BLOCK", protocol: "blackhole" }
                ]
            }
        }')

    # Поддержка обоих стандартных эндпоинтов профилей Remnawave (/api/config-profiles и /api/inbounds)
    if profile_resp=$(remnawave_api_request "POST" "/api/config-profiles" "$profile_payload" 2>/dev/null); then
        profile_uuid=$(echo "$profile_resp" | jq -r '.response.uuid // .data.uuid // .uuid // .id // empty')
        inbound_uuid=$(echo "$profile_resp" | jq -r '.response.inbounds[0].uuid // .data.inbounds[0].uuid // .inbounds[0].uuid // empty')
    elif profile_resp=$(remnawave_api_request "POST" "/api/inbounds" "$profile_payload" 2>/dev/null); then
        profile_uuid=$(echo "$profile_resp" | jq -r '.response.configProfileUuid // .response.uuid // .data.uuid // .uuid // .id // empty')
        inbound_uuid=$(echo "$profile_resp" | jq -r '.response.uuid // .data.uuid // .uuid // .id // empty')
    else
        log_warning "Профиль с таким именем/тегом может уже существовать, проверяем список существующих..."
        local existing_profiles
        existing_profiles=$(remnawave_api_request "GET" "/api/config-profiles" "" 2>/dev/null || true)
        if [ -n "$existing_profiles" ]; then
            profile_uuid=$(echo "$existing_profiles" | jq -r --arg n "$profile_name" '(.response.configProfiles // .response // .data // []) | map(select(.name == $n))[0].uuid // .[0].uuid // empty')
            inbound_uuid=$(echo "$existing_profiles" | jq -r '(.response.configProfiles // .response // .data // [])[0].inbounds[0].uuid // empty')
        fi
    fi

    if [ -n "$profile_uuid" ]; then
        DETAIL_PROFILE_UUID="$profile_uuid"
        log_success "Inbound-профиль готов (UUID: ${profile_uuid})"
    else
        log_warning "Не удалось получить UUID профиля автоматически, продолжаем создание ноды..."
    fi

    # ── 2. Создание Ноды (POST /api/nodes) ─────────────────────────
    log_info "Шаг 2/3: Регистрация ноды '${NODE_NAME}' (${NODE_ADDRESS})..."
    local req_node_port="${CFG_NODE_PORT:-3000}"
    local node_payload node_resp node_uuid="" node_secret="" parsed_port=""

    if [ -n "$profile_uuid" ] && [ -n "$inbound_uuid" ]; then
        node_payload=$(jq -n \
            --arg name "$NODE_NAME" \
            --arg addr "$NODE_ADDRESS" \
            --argjson port "$req_node_port" \
            --arg p_uuid "$profile_uuid" \
            --arg i_uuid "$inbound_uuid" \
            '{
                name: $name,
                address: $addr,
                port: $port,
                configProfile: {
                    activeConfigProfileUuid: $p_uuid,
                    activeInbounds: [$i_uuid]
                }
            }')
    else
        node_payload=$(jq -n \
            --arg name "$NODE_NAME" \
            --arg addr "$NODE_ADDRESS" \
            --argjson port "$req_node_port" \
            '{
                name: $name,
                address: $addr,
                port: $port
            }')
    fi

    if node_resp=$(remnawave_api_request "POST" "/api/nodes" "$node_payload"); then
        node_uuid=$(echo "$node_resp" | jq -r '.response.uuid // .data.uuid // .uuid // .id // empty')
        node_secret=$(echo "$node_resp" | jq -r '.response.secretKey // .response.secret_key // .response.credentials.secretKey // .data.secretKey // .secretKey // .secret_key // empty')
        parsed_port=$(echo "$node_resp" | jq -r '.response.port // .data.port // .port // empty')
    else
        log_warning "Нода '${NODE_NAME}' уже может существовать в панели, ищем по списку нод..."
        local nodes_list
        nodes_list=$(remnawave_api_request "GET" "/api/nodes" "" 2>/dev/null || true)
        if [ -n "$nodes_list" ]; then
            node_uuid=$(echo "$nodes_list" | jq -r --arg addr "$NODE_ADDRESS" --arg nm "$NODE_NAME" '(.response // .data // []) | map(select(.address == $addr or .name == $nm))[0].uuid // empty')
            node_secret=$(echo "$nodes_list" | jq -r --arg addr "$NODE_ADDRESS" --arg nm "$NODE_NAME" '(.response // .data // []) | map(select(.address == $addr or .name == $nm))[0].secretKey // empty')
            parsed_port=$(echo "$nodes_list" | jq -r --arg addr "$NODE_ADDRESS" --arg nm "$NODE_NAME" '(.response // .data // []) | map(select(.address == $addr or .name == $nm))[0].port // empty')
        fi
    fi

    if [ -z "$node_secret" ]; then
        log_error "Не удалось получить SECRET_KEY из ответа API панели!"
        STATUS_API="ошибка"
        return 1
    fi

    CFG_SECRET_KEY="$node_secret"
    CFG_NODE_PORT="${parsed_port:-$req_node_port}"
    DETAIL_REMNANODE_PORT="$CFG_NODE_PORT"
    DETAIL_NODE_UUID="$node_uuid"
    log_success "Нода зарегистрирована! ID: ${node_uuid:-ok} | Порт: ${CFG_NODE_PORT}"

    # ── 3. Создание Хоста (POST /api/hosts) ────────────────────────
    log_info "Шаг 3/3: Создание Хоста для домена ${SELF_STEAL_DOMAIN}..."
    local host_payload host_resp host_uuid=""

    host_payload=$(jq -n \
        --arg remark "$NODE_NAME" \
        --arg addr "$SELF_STEAL_DOMAIN" \
        --arg sni "$SELF_STEAL_DOMAIN" \
        --arg p_uuid "$profile_uuid" \
        --arg i_uuid "$inbound_uuid" \
        '{
            remark: $remark,
            address: $addr,
            port: 443,
            sni: $sni,
            host: $addr,
            path: "/",
            securityLayer: "DEFAULT",
            inbound: {
                configProfileUuid: (if $p_uuid != "" then $p_uuid else null end),
                configProfileInboundUuid: (if $i_uuid != "" then $i_uuid else null end)
            }
        }')

    if host_resp=$(remnawave_api_request "POST" "/api/hosts" "$host_payload" 2>/dev/null); then
        host_uuid=$(echo "$host_resp" | jq -r '.response.uuid // .data.uuid // .uuid // .id // empty')
        DETAIL_HOST_UUID="$host_uuid"
        log_success "Хост успешно создан в панели (UUID: ${host_uuid})"
    else
        log_warning "Хост не был создан автоматически (возможно, уже существует) — проверьте раздел Hosts в панели."
    fi

    # Сохраняем метаданные API-деплоя
    umask 077
    cat > "$API_STATE_FILE" << EOF
REMNAWAVE_API_URL="${REMNAWAVE_API_URL}"
NODE_NAME="${NODE_NAME}"
NODE_ADDRESS="${NODE_ADDRESS}"
NODE_UUID="${DETAIL_NODE_UUID}"
PROFILE_UUID="${DETAIL_PROFILE_UUID}"
HOST_UUID="${DETAIL_HOST_UUID}"
SELF_STEAL_DOMAIN="${SELF_STEAL_DOMAIN}"
SELF_STEAL_PORT="${SELF_STEAL_PORT}"
REALITY_PUBLIC_KEY="${pub_key}"
REALITY_SHORT_ID="${short_id}"
PANEL_IP="${CFG_PANEL_IP}"
EOF
    chmod 600 "$API_STATE_FILE"
    umask 022

    STATUS_API="выполнен"
    return 0
}

change_template() {
    _init_env
    mkdir -p "$CADDY_HTML_DIR"
    print_header "СМЕНА HTML-ШАБЛОНА МАСКИРОВКИ (${CADDY_HTML_DIR})"
    select_and_download_template
    log_success "Шаблон обновлен на лету."
}

# ═══════════════════════════════════════════════════════════════════
#  МОДУЛЬ 4: ЗАЩИТА ПЕРИМЕТРА (UFW Strict Panel ACL + Fail2ban Fix)
# ═══════════════════════════════════════════════════════════════════
setup_ufw() {
    print_header "НАСТРОЙКА UFW FIREWALL (STRICT PANEL ACL)"

    if ! prompt_yn "Настроить межсетевой экран UFW? (y/n): " "y" "$CFG_SETUP_UFW"; then
        return 0
    fi

    if ! command -v ufw >/dev/null 2>&1; then
        install_package ufw || { STATUS_UFW="ошибка"; return 1; }
    fi

    local ssh_port node_port caddy_port panel_ip
    ssh_port=$(detect_ssh_port)
    node_port=$(get_saved_node_port)
    caddy_port=$(get_saved_caddy_port)
    panel_ip=$(get_saved_panel_ip)

    while [ -z "$panel_ip" ]; do
        if [ "${NON_INTERACTIVE:-false}" = true ]; then
            log_error "CFG_PANEL_IP не задан! Открытие порта ноды всему миру запрещено."
            STATUS_UFW="ошибка"
            return 1
        fi
        read -p "  ${ORANGE}>${NC} Введите IP-адрес панели Remnawave (для доступа к порту ${node_port}): " -r panel_ip
        panel_ip=$(echo "$panel_ip" | tr -d '[:space:]')
        if ! validate_ip_or_cidr "$panel_ip"; then
            log_warning "Введите корректный IPv4-адрес панели!"
            panel_ip=""
        fi
    done
    DETAIL_PANEL_IP="$panel_ip"

    if [ -f "$REMNANODE_DIR/.env" ]; then
        if grep -q "^PANEL_IP=" "$REMNANODE_DIR/.env"; then
            sed -i "s|^PANEL_IP=.*|PANEL_IP=$panel_ip|" "$REMNANODE_DIR/.env"
        else
            echo "PANEL_IP=$panel_ip" >> "$REMNANODE_DIR/.env"
        fi
    fi

    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    ufw allow in on lo >/dev/null 2>&1 || true

    ufw allow "${ssh_port}/tcp" comment 'SSH Active' >/dev/null 2>&1 || true
    if [ "$ssh_port" != "22" ]; then
        ufw allow 22/tcp comment 'SSH Default' >/dev/null 2>&1 || true
    fi

    ufw delete allow "${node_port}/tcp" >/dev/null 2>&1 || true
    ufw delete allow "${node_port}" >/dev/null 2>&1 || true
    local old_rule_num=""
    while true; do
        old_rule_num=$(ufw status numbered 2>/dev/null | awk -v p="$node_port" '$0 ~ p && $0 ~ /ALLOW/ {gsub(/[\[\]]/,"",$1); print $1; exit}')
        if [ -n "$old_rule_num" ] && [[ "$old_rule_num" =~ ^[0-9]+$ ]]; then
            ufw --force delete "$old_rule_num" >/dev/null 2>&1 || break
        else
            break
        fi
    done

    ufw allow from "$panel_ip" to any port "$node_port" proto tcp comment 'RemnaNode API (Panel Only)' >/dev/null 2>&1

    ufw allow 443/tcp comment 'Xray Reality TCP' >/dev/null 2>&1
    ufw allow 443/udp comment 'Xray Reality QUIC' >/dev/null 2>&1
    ufw allow 80/tcp comment 'Caddy ACME HTTP-01' >/dev/null 2>&1

    if [ -n "$caddy_port" ] && [ "$caddy_port" != "443" ]; then
        ufw delete allow "${caddy_port}/tcp" >/dev/null 2>&1 || true
        ufw deny in to any port "$caddy_port" comment 'Block Selfsteal Fallback' >/dev/null 2>&1
    fi

    ufw --force enable >/dev/null 2>&1
    _log_fix "UFW enabled (port ${node_port} restricted to panel ${panel_ip})"
    log_success "UFW активен: порт ${node_port}/tcp открыт ТОЛЬКО для панели ${panel_ip}"
    STATUS_UFW="настроен"
}

install_fail2ban() {
    print_header "УСТАНОВКА И НАСТРОЙКА FAIL2BAN (SYSTEMD + UFW)"

    if ! prompt_yn "Настроить и запустить службу Fail2ban? (y/n): " "y" "$CFG_INSTALL_FAIL2BAN"; then
        return 0
    fi

    if ! command -v fail2ban-client >/dev/null 2>&1; then
        install_package fail2ban || { STATUS_FAIL2BAN="ошибка"; return 1; }
    fi
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        install_package python3-systemd >/dev/null 2>&1 || true
    fi

    systemctl stop fail2ban 2>/dev/null || true
    pkill -9 -f fail2ban-server 2>/dev/null || true
    rm -f /var/run/fail2ban/fail2ban.sock /run/fail2ban/fail2ban.sock /var/run/fail2ban/fail2ban.pid 2>/dev/null || true
    rm -f /etc/fail2ban/jail.d/*.local /etc/fail2ban/jail.d/*.conf 2>/dev/null || true

    mkdir -p "$CADDY_DIR/logs" /var/log/remnanode /etc/fail2ban/filter.d /etc/fail2ban/action.d
    touch "$CADDY_DIR/logs/access.log"
    chmod 644 "$CADDY_DIR/logs/access.log"

    if [ ! -f /etc/fail2ban/action.d/ufw.conf ]; then
        cat > /etc/fail2ban/action.d/ufw.conf << 'EOF'
[Definition]
actionstart =
actionstop =
actioncheck =
actionban = [ -n "<ip>" ] && ufw insert 1 deny from <ip> to any
actionunban = [ -n "<ip>" ] && ufw delete deny from <ip> to any
EOF
    fi

    cat > /etc/fail2ban/filter.d/caddy-status.conf << 'EOF'
[Definition]
failregex = ^.*"remote_ip":"<HOST>".*"status":(400|401|403|404|405|444)\b.*$
            ^.*"client_ip":"<HOST>".*"status":(400|401|403|404|405|444)\b.*$
            ^.*"status":(400|401|403|404|405|444)\b.*"remote_ip":"<HOST>".*$
            ^.*"status":(400|401|403|404|405|444)\b.*"client_ip":"<HOST>".*$
ignoreregex =
EOF

    local ssh_port ssh_backend ssh_logpath_line=""
    ssh_port=$(detect_ssh_port)
    if python3 -c "import systemd.journal" >/dev/null 2>&1; then
        ssh_backend="systemd"
    elif [ -f /var/log/auth.log ]; then
        ssh_backend="auto"
        ssh_logpath_line="logpath = /var/log/auth.log"
    else
        touch /var/log/auth.log
        chmod 640 /var/log/auth.log
        ssh_backend="polling"
        ssh_logpath_line="logpath = /var/log/auth.log"
    fi

    local f2b_banaction="iptables-multiport"
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
        f2b_banaction="ufw"
    fi

    local panel_ip_ignore
    panel_ip_ignore=$(get_saved_panel_ip)

    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
banaction = ${f2b_banaction}
banaction_allports = ${f2b_banaction}
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 ${panel_ip_ignore}
bantime = 1h
findtime = 10m
maxretry = 5
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 7d

[sshd]
enabled = true
port = ${ssh_port}
filter = sshd
backend = ${ssh_backend}
${ssh_logpath_line}
maxretry = 4
bantime = 1h

[caddy-status]
enabled = true
port = 80,443
filter = caddy-status
backend = auto
logpath = ${CADDY_DIR}/logs/access.log
maxretry = 15
findtime = 10m
bantime = 1h
EOF

    systemctl daemon-reload
    systemctl enable fail2ban >/dev/null 2>&1 || true
    systemctl restart fail2ban >/dev/null 2>&1 || true

    sleep 2
    if systemctl is-active --quiet fail2ban && fail2ban-client ping >/dev/null 2>&1; then
        local jails
        jails=$(fail2ban-client status 2>/dev/null | awk -F'Jail list:' '/Jail list:/ {gsub(/^[ \t]+/, "", $2); print $2}')
        _log_fix "Fail2ban started (jails: ${jails})"
        log_success "Fail2ban стабильно запущен! Активные джейлы: ${ORANGE}${jails}${NC}"
        STATUS_FAIL2BAN="установлен"
    else
        log_error "Ошибка запуска Fail2ban. Вывод fail2ban-client -t:"
        fail2ban-client -t >&2 || true
        STATUS_FAIL2BAN="ошибка"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  Сценарии развертывания: API Auto-Deploy и Интерактивная установка
# ═══════════════════════════════════════════════════════════════════
run_api_auto_deploy() {
    _init_env
    print_header "АВТОМАТИЧЕСКОЕ РАЗВЕРТЫВАНИЕ ЧЕРЕЗ REMNAWAVE API [1/7 .. 7/7]"

    if ! check_disk_space 500 "/opt"; then
        if ! prompt_yn "Продолжить? (y/n): " "n"; then exit 1; fi
    fi

    ensure_package_manager_available
    _RESTORE_AUTO_UPDATES=true

    echo -e "\n  ${ORANGE}${BOLD}[1/7] Проверка утилит (curl, jq, openssl, ethtool) и сбор параметров API${NC}"
    install_base_utilities
    collect_api_inputs

    echo -e "\n  ${ORANGE}${BOLD}[2/7] Highload-оптимизация ядра, RPS, NIC и лимитов${NC}"
    run_optimize "--all"

    echo -e "\n  ${ORANGE}${BOLD}[3/7] Проверка и установка Docker Engine & Compose v2${NC}"
    if install_docker && check_docker_compose; then
        STATUS_DOCKER="установлен"
    else
        STATUS_DOCKER="ошибка"
        exit 1
    fi

    echo -e "\n  ${ORANGE}${BOLD}[4/7] Развертывание Caddy Selfsteal (/opt/selfsteel) и выпуск SSL${NC}"
    install_caddy_selfsteal

    echo -e "\n  ${ORANGE}${BOLD}[5/7] Автоматическое создание Профиля, Ноды и Хоста через Remnawave API${NC}"
    automate_remnawave_api

    echo -e "\n  ${ORANGE}${BOLD}[6/7] Развертывание Remnanode (/opt/remnanode) с пробросом /certs:ro${NC}"
    deploy_remnanode_container "$CFG_NODE_PORT" "$CFG_SECRET_KEY" "$CFG_PANEL_IP"

    echo -e "\n  ${ORANGE}${BOLD}[7/7] Изоляция периметра UFW и запуск Fail2ban${NC}"
    setup_ufw
    install_fail2ban

    restore_auto_updates
    _RESTORE_AUTO_UPDATES=false
    show_installation_summary
}

run_full_install() {
    _init_env
    if [ -n "${REMNAWAVE_API_TOKEN:-}" ] && [ -n "${REMNAWAVE_API_URL:-}" ]; then
        run_api_auto_deploy
        return 0
    fi

    print_header "ВЫБОР РЕЖИМА ПОЛНОЙ УСТАНОВКИ УЗЛА"
    echo -e "    ${ORANGE}${BOLD}[1]${NC} ${WHITE}Автоматическая регистрация через Remnawave API${NC} ${DIM}(Нода + Профиль xhttp + Хост + Selfsteal)${NC}"
    echo -e "    ${ORANGE}${BOLD}[2]${NC} ${WHITE}Ручная установка по готовому SECRET_KEY${NC}       ${DIM}(Классический режим)${NC}"
    echo
    local mode_c="1"
    prompt_choice "Выберите режим [1-2, Enter=1]: " 2 mode_c "1"

    if [ "$mode_c" = "1" ]; then
        run_api_auto_deploy
        return 0
    fi

    print_header "КЛАССИЧЕСКАЯ УСТАНОВКА УЗЛА [1/6 .. 6/6]"
    if ! check_disk_space 500 "/opt"; then
        if ! prompt_yn "Продолжить? (y/n): " "n"; then exit 1; fi
    fi
    ensure_package_manager_available
    _RESTORE_AUTO_UPDATES=true
    install_base_utilities

    echo -e "\n  ${ORANGE}${BOLD}[1/6] Оптимизация ядра, RPS, NIC и лимитов${NC}"
    run_optimize "--all"

    echo -e "\n  ${ORANGE}${BOLD}[2/6] Установка Docker Engine${NC}"
    if install_docker && check_docker_compose; then
        STATUS_DOCKER="установлен"
    else
        STATUS_DOCKER="ошибка"
        exit 1
    fi

    echo -e "\n  ${ORANGE}${BOLD}[3/6] Установка Caddy Selfsteal (/opt/selfsteel)${NC}"
    install_caddy_selfsteal

    echo -e "\n  ${ORANGE}${BOLD}[4/6] Установка RemnawaveNode (/opt/remnanode)${NC}"
    install_remnanode_manual

    echo -e "\n  ${ORANGE}${BOLD}[5/6] Настройка UFW Firewall (Strict Panel ACL)${NC}"
    setup_ufw

    echo -e "\n  ${ORANGE}${BOLD}[6/6] Установка и запуск Fail2ban${NC}"
    install_fail2ban

    restore_auto_updates
    _RESTORE_AUTO_UPDATES=false
    show_installation_summary
}

run_selective_install() {
    _init_env
    print_header "ВЫБОРОЧНАЯ УСТАНОВКА / ПОЧИНКА МОДУЛЕЙ"
    echo -e "    ${ORANGE}${BOLD}[1]${NC} Оптимизация ядра (sysctl/BBR/FD/RPS/NIC/MSS/journald)"
    echo -e "    ${ORANGE}${BOLD}[2]${NC} Docker Engine & Compose v2"
    echo -e "    ${ORANGE}${BOLD}[3]${NC} Caddy Selfsteal (/opt/selfsteel + /opt/html)"
    echo -e "    ${ORANGE}${BOLD}[4]${NC} Регистрация через Remnawave API + запуск Remnanode"
    echo -e "    ${ORANGE}${BOLD}[5]${NC} Ручная установка Remnanode (по SECRET_KEY)"
    echo -e "    ${ORANGE}${BOLD}[6]${NC} UFW Firewall (доступ к порту ноды только с IP панели)"
    echo -e "    ${ORANGE}${BOLD}[7]${NC} Fail2ban (починка конфига и перезапуск)"
    echo

    local selection_raw
    read -p "  ${ORANGE}>${NC} Номера через пробел [1-7]: " -r selection_raw
    if [ -z "$selection_raw" ]; then return 0; fi

    ensure_package_manager_available
    _RESTORE_AUTO_UPDATES=true
    install_base_utilities

    for c in $selection_raw; do
        case "$c" in
            1) run_optimize "--all" ;;
            2) if install_docker && check_docker_compose; then STATUS_DOCKER="установлен"; fi ;;
            3) install_caddy_selfsteal ;;
            4) collect_api_inputs && automate_remnawave_api && deploy_remnanode_container "$CFG_NODE_PORT" "$CFG_SECRET_KEY" "$CFG_PANEL_IP" ;;
            5) install_remnanode_manual ;;
            6) setup_ufw ;;
            7) install_fail2ban ;;
        esac
    done

    restore_auto_updates
    _RESTORE_AUTO_UPDATES=false
    show_installation_summary
}

# ═══════════════════════════════════════════════════════════════════
#  Статус, Логи, Автообновление с GitHub, Удаление
# ═══════════════════════════════════════════════════════════════════
show_logs() {
    local target="${1:-node}"
    case "$target" in
        node|remnanode)
            docker logs -f --tail=100 remnanode
            ;;
        caddy|selfsteal)
            if is_container_running "$CADDY_CONTAINER_NAME"; then
                docker logs -f --tail=100 "$CADDY_CONTAINER_NAME"
            else
                docker logs -f --tail=100 caddy-selfsteal
            fi
            ;;
        f2b|fail2ban)
            journalctl -u fail2ban -n 100 -f
            ;;
        *)
            log_error "Использование: node-mgr logs {node|caddy|f2b}"
            ;;
    esac
}

self_update() {
    _init_env
    print_header "АВТООБНОВЛЕНИЕ СКРИПТА С GITHUB (Lissovich-Liss/vpn-node)"
    local tmp_file
    tmp_file=$(create_temp_file)

    log_info "Скачивание свежей версии из ${REPO_RAW_URL}..."
    if ! curl -fsSL -H "Cache-Control: no-cache" --connect-timeout 10 "${REPO_RAW_URL}?t=$(date +%s)" -o "$tmp_file"; then
        log_error "Не удалось скачать файл из репозитория GitHub"
        return 1
    fi

    if ! bash -n "$tmp_file" 2>/dev/null; then
        log_error "Скачанный файл содержит синтаксические ошибки и не будет применен!"
        return 1
    fi

    local new_ver
    new_ver=$(grep -E '^readonly SCRIPT_VERSION=' "$tmp_file" | head -1 | cut -d'"' -f2 || echo "unknown")
    cp -f "$tmp_file" "$BIN_PATH"
    chmod 755 "$BIN_PATH"
    log_success "Утилита node-mgr успешно обновлена (v${SCRIPT_VERSION} -> v${new_ver})!"
}

show_status() {
    _init_env
    print_banner
    echo
    local cc qdisc rmem_mb ssh_p panel_ip node_p caddy_p caddy_dom
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "?")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "?")
    rmem_mb=$(( $(sysctl -n net.core.rmem_max 2>/dev/null || echo 0) / 1048576 ))
    ssh_p=$(detect_ssh_port)
    panel_ip=$(get_saved_panel_ip)
    node_p=$(get_saved_node_port)
    caddy_p=$(get_saved_caddy_port)
    caddy_dom=$(get_saved_caddy_domain)

    box_top "СОСТОЯНИЕ УЗЛА И СЕТЕВОГО СТЕКА"
    box_kv "ОС / Ядро" "${OS} ($(uname -r))"
    box_kv "TCP Congestion" "${cc} + ${qdisc} (rmem_max: ${rmem_mb} MB)"
    box_kv "SSH порт" "${ssh_p}/tcp"
    box_kv "IP Панели (UFW ACL)" "${panel_ip:-не привязан} -> порт ${node_p}/tcp"
    box_kv "Caddy Selfsteal" "${caddy_dom:-не настроен} (127.0.0.1:${caddy_p})"
    box_bottom
    echo

    box_top "СТАТУС СЛУЖБ И КОНТЕЙНЕРОВ"
    if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
        box_row "${GREEN}${BOLD}[ RUNNING ]${NC} Docker Engine"
    else
        box_row "${RED}${BOLD}[ STOPPED ]${NC} Docker Engine"
    fi

    if is_container_running "remnanode"; then
        box_row "${GREEN}${BOLD}[ RUNNING ]${NC} Контейнер remnanode (порт ${node_p}, /certs:ro)"
    else
        box_row "${YELLOW}${BOLD}[ STOPPED ]${NC} Контейнер remnanode"
    fi

    if is_caddy_running; then
        box_row "${GREEN}${BOLD}[ RUNNING ]${NC} Контейнер ${CADDY_CONTAINER_NAME} (127.0.0.1:${caddy_p})"
    else
        box_row "${YELLOW}${BOLD}[ STOPPED ]${NC} Контейнер ${CADDY_CONTAINER_NAME}"
    fi

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
        box_row "${GREEN}${BOLD}[ ACTIVE  ]${NC} UFW Firewall"
    else
        box_row "${YELLOW}${BOLD}[ INACTIVE]${NC} UFW Firewall"
    fi

    if command -v fail2ban-client >/dev/null 2>&1 && systemctl is-active --quiet fail2ban && fail2ban-client ping >/dev/null 2>&1; then
        local jl
        jl=$(fail2ban-client status 2>/dev/null | awk -F'Jail list:' '/Jail list:/ {gsub(/^[ \t]+/, "", $2); print $2}')
        box_row "${GREEN}${BOLD}[ ACTIVE  ]${NC} Fail2ban (Jails: ${jl})"
    else
        box_row "${RED}${BOLD}[ FAILED  ]${NC} Fail2ban"
    fi
    box_bottom
    echo
}

show_installation_summary() {
    echo
    box_top "ИТОГИ РАЗВЕРТЫВАНИЯ УЗЛА LISSVPN"
    box_kv "Сетевой стек Highload" "$STATUS_NETWORK"
    box_kv "Docker Engine" "$STATUS_DOCKER"
    box_kv "Caddy Selfsteal" "$STATUS_CADDY ($(get_saved_caddy_domain) : $(get_saved_caddy_port))"
    box_kv "Remnawave API" "$STATUS_API ${DETAIL_NODE_UUID:+(Node UUID: $DETAIL_NODE_UUID)}"
    box_kv "RemnawaveNode" "$STATUS_REMNANODE (порт: $(get_saved_node_port), /certs:ro)"
    box_kv "UFW Firewall (ACL)" "$STATUS_UFW (панель: $(get_saved_panel_ip))"
    box_kv "Fail2ban" "$STATUS_FAIL2BAN"
    box_bottom
    echo
}

update_components() {
    _init_env
    print_header "ОБНОВЛЕНИЕ КОМПОНЕНТОВ УЗЛА"
    if [ -f "$REMNANODE_DIR/docker-compose.yml" ]; then
        log_info "Обновление образа RemnawaveNode..."
        docker compose --project-directory "$REMNANODE_DIR" pull
        docker compose --project-directory "$REMNANODE_DIR" up -d --remove-orphans
    fi
    if [ -f "$CADDY_DIR/docker-compose.yml" ]; then
        log_info "Обновление образа Caddy Selfsteal..."
        docker compose --project-directory "$CADDY_DIR" pull
        docker compose --project-directory "$CADDY_DIR" up -d --remove-orphans
    fi
    log_success "Все установленные компоненты обновлены."
}

export_config() {
    _init_env
    local output="${1:-/etc/remnanode-install.conf}"
    print_header "ЭКСПОРТ КОНФИГУРАЦИИ ДЛЯ КЛОНИРОВАНИЯ"

    local cfg_secret=""
    if [ -f "$REMNANODE_DIR/.env" ]; then
        cfg_secret=$(grep "^SECRET_KEY=" "$REMNANODE_DIR/.env" 2>/dev/null | cut -d= -f2- || true)
    fi

    umask 077
    cat > "$output" << EOF
# LissVPN Node Orchestrator Configuration
REMNAWAVE_API_URL="${REMNAWAVE_API_URL}"
REMNAWAVE_API_TOKEN="${REMNAWAVE_API_TOKEN}"
NODE_NAME="${NODE_NAME:-$(hostname)}"
NODE_ADDRESS="${NODE_ADDRESS:-$NODE_IP}"
SELF_STEAL_DOMAIN="$(get_saved_caddy_domain)"
SELF_STEAL_PORT=$(get_saved_caddy_port)
CFG_SECRET_KEY="${cfg_secret}"
CFG_NODE_PORT=$(get_saved_node_port)
CFG_PANEL_IP="$(get_saved_panel_ip)"
CFG_APPLY_NETWORK=y
CFG_SETUP_UFW=y
CFG_INSTALL_FAIL2BAN=y
EOF
    chmod 600 "$output"
    umask 022
    log_success "Конфигурация сохранена в $output (права 600)"
}

uninstall_all() {
    _init_env
    print_header "ПОЛНОЕ УДАЛЕНИЕ КОМПОНЕНТОВ УЗЛА"
    read -p "  ${ORANGE}>${NC} Введите 'YES' для подтверждения удаления: " -r confirm
    if [ "$confirm" != "YES" ]; then
        log_info "Отменено."
        return 0
    fi

    if [ -f "$REMNANODE_DIR/docker-compose.yml" ]; then
        docker compose --project-directory "$REMNANODE_DIR" down 2>/dev/null || true
    fi
    if [ -f "$CADDY_DIR/docker-compose.yml" ]; then
        docker compose --project-directory "$CADDY_DIR" down 2>/dev/null || true
    fi
    docker rm -f remnanode "$CADDY_CONTAINER_NAME" caddy-selfsteal 2>/dev/null || true

    run_rollback
    rm -f /etc/fail2ban/jail.local /etc/fail2ban/filter.d/caddy-status.conf
    systemctl restart fail2ban 2>/dev/null || true

    rm -rf "$REMNANODE_DIR" "$REMNANODE_DATA_DIR" "$CADDY_DIR" "$CADDY_HTML_DIR" /var/log/remnanode /etc/logrotate.d/remnanode
    log_success "Все компоненты узла удалены."
}

show_help() {
    print_banner
    cat << 'HELP'

  Использование: node-mgr [КОМАНДА] [ОПЦИИ]

  Основные команды тулкита:
    auto-deploy                  Полное авто-развертывание ноды, xhttp-профиля и хоста по API
    diagnose [-q|--no-net]       Диагностика ноды (27 чеков, дашборд, вердикт)
    optimize [--all|--from-findings|--zram|--sysctl|--rps|--nic|--mss]
                                 Тюнинг ядра, BBR, лимитов FD, RPS/RFS, NIC, TCPMSS, Zram
    bbr3                         Установка ядра XanMod с поддержкой BBRv3
    rollback                     Откат всех наложенных оптимизаций
    status                       Показать состояние узла, контейнеров и артефактов
    logs {node|caddy|f2b}        Просмотр логов RemnaNode, Caddy или Fail2ban в реальном времени
    install                      Установка ноды (с выбором API или ручного режима)
    selective                    Выборочная установка или починка отдельных модулей
    change-template              Смена HTML-шаблона маскировки (/opt/html)
    update                       Обновление Docker-образов RemnaNode и Caddy
    self-update                  Обновление самого скрипта node-mgr из GitHub
    export-config [FILE]         Экспорт текущих настроек в конфиг-файл
    uninstall                    Удаление всех компонентов и откат настроек
    --config FILE                Автоматическая установка по конфиг-файлу

  Переменные окружения для Zero-Touch API деплоя:
    REMNAWAVE_API_URL="https://panel.example.com"
    REMNAWAVE_API_TOKEN="eyJ..."
    NODE_NAME="DE-Frankfurt-01"
    NODE_ADDRESS="84.54.57.173"
    SELF_STEAL_DOMAIN="edge.example.com"
    SELF_STEAL_PORT="9443"
HELP
    echo
}

# ═══════════════════════════════════════════════════════════════════
#  Интерактивное меню
# ═══════════════════════════════════════════════════════════════════
show_main_menu() {
    while true; do
        print_banner
        echo
        echo -e "    ${ORANGE}${BOLD}[1]${NC} ${WHITE}Диагностика ноды${NC}     ${DIM}27 чеков, дашборд, аудит безопасности и вердикт${NC}"
        echo -e "    ${ORANGE}${BOLD}[2]${NC} ${WHITE}Оптимизация стека${NC}    ${DIM}sysctl / BBR / FD / RPS / NIC / TCPMSS / Zram${NC}"
        echo -e "    ${ORANGE}${BOLD}[3]${NC} ${WHITE}Авто-деплой по API${NC}   ${DIM}Нода + Профиль (xhttp) + Хост + Selfsteal + Certs${NC}"
        echo -e "    ${ORANGE}${BOLD}[4]${NC} ${WHITE}Выборочный запуск${NC}    ${DIM}ручная установка или починка отдельных модулей${NC}"
        echo -e "    ${ORANGE}${BOLD}[5]${NC} ${WHITE}Статус системы${NC}       ${DIM}контейнеры, ядро, UFW ACL, наложенные артефакты${NC}"
        echo -e "    ${ORANGE}${BOLD}[6]${NC} ${WHITE}Ядро BBRv3 (XanMod)${NC}  ${DIM}установка ядра XanMod под микроархитектуру CPU${NC}"
        echo -e "    ${ORANGE}${BOLD}[7]${NC} ${WHITE}Сменить шаблон SNI${NC}   ${DIM}быстрая смена HTML-лендинга в /opt/html${NC}"
        echo -e "    ${ORANGE}${BOLD}[8]${NC} ${WHITE}Обновить компоненты${NC}  ${DIM}docker pull + self-update скрипта с GitHub${NC}"
        echo -e "    ${ORANGE}${BOLD}[9]${NC} ${WHITE}Откат / Удаление${NC}     ${DIM}снять оптимизации (rollback) или удалить узел${NC}"
        echo -e "    ${ORANGE}${BOLD}[0]${NC} ${GRAPHITE}Выход${NC}"
        echo
        printf "  ${BOLD}Выбор${NC} ${DIM}[0-9]${NC}: "
        local c=""
        read -r c
        echo

        case "$c" in
            1) run_diagnose ;;
            2)
                echo -e "  ${BOLD}Режим оптимизации:${NC}"
                echo -e "    ${ORANGE}[a]${NC} Применить всё (sysctl + FD + RPS + NIC + MSS + journald)"
                echo -e "    ${ORANGE}[f]${NC} Исправить только найденное диагностикой (--from-findings)"
                echo -e "    ${ORANGE}[z]${NC} Включить сжатый Zram-swap (50% RAM)"
                printf "  ${ORANGE}>${NC} Выбор [Enter=a]: "
                local oc=""
                read -r oc
                case "${oc,,}" in
                    f) run_optimize "--from-findings" ;;
                    z) run_optimize "--zram" ;;
                    *) run_optimize "--all" ;;
                esac
                ;;
            3) run_full_install ;;
            4) run_selective_install ;;
            5) show_status ;;
            6) run_bbr3_xanmod ;;
            7) change_template ;;
            8)
                echo -e "    ${ORANGE}[1]${NC} Обновить контейнеры RemnaNode и Caddy"
                echo -e "    ${ORANGE}[2]${NC} Обновить сам скрипт node-mgr с GitHub (self-update)"
                printf "  ${ORANGE}>${NC} Выбор [Enter=1]: "
                local uc=""
                read -r uc
                if [ "$uc" = "2" ]; then self_update; else update_components; fi
                ;;
            9)
                echo -e "    ${ORANGE}[1]${NC} Откатить только сетевые оптимизации (rollback)"
                echo -e "    ${ORANGE}[2]${NC} Полностью удалить RemnawaveNode, Caddy и конфиги (uninstall)"
                printf "  ${ORANGE}>${NC} Выбор [1-2]: "
                local rc=""
                read -r rc
                if [ "$rc" = "1" ]; then run_rollback; fi
                if [ "$rc" = "2" ]; then uninstall_all; fi
                ;;
            0|q|"")
                log_info "Выход."
                exit 0
                ;;
            *)
                log_warning "Нет такого пункта меню"
                ;;
        esac
        echo
        printf "  ${DIM}Нажмите Enter для возврата в меню...${NC}"
        read -r _
    done
}

# ═══════════════════════════════════════════════════════════════════
#  Диспетчер CLI и точка входа
# ═══════════════════════════════════════════════════════════════════
main() {
    _init_env

    if [ -f "$CONFIG_FILE" ] && [ "${NON_INTERACTIVE:-false}" != true ]; then
        load_config_file "$CONFIG_FILE"
    fi

    # Если переданы переменные API в окружении — сразу запускаем авто-деплой
    if [ -n "${REMNAWAVE_API_URL:-}" ] && [ -n "${REMNAWAVE_API_TOKEN:-}" ] && [ -n "${SELF_STEAL_DOMAIN:-}" ]; then
        NON_INTERACTIVE=true
        run_api_auto_deploy
        return 0
    fi

    if [ "${NON_INTERACTIVE:-false}" = true ]; then
        run_full_install
        return 0
    fi

    if [ -t 0 ]; then
        show_main_menu
    else
        run_diagnose
    fi
}

cmd="${1:-}"
if [ $# -gt 0 ]; then shift; fi

case "$cmd" in
    auto-deploy|--auto-deploy)         run_api_auto_deploy ;;
    diagnose|diag|--diagnose)          run_diagnose "${1:-full}" ;;
    optimize|opt|tune|--optimize)      run_optimize "${1:---all}" ;;
    bbr3|kernel|--bbr3)                run_bbr3_xanmod ;;
    rollback|revert|--rollback)        run_rollback ;;
    status|st|--status)                show_status ;;
    logs|--logs)                       show_logs "${1:-node}" ;;
    install|--install)                 run_full_install ;;
    selective|--selective)             run_selective_install ;;
    change-template|--change-template) change_template ;;
    update|--update)                   update_components ;;
    self-update|--self-update)         self_update ;;
    export-config|--export-config)     export_config "${1:-/etc/remnanode-install.conf}" ;;
    uninstall|--uninstall)             uninstall_all ;;
    --config)
        if [ -n "${1:-}" ] && [ -f "$1" ]; then
            CONFIG_FILE="$1"
            NON_INTERACTIVE=true
            main
        else
            log_error "Укажите существующий файл конфигурации: node-mgr --config /path/to/file"
            exit 1
        fi
        ;;
    menu)                              show_main_menu ;;
    help|-h|--help)                    show_help ;;
    --version|-V)                      echo "node-mgr v${SCRIPT_VERSION}" ;;
    "")                                main ;;
    *)
        log_error "Неизвестная команда: $cmd (используйте: node-mgr --help)"
        exit 2
        ;;
esac
