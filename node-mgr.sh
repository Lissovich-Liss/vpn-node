#!/usr/bin/env bash
# ==============================================================================
#  LissVPN Node Orchestrator & Diagnostic Toolkit v4.0.0 (node-mgr)
#  Repository: https://github.com/Lissovich-Liss/vpn-node
#  Remnawave API Auto-Deploy • Caddy L4 (Vision + XHTTP) • E2E Handshake Probe
#  Kernel Highload + CAKE Shaper • UFW/nftables/Fail2ban • NetBird & Monitoring
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
readonly CYAN=$'\033[38;2;52;152;219m'
readonly NC=$'\033[0m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'

# ═══════════════════════════════════════════════════════════════════
#  Константы, пути и стейт диагностики
# ═══════════════════════════════════════════════════════════════════
readonly SCRIPT_VERSION="4.0.0"
readonly BIN_PATH="/usr/local/bin/node-mgr"
readonly REPO_RAW_URL="https://raw.githubusercontent.com/Lissovich-Liss/vpn-node/main/node-mgr.sh"
readonly INSTALL_LOG="/var/log/remnanode-install.log"

readonly ND_STATE_DIR="/var/lib/node-mgr"
readonly FINDINGS_FILE="${ND_STATE_DIR}/findings.env"
readonly FIX_LOG="${ND_STATE_DIR}/applied-fixes.log"
readonly API_STATE_FILE="${ND_STATE_DIR}/remnawave-api.env"
readonly PROTECT_OUT_DIR="${ND_STATE_DIR}/protect"
readonly ND_DROPIN_PREFIX="99-lissvpn"
readonly ND_BOX_W=70

readonly INSTALL_DIR="/opt"
readonly REMNANODE_DIR="${INSTALL_DIR}/remnanode"
readonly REMNANODE_DATA_DIR="/var/lib/remnanode"
readonly CADDY_DIR="${INSTALL_DIR}/selfsteel"
readonly CADDY_HTML_DIR="${INSTALL_DIR}/html"
readonly MONITORING_DIR="${INSTALL_DIR}/monitoring"
readonly CADDY_CONTAINER_NAME="caddy-remnawave"
readonly CADDY_DATA_VOL="selfsteel_caddy_data_selfsteal"
readonly CADDY_CONFIG_VOL="selfsteel_caddy_config_selfsteal"
readonly DEFAULT_PORT="9443"
readonly DEFAULT_VISION_PORT="10443"
readonly DEFAULT_XHTTP_PORT="10444"
readonly DEFAULT_XHTTP_PATH="/api/v3/sync/r1"

CADVISOR_VERSION="0.53.0"
NODE_EXPORTER_VERSION="1.9.1"
VMAGENT_VERSION="1.123.0"

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

# Переменные для API-автоматизации Remnawave и L4 Multi-Protocol
REMNAWAVE_API_URL="${REMNAWAVE_API_URL:-}"
REMNAWAVE_API_TOKEN="${REMNAWAVE_API_TOKEN:-}"
NODE_NAME="${NODE_NAME:-}"
NODE_ADDRESS="${NODE_ADDRESS:-}"
SELF_STEAL_DOMAIN="${SELF_STEAL_DOMAIN:-}"
XHTTP_STEAL_DOMAIN="${XHTTP_STEAL_DOMAIN:-}"
XHTTP_PATH="${XHTTP_PATH:-$DEFAULT_XHTTP_PATH}"
SELF_STEAL_PORT="${SELF_STEAL_PORT:-$DEFAULT_PORT}"
VISION_INBOUND_PORT="${VISION_INBOUND_PORT:-$DEFAULT_VISION_PORT}"
XHTTP_INBOUND_PORT="${XHTTP_INBOUND_PORT:-$DEFAULT_XHTTP_PORT}"

# Классические CFG_* переменные (совместимость)
CFG_SECRET_KEY="${CFG_SECRET_KEY:-}"
CFG_NODE_PORT="${CFG_NODE_PORT:-3000}"
CFG_PANEL_IP="${CFG_PANEL_IP:-}"
CFG_INSTALL_XRAY="${CFG_INSTALL_XRAY:-y}"
CFG_DOMAIN="${CFG_DOMAIN:-}"
CFG_CERT_TYPE="${CFG_CERT_TYPE:-1}"
CFG_CLOUDFLARE_TOKEN="${CFG_CLOUDFLARE_TOKEN:-}"
CFG_CADDY_PORT="${CFG_CADDY_PORT:-$DEFAULT_PORT}"
CFG_APPLY_NETWORK="${CFG_APPLY_NETWORK:-y}"
CFG_SETUP_UFW="${CFG_SETUP_UFW:-y}"
CFG_INSTALL_FAIL2BAN="${CFG_INSTALL_FAIL2BAN:-y}"
CFG_INSTALL_NETBIRD="${CFG_INSTALL_NETBIRD:-n}"
CFG_NETBIRD_SETUP_KEY="${CFG_NETBIRD_SETUP_KEY:-}"
CFG_INSTALL_MONITORING="${CFG_INSTALL_MONITORING:-n}"
CFG_INSTANCE_NAME="${CFG_INSTANCE_NAME:-}"
CFG_GRAFANA_IP="${CFG_GRAFANA_IP:-}"

STATUS_NETWORK="пропущен"
STATUS_DOCKER="пропущен"
STATUS_CADDY="пропущен"
STATUS_API="пропущен"
STATUS_REMNANODE="пропущен"
STATUS_UFW="пропущен"
STATUS_FAIL2BAN="пропущен"
STATUS_NETBIRD="пропущен"
STATUS_MONITORING="пропущен"

DETAIL_REMNANODE_PORT=""
DETAIL_PANEL_IP=""
DETAIL_CADDY_DOMAIN=""
DETAIL_XHTTP_DOMAIN=""
DETAIL_CADDY_PORT=""
DETAIL_NODE_UUID=""
DETAIL_PROFILE_UUID=""
DETAIL_HOST_UUID=""
DETAIL_XHTTP_HOST_UUID=""
DETAIL_NETBIRD_IP=""
DETAIL_GRAFANA_IP=""
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
    local pad=$(( ND_BOX_W - tlen - 4 ))
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
    printf "  %s│%s  ${SLATE}%-24s${NC} %b\n" "${GRAPHITE}" "${NC}" "${key}:" "${WHITE}${val}${NC}"
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
    local cc qdisc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "?")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "?")
    echo
    echo -e "  ${ORANGE}${BOLD}🦊 LISSVPN NODE ORCHESTRATOR${NC}  ${GRAPHITE}v${SCRIPT_VERSION} · L4 Multi-Protocol Toolkit${NC}"
    ui_rule "━"
    echo -e "  ${GRAPHITE}$(date -u +'%Y-%m-%d %H:%M UTC') · ${WHITE}$(hostname)${GRAPHITE} · $(detect_virt) · TCP: ${ORANGE}${cc}+${qdisc}${GRAPHITE} · IP: ${WHITE}${NODE_IP:-...}${NC}"
}

print_live_statusbar() {
    local rn_pill cd_pill ufw_pill f2b_pill nb_pill
    if is_container_running "remnanode"; then
        rn_pill="${GREEN}${BOLD}●${NC} ${WHITE}RemnaNode${NC}"
    else
        rn_pill="${GRAPHITE}○ RemnaNode${NC}"
    fi
    if is_caddy_running; then
        cd_pill="${GREEN}${BOLD}●${NC} ${WHITE}Caddy L4${NC}"
    else
        cd_pill="${GRAPHITE}○ Caddy L4${NC}"
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
        ufw_pill="${GREEN}${BOLD}●${NC} ${WHITE}UFW${NC}"
    else
        ufw_pill="${YELLOW}○ UFW${NC}"
    fi
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        f2b_pill="${GREEN}${BOLD}●${NC} ${WHITE}Fail2ban${NC}"
    else
        f2b_pill="${YELLOW}○ Fail2ban${NC}"
    fi
    local nb_ip=""
    nb_ip=$(ip -4 addr show wt0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || true)
    if [ -n "$nb_ip" ]; then
        nb_pill="${GREEN}${BOLD}●${NC} ${WHITE}NetBird (${nb_ip})${NC}"
    else
        nb_pill="${GRAPHITE}○ NetBird${NC}"
    fi
    echo -e "  ${rn_pill}   ${cd_pill}   ${ufw_pill}   ${f2b_pill}   ${nb_pill}"
    ui_rule "─"
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
    local cdom="${DETAIL_CADDY_DOMAIN:-${SELF_STEAL_DOMAIN:-}}"
    if [ -z "$cdom" ] && [ -f "$CADDY_DIR/.env" ]; then
        cdom=$(grep -E '^SELF_STEAL_DOMAIN=' "$CADDY_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    if [ -z "$cdom" ] && [ -f "/opt/caddy/.env" ]; then
        cdom=$(grep -E '^SELF_STEAL_DOMAIN=' "/opt/caddy/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    echo "$cdom"
}

get_saved_xhttp_domain() {
    local xdom="${DETAIL_XHTTP_DOMAIN:-${XHTTP_STEAL_DOMAIN:-}}"
    if [ -z "$xdom" ] && [ -f "$CADDY_DIR/.env" ]; then
        xdom=$(grep -E '^XHTTP_STEAL_DOMAIN=' "$CADDY_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    if [ -z "$xdom" ] && [ -f "$API_STATE_FILE" ]; then
        xdom=$(grep -E '^XHTTP_STEAL_DOMAIN=' "$API_STATE_FILE" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    echo "$xdom"
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
        for f in "$dir"/.env "$dir"/docker-compose.yml "$dir"/Caddyfile "$dir"/Dockerfile; do
            if [ -f "$f" ]; then cp -f "$f" "$backup_dir/" 2>/dev/null || true; fi
        done
        chmod 700 "$backup_dir"
        log_info "Бэкап сохранен: $backup_dir"
    fi
}

load_config_file() {
    local config_file="${1:-$CONFIG_FILE}"
    if [ -f "$config_file" ]; then
        local file_owner file_perms
        file_owner=$(stat -c '%U' "$config_file" 2>/dev/null || echo "root")
        file_perms=$(stat -c '%a' "$config_file" 2>/dev/null || echo "600")
        if [ "$file_owner" != "root" ]; then
            log_warning "Конфиг-файл $config_file принадлежит $file_owner (рекомендуется root)"
        fi
        if [[ "$file_perms" =~ [0-7][2367][0-7] ]]; then
            log_warning "Конфиг-файл $config_file доступен на запись группе/другим (права: $file_perms)"
        fi
        log_info "Загрузка конфигурации из $config_file"
        local _allowed_vars="REMNAWAVE_API_URL REMNAWAVE_API_TOKEN NODE_NAME NODE_ADDRESS SELF_STEAL_DOMAIN XHTTP_STEAL_DOMAIN XHTTP_PATH SELF_STEAL_PORT VISION_INBOUND_PORT XHTTP_INBOUND_PORT CFG_SECRET_KEY CFG_NODE_PORT CFG_PANEL_IP CFG_INSTALL_XRAY CFG_DOMAIN CFG_CERT_TYPE CFG_CLOUDFLARE_TOKEN CFG_CADDY_PORT CFG_APPLY_NETWORK CFG_SETUP_UFW CFG_INSTALL_FAIL2BAN CFG_INSTALL_NETBIRD CFG_NETBIRD_SETUP_KEY CFG_INSTALL_MONITORING CFG_INSTANCE_NAME CFG_GRAFANA_IP NON_INTERACTIVE"
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

validate_cloudflare_token() {
    local token="$1"
    log_info "Проверка Cloudflare API Token через Cloudflare API..."
    local response
    response=$(curl -s --connect-timeout 8 --max-time 12 \
        -H "Authorization: Bearer $token" \
        "https://api.cloudflare.com/client/v4/user/tokens/verify" 2>/dev/null) || true
    if echo "$response" | grep -q '"success":true'; then
        log_success "Cloudflare API Token валиден"
        return 0
    else
        local error_msg
        error_msg=$(echo "$response" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p' | head -1)
        log_error "Cloudflare API Token невалиден${error_msg:+: $error_msg}"
        return 1
    fi
}

validate_domain_dns() {
    local domain="${1#\*.}"
    local server_ip="${2:-$NODE_IP}"
    log_info "Проверка DNS A-записи для ${domain}..."
    local dns_ip=""
    if command -v dig >/dev/null 2>&1; then
        dns_ip=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -1 || true)
    fi
    if [ -z "$dns_ip" ]; then
        dns_ip=$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1; exit}' || true)
    fi
    if [ -z "$dns_ip" ]; then
        log_warning "Не удалось получить IPv4 для домена ${domain}"
        return 1
    fi
    if [ "$dns_ip" != "$server_ip" ]; then
        log_warning "DNS не совпадает: ${domain} -> ${dns_ip}, а IP этого сервера: ${server_ip}"
        return 1
    fi
    log_success "DNS настроен корректно: ${domain} -> ${dns_ip}"
    return 0
}

fetch_latest_version() {
    local repo="$1"
    local default="$2"
    local version="" api_response=""
    api_response=$(curl -s --connect-timeout 5 --max-time 10 \
        "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null) || true
    if [ -n "$api_response" ]; then
        if command -v jq >/dev/null 2>&1; then
            version=$(echo "$api_response" | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//')
        else
            version=$(echo "$api_response" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1 | sed 's/^v//')
        fi
    fi
    echo "${version:-$default}"
}

fetch_latest_vmagent_version() {
    local default="$1"
    local version="" api_response=""
    api_response=$(curl -s --connect-timeout 5 --max-time 15 \
        "https://api.github.com/repos/VictoriaMetrics/VictoriaMetrics/releases?per_page=15" 2>/dev/null) || true
    if [ -n "$api_response" ] && command -v jq >/dev/null 2>&1; then
        version=$(echo "$api_response" | jq -r '
            [.[] | select(.assets[]?.name | test("^vmutils-linux-.*\\.tar\\.gz$") and (test("enterprise") | not))][0].tag_name // empty
        ' 2>/dev/null | sed 's/^v//')
    fi
    echo "${version:-$default}"
}

update_component_versions() {
    local new_ver
    new_ver=$(fetch_latest_version "google/cadvisor" "$CADVISOR_VERSION")
    [ -n "$new_ver" ] && CADVISOR_VERSION="$new_ver"
    new_ver=$(fetch_latest_version "prometheus/node_exporter" "$NODE_EXPORTER_VERSION")
    [ -n "$new_ver" ] && NODE_EXPORTER_VERSION="$new_ver"
    new_ver=$(fetch_latest_vmagent_version "$VMAGENT_VERSION")
    [ -n "$new_ver" ] && VMAGENT_VERSION="$new_ver"
}

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}" o3="${BASH_REMATCH[3]}" o4="${BASH_REMATCH[4]}"
        if [ "$o1" -le 255 ] && [ "$o2" -le 255 ] && [ "$o3" -le 255 ] && [ "$o4" -le 255 ]; then
            return 0
        fi
    fi
    return 1
}

validate_setup_key() {
    local key="$1"
    if [[ "$key" =~ ^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$ ]] || [[ "${#key}" -ge 16 ]]; then
        return 0
    fi
    log_warning "Неверный формат Setup Key (ожидается UUID вида XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX)"
    return 1
}

validate_instance_name() {
    local name="$1"
    if [[ "$name" =~ ^[a-zA-Z0-9_.-]{1,64}$ ]]; then
        return 0
    fi
    log_warning "Имя инстанса должно содержать только буквы, цифры, дефис, точку или подчеркивание (1..64 симв.)"
    return 1
}

check_existing_netbird() {
    if ! command -v netbird >/dev/null 2>&1; then
        return 1
    fi
    local nb_ip=""
    nb_ip=$(ip -4 addr show wt0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || true)
    if [ -n "$nb_ip" ]; then
        DETAIL_NETBIRD_IP="$nb_ip"
        return 0
    fi
    if netbird status 2>/dev/null | grep -qi "Connected"; then
        return 0
    fi
    return 2
}

check_existing_monitoring() {
    if [ -d "$MONITORING_DIR" ] && [ -f "$MONITORING_DIR/docker-compose.yml" ]; then
        local g_ip=""
        g_ip=$(grep -oE 'remoteWrite\.url=http://[0-9.]+' "$MONITORING_DIR/docker-compose.yml" 2>/dev/null | sed 's|.*http://||' | head -1 || true)
        [ -n "$g_ip" ] && DETAIL_GRAFANA_IP="$g_ip"
        if is_container_running "vmagent" || is_container_running "node-exporter"; then
            return 0
        fi
    fi
    return 1
}

# ═══════════════════════════════════════════════════════════════════
#  МОДУЛЬ 1: ДИАГНОСТИКА НОДЫ (33 чека, дашборд, findings, JSON, вердикт)
# ═══════════════════════════════════════════════════════════════════
run_diagnose() {
    _init_env
    local mode="${1:-full}"
    local emit_json_mode=false
    if [ "$mode" = "--json" ]; then
        emit_json_mode=true
        exec 3>&1 1>>"$INSTALL_LOG" 2>&1
    fi
    local pass_cnt=0 warn_cnt=0 fail_cnt=0
    local summary_txt="/tmp/node-diagnostic-summary-$(date +%Y%m%d-%H%M%S).txt"
    : > "$summary_txt" 2>/dev/null || true

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

    _chk_ok()   { pass_cnt=$((pass_cnt + 1)); echo "[PASS] $1: $2" >> "$summary_txt" 2>/dev/null || true; box_row "${GREEN}${BOLD}[ PASS ]${NC} $(printf '%-26s' "$1") ${SLATE}$2${NC}"; }
    _chk_warn() { warn_cnt=$((warn_cnt + 1)); echo "[WARN] $1: $2" >> "$summary_txt" 2>/dev/null || true; box_row "${YELLOW}${BOLD}[ WARN ]${NC} $(printf '%-26s' "$1") ${YELLOW}$2${NC}"; }
    _chk_fail() { fail_cnt=$((fail_cnt + 1)); echo "[FAIL] $1: $2" >> "$summary_txt" 2>/dev/null || true; box_row "${RED}${BOLD}[ FAIL ]${NC} $(printf '%-26s' "$1") ${RED}$2${NC}"; }

    print_banner
    echo

    # ── Блок 1: Аппаратные ресурсы и ОС (Чеки 1-5) ─────────────────
    box_top "1/6 · СИСТЕМА И РЕСУРСЫ (ЧЕКИ 1–5)"

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
    box_top "2/6 · СЕТЕВОЙ СТЕК ЯДРА И SYSCTL (ЧЕКИ 6–13)"

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
    box_top "3/6 · СЕТЕВАЯ КАРТА, RPS, MSS И СИСТЕМНЫЕ СЛУЖБЫ (ЧЕКИ 14–18)"
    local iface
    iface=$(detect_default_iface)

    local rps_val=""
    if [ -n "$iface" ] && [ -r "/sys/class/net/${iface}/queues/rx-0/rps_cpus" ]; then
        rps_val=$(tr -d '0,\n ' < "/sys/class/net/${iface}/queues/rx-0/rps_cpus" 2>/dev/null || true)
    fi
    if [ "$cores" -le 1 ] || [ -n "$rps_val" ]; then
        _chk_ok "14. Балансировка RPS/XPS" "Активна на интерфейсе ${iface:-?}"
    else
        _chk_warn "14. Балансировка RPS/XPS" "RPS выключен на ${iface:-eth0} (сеть на 1 ядре)"
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

    if command -v iptables >/dev/null 2>&1 \
       && iptables -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null \
       && iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
        _chk_ok "16. TCPMSS Clamp to PMTU" "Правила mangle OUTPUT + FORWARD активны"
    else
        _chk_warn "16. TCPMSS Clamp to PMTU" "Не активно на OUTPUT/FORWARD (возможен PMTU blackhole)"
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

    # ── Блок 4: Контейнеры RemnawaveNode и Caddy Selfsteal L4 (19-23) ─
    box_top "4/6 · DOCKER, REMNANODE И CADDY L4 SELFSTEAL (ЧЕКИ 19–23)"
    local node_port caddy_port caddy_domain xhttp_domain
    node_port=$(get_saved_node_port)
    caddy_port=$(get_saved_caddy_port)
    caddy_domain=$(get_saved_caddy_domain)
    xhttp_domain=$(get_saved_xhttp_domain)
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
        _chk_ok "21. Контейнер Caddy L4" "Запущен (Vision: ${caddy_domain:-?} | XHTTP: ${xhttp_domain:-?})"
    else
        _chk_fail "21. Контейнер Caddy L4" "Не установлен или остановлен"
    fi

    if awk '{print $4}' <<< "$ss_listening" | grep -q "^127\.0\.0\.1:${caddy_port}$"; then
        _chk_ok "22. Изоляция Selfsteal сокета" "Слушает строго на 127.0.0.1:${caddy_port} (L4 на :443)"
    elif grep -qE ":${caddy_port}[[:space:]]" <<< "$ss_listening"; then
        _chk_fail "22. Изоляция Selfsteal сокета" "УТЕЧКА: порт ${caddy_port} слушает публично!"
    else
        _chk_warn "22. Изоляция Selfsteal сокета" "Порт 127.0.0.1:${caddy_port} не прослушивается"
    fi

    if is_caddy_running && [ -n "$caddy_domain" ]; then
        local clean_dom="${caddy_domain#\*.}"
        local clean_xdom="${xhttp_domain#\*.}"
        local active_cname="$CADDY_CONTAINER_NAME"
        if ! is_container_running "$active_cname"; then active_cname="caddy-selfsteal"; fi
        local cert_v="" cert_x=""
        cert_v=$(docker exec "$active_cname" sh -c "find /data/caddy/certificates -type f -name '*${clean_dom}*.crt' 2>/dev/null | head -1" 2>/dev/null || true)
        if [ -n "$clean_xdom" ]; then
            cert_x=$(docker exec "$active_cname" sh -c "find /data/caddy/certificates -type f -name '*${clean_xdom}*.crt' 2>/dev/null | head -1" 2>/dev/null || true)
        fi
        if [ -n "$cert_v" ] && { [ -z "$clean_xdom" ] || [ -n "$cert_x" ]; }; then
            _chk_ok "23. TLS-сертификаты маскировки" "Выпущены (${clean_dom}${clean_xdom:+, $clean_xdom})"
        elif [ -n "$cert_v" ]; then
            _chk_warn "23. TLS-сертификаты маскировки" "Выпущен ${clean_dom}, ожидается ${clean_xdom}"
        else
            _chk_warn "23. TLS-сертификаты маскировки" "Сертификаты для ${clean_dom} еще не получены"
        fi
    else
        _chk_warn "23. TLS-сертификаты маскировки" "Контейнер Caddy или домен не активен"
    fi
    box_bottom
    echo

    # ── Блок 5: Периметр безопасности и связность (Чеки 24-27) ────
    box_top "5/6 · ЗАЩИТА ПЕРИМЕТРА И СВЯЗНОСТЬ (ЧЕКИ 24–27)"
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

    # ── Блок 6: Углубленный аудит ядра, сокетов, портов и репутации (Чеки 28-33) ─
    box_top "6/6 · PSI, UDP-БУФЕРЫ, MSS-КОЛЛАПС, ПОРТЫ И РЕПУТАЦИЯ (ЧЕКИ 28–33)"

    # 28. PSI (/proc/pressure)
    if [ -d /proc/pressure ]; then
        local psi_cpu="0.00" psi_mem="0.00" psi_io="0.00"
        [ -r /proc/pressure/cpu ]    && psi_cpu=$(awk '/^some/{for(i=1;i<=NF;i++)if($i~/^avg10=/){sub("avg10=","",$i);print $i;exit}}' /proc/pressure/cpu 2>/dev/null || echo "0.00")
        [ -r /proc/pressure/memory ] && psi_mem=$(awk '/^some/{for(i=1;i<=NF;i++)if($i~/^avg10=/){sub("avg10=","",$i);print $i;exit}}' /proc/pressure/memory 2>/dev/null || echo "0.00")
        [ -r /proc/pressure/io ]     && psi_io=$(awk '/^some/{for(i=1;i<=NF;i++)if($i~/^avg10=/){sub("avg10=","",$i);print $i;exit}}' /proc/pressure/io 2>/dev/null || echo "0.00")
        if awk -v c="${psi_cpu:-0}" -v m="${psi_mem:-0}" -v io="${psi_io:-0}" 'BEGIN{exit !(c<10 && m<10 && io<10)}'; then
            _chk_ok "28. PSI Давление ресурсов" "avg10: cpu=${psi_cpu}% mem=${psi_mem}% io=${psi_io}%"
        else
            _chk_warn "28. PSI Давление ресурсов" "Высокое ожидание PSI: cpu=${psi_cpu}% mem=${psi_mem}% io=${psi_io}%"
        fi
    else
        _chk_ok "28. PSI Давление ресурсов" "Пропущено (CONFIG_PSI не активен)"
    fi

    # 29. UDP RcvbufErrors / SndbufErrors (/proc/net/snmp)
    local udp_rcv_err=0 udp_snd_err=0
    if [ -r /proc/net/snmp ]; then
        while IFS='=' read -r uk uv; do
            case "$uk" in
                RcvbufErrors) udp_rcv_err="${uv:-0}" ;;
                SndbufErrors) udp_snd_err="${uv:-0}" ;;
            esac
        done < <(awk '/^Udp:/{if(!h){for(i=2;i<=NF;i++)n[i]=$i;h=1;next} for(i=2;i<=NF;i++)printf "%s=%d\n",n[i],$i}' /proc/net/snmp 2>/dev/null)
    fi
    if [ "${udp_rcv_err:-0}" -le 1000 ]; then
        _chk_ok "29. Ошибки буферов UDP/QUIC" "RcvbufErrors=${udp_rcv_err}, SndbufErrors=${udp_snd_err}"
    else
        _chk_warn "29. Ошибки буферов UDP/QUIC" "Дропы UDP буфера: RcvbufErrors=${udp_rcv_err} (нужен тюнинг sysctl)"
        _mark_finding "NEED_SYSCTL"
    fi

    # 30. Живые сокеты: MSS-коллапс (<256) и переполнение Accept-Queue
    local mss_low=0 full_q=""
    if command -v ss >/dev/null 2>&1; then
        mss_low=$(ss -tin 2>/dev/null | grep -oE 'mss:[0-9]+' | awk -F: '$2<256{c++} END{print c+0}')
        full_q=$(ss -tlnH 2>/dev/null | awk '$1=="LISTEN" && $3+0>0 && $2+0>=$3+0 {print $4}' | head -3 | tr '\n' ' ')
    fi
    if [ "${mss_low:-0}" -eq 0 ] && [ -z "$full_q" ]; then
        _chk_ok "30. Живые сокеты (MSS/Queue)" "Коллапсов MSS<256 нет, Accept-Queue в норме"
    else
        _chk_warn "30. Живые сокеты (MSS/Queue)" "MSS<256: ${mss_low} сок.${full_q:+ | Переполнена очередь: $full_q}"
        _mark_finding "NEED_SYSCTL"
        _mark_finding "NEED_MSS"
    fi

    # 31. Туннели, NetBird и стек мониторинга (VictoriaMetrics/NodeExporter/cAdvisor)
    local tun_info=()
    if check_existing_netbird; then
        if netbird status 2>/dev/null | grep -qi "connected"; then
            local nb_ip
            nb_ip=$(ip -4 addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
            tun_info+=("NetBird:OK(${nb_ip:-wt0})")
        else
            tun_info+=("NetBird:WARN(disconnected)")
        fi
    fi
    if check_existing_monitoring; then
        if systemctl is-active --quiet vmagent 2>/dev/null && systemctl is-active --quiet nodeexporter 2>/dev/null; then
            tun_info+=("Monitoring:OK(vmagent+exporters)")
        else
            tun_info+=("Monitoring:WARN(stopped)")
        fi
    fi
    if [ ${#tun_info[@]} -eq 0 ]; then
        _chk_ok "31. Агенты NetBird & Метрики" "Не установлены (опциональные модули)"
    elif [[ "${tun_info[*]}" == *"WARN"* ]]; then
        _chk_warn "31. Агенты NetBird & Метрики" "${tun_info[*]}"
    else
        _chk_ok "31. Агенты NetBird & Метрики" "${tun_info[*]}"
    fi

    # 32. Аудит публично открытых портов (0.0.0.0 / [::])
    local danger_ports="" extra_ports="" ssh_p_cur
    ssh_p_cur=$(detect_ssh_port)
    if command -v ss >/dev/null 2>&1; then
        local pub_ports
        pub_ports=$(ss -tulnp 2>/dev/null | tail -n +2 | awk '
            $5 ~ /^(0\.0\.0\.0|\[::\]|\*):[0-9]+$/ {
                p=$5; sub(/.*:/,"",p); print p
            }' | sort -u -n)
        local p_item
        for p_item in $pub_ports; do
            case "$p_item" in
                80|443|"$ssh_p_cur"|"$node_port"|51820) ;;
                2375|2376|5432|3306|6379|27017|9200) danger_ports="${danger_ports}${p_item} " ;;
                *) extra_ports="${extra_ports}${p_item} " ;;
            esac
        done
    fi
    if [ -n "$danger_ports" ]; then
        _chk_fail "32. Аудит открытых портов" "ОПАСНЫЕ ПОРТЫ НАРУЖУ: ${danger_ports}(закройте через UFW/protect!)"
        _mark_finding "NEED_UFW_FIX"
    elif [ -n "$extra_ports" ]; then
        _chk_warn "32. Аудит открытых портов" "Нестандартные внешние порты: ${extra_ports}"
    else
        _chk_ok "32. Аудит открытых портов" "Слушают только штатные порты (80, 443, SSH, Node)"
    fi

    # 33. IP-репутация, Cloudflare Trace и доступность сервисов (YouTube / Google / ChatGPT / Gemini)
    if [ "$mode" != "--no-net" ] && [ "$mode" != "-q" ]; then
        local cf_trace cf_colo="?" cf_loc="?" g_code="000" yt_code="000" ai_code="000"
        cf_trace=$(curl -4 -sS --connect-timeout 4 --max-time 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
        if [ -n "$cf_trace" ]; then
            cf_colo=$(awk -F= '/^colo=/{print $2}' <<< "$cf_trace")
            cf_loc=$(awk -F= '/^loc=/{print $2}' <<< "$cf_trace")
        fi
        yt_code=$(curl -4 -sS -o /dev/null --connect-timeout 4 --max-time 6 -w "%{http_code}" "https://www.youtube.com/" 2>/dev/null || echo "000")
        g_code=$(curl -4 -sS -o /dev/null --connect-timeout 4 --max-time 6 -w "%{http_code}" "https://www.google.com/generate_204" 2>/dev/null || echo "000")
        ai_code=$(curl -4 -sS -o /dev/null --connect-timeout 4 --max-time 6 -w "%{http_code}" "https://chatgpt.com/" 2>/dev/null || echo "000")
        if [[ "$yt_code" =~ ^(200|301|302)$ ]] && [[ "$g_code" =~ ^(200|204)$ ]]; then
            _chk_ok "33. Репутация IP и Сервисы" "CF=${cf_colo}/${cf_loc} | YouTube=${yt_code} | Google=${g_code} | ChatGPT=${ai_code}"
        else
            _chk_warn "33. Репутация IP и Сервисы" "CF=${cf_colo}/${cf_loc} | YouTube=${yt_code} | Google=${g_code} | ChatGPT=${ai_code}"
        fi
    else
        _chk_ok "33. Репутация IP и Сервисы" "Пропущено (${mode})"
    fi
    box_bottom
    echo

    local score=$(( 100 - fail_cnt * 12 - warn_cnt * 4 ))
    [ "$score" -lt 0 ] && score=0

    box_top "ВЕРДИКТ ДИАГНОСТИКИ (33 ЧЕКА · ОЦЕНКА: ${score}/100)"
    box_row "Успешно: ${GREEN}${BOLD}${pass_cnt}${NC}   |   Предупреждений: ${YELLOW}${BOLD}${warn_cnt}${NC}   |   Ошибок: ${RED}${BOLD}${fail_cnt}${NC}   |   Сводка: ${DIM}${summary_txt}${NC}"
    if [ $fail_cnt -eq 0 ] && [ $warn_cnt -eq 0 ]; then
        box_row "${GREEN}${BOLD}Идеальное состояние! Узел полностью оптимизирован и защищен.${NC}"
    else
        box_row "${SLATE}Для авто-исправления находок запустите: ${ORANGE}${BOLD}node-mgr optimize --from-findings${NC}"
        box_row "${SLATE}Для полного профиля оптимизации:       ${ORANGE}${BOLD}node-mgr optimize --all${NC}"
        box_row "${SLATE}Для генерации nftables/SSH защиты:     ${ORANGE}${BOLD}node-mgr protect${NC}"
    fi
    box_bottom
    echo

    if [ "$emit_json_mode" = true ]; then
        exec 1>&3
        printf '{"version":"%s","host":"%s","ip":"%s","ts":"%s","score":%d,"pass":%d,"warn":%d,"fail":%d,"summary_file":"%s"}\n' \
            "$SCRIPT_VERSION" "$(hostname 2>/dev/null || echo node)" "${NODE_IP:-0.0.0.0}" \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$score" "$pass_cnt" "$warn_cnt" "$fail_cnt" "$summary_txt"
    fi
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

    local QDISC_ALGO="fq"
    if modprobe sch_cake 2>/dev/null || [ -d /sys/module/sch_cake ]; then
        QDISC_ALGO="cake"
    fi

    modprobe nf_conntrack 2>/dev/null || true
    mkdir -p /etc/modules-load.d /etc/modprobe.d
    {
        echo "nf_conntrack"
        [ "$QDISC_ALGO" = "cake" ] && echo "sch_cake"
    } > "/etc/modules-load.d/${ND_DROPIN_PREFIX}.conf"
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

net.core.default_qdisc = ${QDISC_ALGO}
net.ipv4.tcp_congestion_control = ${BBR_ALGO}
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_ecn = 2

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
net.ipv4.tcp_min_snd_mss = 512
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

net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.src_valid_mark = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
vm.swappiness = 10
vm.overcommit_memory = 1
EOF

    sysctl --system >/dev/null 2>&1 || true
    _log_fix "sysctl profile applied (${profile_tier}, ${BBR_ALGO}+${QDISC_ALGO}, conntrack=${conntrack_max})"
    log_success "Профиль sysctl применен (${profile_tier}, ${BBR_ALGO}+${QDISC_ALGO})"
}

opt_limits() {
    log_info "Настройка системных лимитов дескрипторов (PAM & Systemd)..."
    mkdir -p /etc/security/limits.d /etc/systemd/system.conf.d /etc/systemd/user.conf.d
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
DefaultLimitNPROC=1048576
EOF
    cp -f "/etc/systemd/system.conf.d/${ND_DROPIN_PREFIX}-limits.conf" "/etc/systemd/user.conf.d/${ND_DROPIN_PREFIX}-limits.conf" 2>/dev/null || true
    ulimit -n 1048576 2>/dev/null || true
    systemctl daemon-reexec 2>/dev/null || true
    _log_fix "FD limits set to 1048576 (PAM + systemd system/user)"
    log_success "Лимиты файловых дескрипторов установлены (1048576)"
}

opt_rps() {
    log_info "Настройка Receive/Transmit Packet Steering (RPS/RFS/XPS) по всем ядрам CPU..."
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
    if [ -d "${rx_queues[0]}" ]; then
        rx_cnt=${#rx_queues[@]}
        flow_cnt=$(( entries / rx_cnt ))
        for q in "${rx_queues[@]}"; do
            echo "$mask" > "$q/rps_cpus" 2>/dev/null || true
            echo "$flow_cnt" > "$q/rps_flow_cnt" 2>/dev/null || true
        done
    fi
    tx_queues=( "${iface_dir}/queues/tx-"* )
    if [ -d "${tx_queues[0]}" ]; then
        for tq in "${tx_queues[@]}"; do
            [ -w "$tq/xps_cpus" ] && echo "$mask" > "$tq/xps_cpus" 2>/dev/null || true
        done
    fi
done
EOF
    chmod 755 /usr/local/sbin/node-mgr-rps
    /usr/local/sbin/node-mgr-rps || true

    cat > /etc/systemd/system/node-diagnostic-rps.service << 'EOF'
[Unit]
Description=LissVPN RPS/RFS/XPS Multi-Queue Packet Steering
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
    _log_fix "RPS/RFS/XPS packet steering enabled"
    log_success "RPS/RFS/XPS распределение пакетов по ядрам активировано"
}

opt_nic() {
    log_info "Тюнинг сетевой карты (GRO/GSO/TSO on, LRO off, txqueuelen 10000 & TCPMSS)..."
    if ! command -v ethtool >/dev/null 2>&1; then
        install_package ethtool >/dev/null 2>&1 || true
    fi
    cat > /usr/local/sbin/node-mgr-nic << 'EOF'
#!/usr/bin/env bash
iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
if [ -n "$iface" ]; then
    ip link set dev "$iface" txqueuelen 10000 2>/dev/null || true
    if command -v ethtool >/dev/null 2>&1; then
        ethtool -K "$iface" gro on gso on tso on lro off 2>/dev/null || true
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
    _log_fix "NIC offloads (GRO/GSO/TSO on, LRO off), txqueuelen=10000 & TCPMSS applied"
    log_success "Аппаратные оффлоады NIC (LRO off), txqueuelen=10000 и TCPMSS настроены"
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

opt_shaper() {
    local bw_mbit="${1:-}"
    local def_if
    def_if=$(detect_default_iface)
    if [ -z "$def_if" ]; then
        log_error "Не удалось определить основной сетевой интерфейс для шейпинга"
        return 1
    fi

    if [ -z "$bw_mbit" ] && [ "${NON_INTERACTIVE:-false}" != true ]; then
        local link_spd=""
        link_spd=$(cat "/sys/class/net/${def_if}/speed" 2>/dev/null || echo "")
        local def_bw="950"
        if [[ "$link_spd" =~ ^[0-9]+$ ]] && [ "$link_spd" -gt 10 ] && [ "$link_spd" -le 25000 ]; then
            def_bw=$(( link_spd * 95 / 100 ))
        fi
        read -p "  ${ORANGE}>${NC} Лимит канала для CAKE Fair Queueing в Мбит/с (95% от порта VPS) [${def_bw}]: " -r bw_mbit
        bw_mbit="${bw_mbit:-$def_bw}"
    fi
    bw_mbit="${bw_mbit:-950}"
    if ! [[ "$bw_mbit" =~ ^[0-9]+$ ]] || [ "$bw_mbit" -lt 10 ]; then
        bw_mbit=950
    fi

    log_info "Настройка Smart Traffic Shaper (CAKE dual-srchost / fq_codel) на ${def_if} (${bw_mbit} Mbit/s)..."
    modprobe sch_cake 2>/dev/null || true

    cat > /usr/local/sbin/node-mgr-shaper << EOF
#!/usr/bin/env bash
IFACE="${def_if}"
BW="${bw_mbit}mbit"
modprobe sch_cake 2>/dev/null || true
if tc qdisc replace dev "\$IFACE" root cake bandwidth "\$BW" diffserv4 nat dual-srchost 2>/dev/null; then
    exit 0
fi
tc qdisc replace dev "\$IFACE" root fq_codel 2>/dev/null || true
EOF
    chmod 755 /usr/local/sbin/node-mgr-shaper
    /usr/local/sbin/node-mgr-shaper || true

    cat > /etc/systemd/system/node-diagnostic-shaper.service << EOF
[Unit]
Description=LissVPN Smart Traffic Shaper (CAKE Fair Queueing)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/node-mgr-shaper
ExecStop=/sbin/tc qdisc replace dev ${def_if} root fq
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node-diagnostic-shaper.service >/dev/null 2>&1 || true
    _log_fix "CAKE traffic shaper enabled on ${def_if} (${bw_mbit}mbit, dual-srchost)"
    log_success "Smart Traffic Shaper активирован на ${def_if} (${bw_mbit} Мбит/с, честное деление канала между клиентами)"
}

run_optimize() {
    _init_env
    local flag="${1:---all}"
    local arg2="${2:-}"
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
        --zram)            opt_zram ;;
        --shaper|--shape)  opt_shaper "$arg2" ;;
        --sysctl)          opt_sysctl ;;
        --limits)          opt_limits ;;
        --rps)             opt_rps ;;
        --nic)             opt_nic ;;
        --mss)             opt_mss ;;
        --irqbalance)      opt_irqbalance ;;
        --journald)        opt_journald ;;
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
          "/etc/systemd/user.conf.d/${ND_DROPIN_PREFIX}-limits.conf" \
          "/etc/modules-load.d/${ND_DROPIN_PREFIX}.conf" \
          "/etc/modprobe.d/${ND_DROPIN_PREFIX}-conntrack.conf" \
          "/etc/systemd/journald.conf.d/${ND_DROPIN_PREFIX}.conf" 2>/dev/null || true

    for svc in node-diagnostic-rps node-diagnostic-nic node-diagnostic-zram node-diagnostic-shaper; do
        systemctl disable --now "${svc}.service" 2>/dev/null || true
        rm -f "/etc/systemd/system/${svc}.service"
    done
    rm -f /usr/local/sbin/node-mgr-rps /usr/local/sbin/node-mgr-nic /usr/local/sbin/node-mgr-zram /usr/local/sbin/node-mgr-shaper

    local def_if
    def_if=$(detect_default_iface)
    if [ -n "$def_if" ] && command -v tc >/dev/null 2>&1; then
        tc qdisc replace dev "$def_if" root fq 2>/dev/null || true
    fi

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

    local virt_type
    virt_type=$(detect_virt)
    case "$virt_type" in
        lxc|lxc-libvirt|openvz|docker|podman|systemd-nspawn)
            log_error "Контейнерная виртуализация ($virt_type): ядро общее с хостом, замена невозможна"
            return 1
            ;;
    esac

    local cpu_model xanmod_level="x64v1"
    cpu_model=$(awk -F: '/model name/{gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "unknown")
    if grep -q "avx512" /proc/cpuinfo 2>/dev/null; then
        xanmod_level="x64v4"
    elif grep -q "avx2" /proc/cpuinfo 2>/dev/null; then
        xanmod_level="x64v3"
    elif grep -q "sse4_2" /proc/cpuinfo 2>/dev/null; then
        xanmod_level="x64v2"
    fi
    log_info "Текущее ядро: $(uname -r) | CPU: ${cpu_model} | Профиль ISA: ${ORANGE}${xanmod_level}${NC}"
    if echo "$cpu_model" | grep -qiE 'QEMU Virtual CPU|Common KVM processor|Common 32-bit KVM|kvm64|qemu64'; then
        log_warning "Гипервизор маскирует модель CPU (${cpu_model}) — выбран безопасный профиль ${xanmod_level}"
    fi

    local codename=""
    codename=$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-}" || true)
    [ -z "$codename" ] && codename=$(lsb_release -cs 2>/dev/null || echo "releases")
    local suite="$codename"
    local http_code
    http_code=$(curl -fsSL -o /dev/null -w '%{http_code}' --connect-timeout 6 "https://deb.xanmod.org/dists/${suite}/Release" 2>/dev/null || echo "000")
    if [ "$http_code" != "200" ]; then
        http_code=$(curl -fsSL -o /dev/null -w '%{http_code}' --connect-timeout 6 "https://deb.xanmod.org/dists/releases/Release" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ]; then
            suite="releases"
        else
            log_error "Репозиторий XanMod не отвечает или не поддерживает дистрибутив '${codename}' (HTTP ${http_code})"
            return 1
        fi
    fi

    if ! prompt_yn "Установить пакет linux-xanmod-${xanmod_level} из ветки '${suite}' (потребуется перезагрузка)? (y/n): " "y"; then
        return 0
    fi

    if ! command -v gpg >/dev/null 2>&1; then install_package gnupg; fi
    local xanmod_key="/usr/share/keyrings/xanmod-archive-keyring.gpg"
    local raw_key
    raw_key=$(create_temp_file)
    if ! curl -fsSL --connect-timeout 10 https://dl.xanmod.org/archive.key -o "$raw_key"; then
        log_error "Не удалось скачать GPG-ключ XanMod"
        return 1
    fi
    local expected_fpr="D38D7D1DA1349567ADED882D86F7D09EE734E623"
    local got_fpr
    got_fpr=$(gpg --batch --with-colons --import-options show-only --import < "$raw_key" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}' || true)
    if [ -n "$got_fpr" ] && [ "$got_fpr" != "$expected_fpr" ]; then
        log_error "Несовпадение GPG fingerprint ключа XanMod: получен ${got_fpr}, ожидался ${expected_fpr}"
        return 1
    fi
    gpg --batch --yes --dearmor -o "$xanmod_key" < "$raw_key"
    echo "deb [signed-by=$xanmod_key] https://deb.xanmod.org ${suite} main" > /etc/apt/sources.list.d/xanmod-release.list
    apt-get update -qq >/dev/null 2>&1

    log_info "Установка linux-xanmod-${xanmod_level}..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "linux-xanmod-${xanmod_level}"; then
        _log_fix "XanMod kernel (${xanmod_level}) installed"
        log_success "Ядро XanMod (${xanmod_level}) успешно установлено!"
        local k_cnt
        k_cnt=$(find /boot -maxdepth 1 -name 'vmlinuz-*' 2>/dev/null | wc -l)
        log_info "Пре-ребут проверка: ядер в /boot = ${k_cnt} (старое ядро сохранено для отката в GRUB)"
        log_warning "Выполните 'reboot' в удобное время для загрузки с ядром BBRv3."
    else
        log_error "Не удалось установить пакет ядра XanMod"
        rm -f /etc/apt/sources.list.d/xanmod-release.list
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
    # У XTLS релизы помечаются pre-release, поэтому берем первый из /releases?per_page=1
    api_response=$(curl -s --connect-timeout 10 --max-time 25 "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=1" 2>/dev/null) || true
    latest_release=$(echo "$api_response" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    if [ -z "$latest_release" ]; then
        api_response=$(curl -s --connect-timeout 10 --max-time 25 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null) || true
        latest_release=$(echo "$api_response" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    fi
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
    if [ -z "$out" ] && is_container_running "remnanode"; then
        out=$(docker exec remnanode xray x25519 2>/dev/null || true)
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

# ── Генерация дефолтного второго поддомена для XHTTP из первого ───
suggest_xhttp_domain() {
    local d1="$1"
    local prefix="${d1%%.*}"
    local rest="${d1#*.}"
    if [[ "$prefix" =~ ^([a-zA-Z-]+)1$ ]]; then
        echo "${BASH_REMATCH[1]}2.${rest}"
    elif [[ "$prefix" =~ ^([a-zA-Z-]+)-01$ ]]; then
        echo "${BASH_REMATCH[1]}-02.${rest}"
    else
        echo "xhttp.${rest}"
    fi
}

# ── Развертывание Caddy L4 + Selfsteal в /opt/selfsteel ───────────
install_caddy_selfsteal() {
    print_header "РАЗВЕРТЫВАНИЕ CADDY L4 + SELFSTEAL (/opt/selfsteel)"

    if check_existing_caddy && [ "${NON_INTERACTIVE:-false}" != true ]; then
        log_warning "Caddy L4 Selfsteal уже установлен в $CADDY_DIR"
        echo -e "    ${ORANGE}1)${NC} Пропустить   ${ORANGE}2)${NC} Перезаписать (с бэкапом)"
        local cc; prompt_choice "Выбор [1-2]: " 2 cc "1"
        if [ "$cc" = "1" ]; then
            STATUS_CADDY="уже установлен"
            DETAIL_CADDY_DOMAIN=$(get_saved_caddy_domain)
            DETAIL_XHTTP_DOMAIN=$(get_saved_xhttp_domain)
            DETAIL_CADDY_PORT=$(get_saved_caddy_port)
            return 0
        fi
        backup_existing_config "$CADDY_DIR"
        docker compose --project-directory "$CADDY_DIR" down 2>/dev/null || true
    fi

    local domain="${SELF_STEAL_DOMAIN:-${CFG_DOMAIN:-}}"
    if [ "${NON_INTERACTIVE:-false}" != true ] && [ -z "$domain" ]; then
        while [ -z "$domain" ]; do
            read -p "  ${ORANGE}>${NC} 1-й поддомен для VLESS Reality Vision (SELF_STEAL_DOMAIN): " -r domain
            domain=$(echo "$domain" | tr -d '[:space:]' | sed 's|^https\?://||;s|/.*$||')
            if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
                log_warning "Некорректный формат домена!"
                domain=""
            fi
        done
    fi
    SELF_STEAL_DOMAIN="$domain"
    DETAIL_CADDY_DOMAIN="$domain"

    local def_xhttp_dom
    def_xhttp_dom=$(suggest_xhttp_domain "$SELF_STEAL_DOMAIN")
    local xdomain="${XHTTP_STEAL_DOMAIN:-}"
    if [ -z "$xdomain" ]; then
        if [ "${NON_INTERACTIVE:-false}" = true ]; then
            xdomain="$def_xhttp_dom"
        else
            while [ -z "$xdomain" ]; do
                read -p "  ${ORANGE}>${NC} 2-й поддомен для VLESS Reality XHTTP (XHTTP_STEAL_DOMAIN) [${def_xhttp_dom}]: " -r xdomain
                xdomain="${xdomain:-$def_xhttp_dom}"
                xdomain=$(echo "$xdomain" | tr -d '[:space:]' | sed 's|^https\?://||;s|/.*$||')
                if ! [[ "$xdomain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
                    log_warning "Некорректный формат домена!"
                    xdomain=""
                elif [ "$xdomain" = "$SELF_STEAL_DOMAIN" ]; then
                    log_warning "Поддомен для XHTTP должен отличаться от Vision (${SELF_STEAL_DOMAIN}) для L4 SNI-маршрутизации!"
                    xdomain=""
                fi
            done
        fi
    fi
    XHTTP_STEAL_DOMAIN="$xdomain"
    DETAIL_XHTTP_DOMAIN="$xdomain"

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

    # Выбор типа сертификата: 1 = HTTP-01 (стандарт), 2 = DNS-01 (Cloudflare API Token)
    local cert_choice="${CFG_CERT_TYPE:-1}"
    local cf_token="${CFG_CLOUDFLARE_TOKEN:-}"
    if [ "${NON_INTERACTIVE:-false}" != true ]; then
        echo -e "  ${WHITE}Способ выпуска SSL-сертификатов Let's Encrypt:${NC}"
        echo -e "    ${ORANGE}1)${NC} Обычный HTTP-01 challenge (по умолчанию, без токенов)"
        echo -e "    ${ORANGE}2)${NC} Cloudflare DNS-01 challenge (через Cloudflare API Token)"
        prompt_choice "Выберите способ [1-2, Enter=1]: " 2 cert_choice "${CFG_CERT_TYPE:-1}"
    fi
    if [ "$cert_choice" = "2" ]; then
        if [ -z "$cf_token" ] && [ "${NON_INTERACTIVE:-false}" != true ]; then
            while [ -z "$cf_token" ]; do
                read -s -p "  ${ORANGE}>${NC} Введите Cloudflare API Token (Zone:Read, DNS:Edit): " -r cf_token
                echo
                cf_token=$(echo "$cf_token" | tr -d '\r\n ' | sed 's/[^a-zA-Z0-9_-]//g')
            done
        fi
        if [ -n "$cf_token" ]; then
            validate_cloudflare_token "$cf_token" || log_warning "Продолжаем с указанным Cloudflare API Token"
            CFG_CERT_TYPE="2"
            CFG_CLOUDFLARE_TOKEN="$cf_token"
        else
            log_warning "Cloudflare API Token не задан — переключаемся на стандартный HTTP-01"
            cert_choice="1"
        fi
    fi

    # Проверка DNS перед стартом Caddy (в интерактивном режиме)
    if [ "${NON_INTERACTIVE:-false}" != true ]; then
        validate_domain_dns "$SELF_STEAL_DOMAIN" "$NODE_IP" || true
        validate_domain_dns "$XHTTP_STEAL_DOMAIN" "$NODE_IP" || true
    fi

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
XHTTP_STEAL_DOMAIN=${XHTTP_STEAL_DOMAIN}
SELF_STEAL_PORT=${SELF_STEAL_PORT}
VISION_INBOUND_PORT=${VISION_INBOUND_PORT}
XHTTP_INBOUND_PORT=${XHTTP_INBOUND_PORT}
${cf_token:+CLOUDFLARE_API_TOKEN=${cf_token}}
EOF
    chmod 600 "$CADDY_DIR/.env"
    umask 022

    # 3. Генерация Dockerfile для сборки Caddy с модулем github.com/mholt/caddy-l4 (+ cloudflare при DNS-01)
    if [ "$cert_choice" = "2" ]; then
        cat > "$CADDY_DIR/Dockerfile" << 'EOF'
FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/mholt/caddy-l4 --with github.com/caddy-dns/cloudflare

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
EOF
    else
        cat > "$CADDY_DIR/Dockerfile" << 'EOF'
FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/mholt/caddy-l4

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
EOF
    fi

    local tls_block_cfg=""
    if [ "$cert_choice" = "2" ]; then
        tls_block_cfg="dns cloudflare {env.CLOUDFLARE_API_TOKEN}"
    else
        tls_block_cfg="issuer acme {
            disable_tlsalpn_challenge
        }"
    fi

    # 4. Генерация /opt/selfsteel/Caddyfile (L4 SNI-роутинг на :443 + Selfsteal HTTPS на 127.0.0.1:9443)
    cat > "$CADDY_DIR/Caddyfile" << EOF
{
    https_port {\$SELF_STEAL_PORT}
    default_bind 127.0.0.1
    auto_https disable_redirects
    admin off

    layer4 {
        0.0.0.0:443 {
            @vision tls sni {\$SELF_STEAL_DOMAIN}
            route @vision {
                proxy 127.0.0.1:{\$VISION_INBOUND_PORT}
            }

            @xhttp tls sni {\$XHTTP_STEAL_DOMAIN}
            route @xhttp {
                proxy 127.0.0.1:{\$XHTTP_INBOUND_PORT}
            }

            route {
                proxy 127.0.0.1:{\$SELF_STEAL_PORT}
            }
        }
    }
}

http://{\$SELF_STEAL_DOMAIN}, http://{\$XHTTP_STEAL_DOMAIN} {
    bind 0.0.0.0
    redir https://{host}{uri} permanent
}

https://{\$SELF_STEAL_DOMAIN}, https://{\$XHTTP_STEAL_DOMAIN} {
    tls {
        ${tls_block_cfg}
    }
    root * /var/www/html
    encode zstd gzip
    header -Server
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

:{\$SELF_STEAL_PORT} {
    tls internal
    respond 204
    log off
}

:80 {
    bind 0.0.0.0
    respond 204
    log off
}
EOF

    # 5. Генерация /opt/selfsteel/docker-compose.yml
    cat > "$CADDY_DIR/docker-compose.yml" << 'EOF'
services:
  caddy:
    build:
      context: .
      dockerfile: Dockerfile
    image: caddy-l4:local
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

    # 6. Сборка (при необходимости) и запуск контейнера Caddy L4 + ожидание сертификатов
    docker rm -f caddy-selfsteal "$CADDY_CONTAINER_NAME" 2>/dev/null || true
    local need_build=false
    if ! docker image inspect caddy-l4:local >/dev/null 2>&1; then
        need_build=true
    elif [ "$cert_choice" = "2" ]; then
        if ! docker run --rm caddy-l4:local caddy list-modules 2>/dev/null | grep -q "dns.providers.cloudflare"; then
            need_build=true
        fi
    fi
    if [ "$need_build" = true ]; then
        log_info "Сборка образа Caddy с модулем layer4 (github.com/mholt/caddy-l4)..."
        docker compose --project-directory "$CADDY_DIR" build
    fi
    docker compose --project-directory "$CADDY_DIR" up -d --remove-orphans

    if check_container_health "$CADDY_CONTAINER_NAME" 30; then
        log_success "Контейнер ${CADDY_CONTAINER_NAME} запущен (L4 :443 -> Vision :${VISION_INBOUND_PORT} / XHTTP :${XHTTP_INBOUND_PORT} | Selfsteal 127.0.0.1:${SELF_STEAL_PORT})"
        wait_for_caddy_certificate "$SELF_STEAL_DOMAIN" 60
        wait_for_caddy_certificate "$XHTTP_STEAL_DOMAIN" 60
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
            read -p "  ${ORANGE}>${NC} 1-й поддомен для VLESS Reality Vision (SELF_STEAL_DOMAIN): " -r SELF_STEAL_DOMAIN
            SELF_STEAL_DOMAIN=$(echo "$SELF_STEAL_DOMAIN" | tr -d '[:space:]' | sed 's|^https\?://||;s|/.*$||')
            if ! [[ "$SELF_STEAL_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
                log_warning "Некорректный формат домена!"
                SELF_STEAL_DOMAIN=""
            fi
        done
    fi

    local def_xhttp_dom
    def_xhttp_dom=$(suggest_xhttp_domain "$SELF_STEAL_DOMAIN")
    if [ -z "$XHTTP_STEAL_DOMAIN" ]; then
        if [ "${NON_INTERACTIVE:-false}" = true ]; then
            XHTTP_STEAL_DOMAIN="$def_xhttp_dom"
        else
            while [ -z "$XHTTP_STEAL_DOMAIN" ]; do
                read -p "  ${ORANGE}>${NC} 2-й поддомен для VLESS Reality XHTTP (XHTTP_STEAL_DOMAIN) [${def_xhttp_dom}]: " -r XHTTP_STEAL_DOMAIN
                XHTTP_STEAL_DOMAIN="${XHTTP_STEAL_DOMAIN:-$def_xhttp_dom}"
                XHTTP_STEAL_DOMAIN=$(echo "$XHTTP_STEAL_DOMAIN" | tr -d '[:space:]' | sed 's|^https\?://||;s|/.*$||')
                if ! [[ "$XHTTP_STEAL_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
                    log_warning "Некорректный формат домена!"
                    XHTTP_STEAL_DOMAIN=""
                elif [ "$XHTTP_STEAL_DOMAIN" = "$SELF_STEAL_DOMAIN" ]; then
                    log_warning "Поддомен для XHTTP должен отличаться от Vision (${SELF_STEAL_DOMAIN}) для L4 SNI-роутинга!"
                    XHTTP_STEAL_DOMAIN=""
                fi
            done
        fi
    fi

    if [ "${NON_INTERACTIVE:-false}" != true ]; then
        local input_xpath=""
        read -p "  ${ORANGE}>${NC} Путь XHTTP (XHTTP_PATH) [${XHTTP_PATH:-$DEFAULT_XHTTP_PATH}]: " -r input_xpath
        XHTTP_PATH="${input_xpath:-${XHTTP_PATH:-$DEFAULT_XHTTP_PATH}}"
    fi
    XHTTP_PATH="${XHTTP_PATH:-$DEFAULT_XHTTP_PATH}"

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
    print_header "АВТОМАТИЧЕСКАЯ РЕГИСТРАЦИЯ В ПАНЕЛИ REMNAWAVE API (L4: REALITY + XHTTP)"

    local xhttp_dom="${XHTTP_STEAL_DOMAIN:-$(suggest_xhttp_domain "$SELF_STEAL_DOMAIN")}"
    local xhttp_path="${XHTTP_PATH:-$DEFAULT_XHTTP_PATH}"
    local vision_port="${VISION_INBOUND_PORT:-$DEFAULT_VISION_PORT}"
    local xhttp_port="${XHTTP_INBOUND_PORT:-$DEFAULT_XHTTP_PORT}"

    local clean_node_name="${NODE_NAME//[^a-zA-Z0-9_-]/}"
    local upper_node_name
    upper_node_name=$(echo "$clean_node_name" | tr '[:lower:]-' '[:upper:]_' | tr -cd 'A-Z0-9_')
    local profile_name="Profile-${clean_node_name}"
    local vision_tag="VLESS_REALITY_${upper_node_name:-NODE}"
    local xhttp_tag="VLESS_XHTTP_${upper_node_name:-NODE}"

    # Генерация ключей Reality (X25519) и shortId
    local keypair priv_key pub_key short_id
    keypair=$(generate_x25519_keypair)
    priv_key="${keypair%%:*}"
    pub_key="${keypair##*:}"
    short_id=$(openssl rand -hex 8 2>/dev/null || echo "a1b2c3d4e5f60718")

    # ── ШАГ 1: Создание или обновление Config Profile (/api/config-profiles) ─
    log_info "Шаг 1/3: Синхронизация Config Profile '${profile_name}' (2 инбаунда: Reality Vision + XHTTP)..."
    local profile_payload profile_resp="" profile_uuid="" vision_inbound_uuid="" xhttp_inbound_uuid=""

    # Формируем JSON с двумя инбаундами за Caddy L4 (127.0.0.1:10443 Vision + 127.0.0.1:10444 XHTTP -> fallback 127.0.0.1:9443)
    profile_payload=$(jq -n \
        --arg name "$profile_name" \
        --arg v_tag "$vision_tag" \
        --arg x_tag "$xhttp_tag" \
        --argjson v_port "$vision_port" \
        --argjson x_port "$xhttp_port" \
        --arg v_dom "$SELF_STEAL_DOMAIN" \
        --arg x_dom "$xhttp_dom" \
        --arg x_path "$xhttp_path" \
        --arg dest "127.0.0.1:${SELF_STEAL_PORT}" \
        --arg pk "$priv_key" \
        --arg sid "$short_id" \
        '{
            name: $name,
            config: {
                log: {
                    loglevel: "warning"
                },
                dns: {
                    servers: ["1.1.1.1", "8.8.8.8"],
                    queryStrategy: "UseIPv4"
                },
                inbounds: [
                    {
                        tag: $v_tag,
                        port: $v_port,
                        listen: "127.0.0.1",
                        protocol: "vless",
                        settings: {
                            clients: [],
                            decryption: "none"
                        },
                        sniffing: {
                            enabled: true,
                            routeOnly: true,
                            destOverride: ["http", "tls", "quic"]
                        },
                        streamSettings: {
                            network: "raw",
                            security: "reality",
                            rawSettings: {
                                acceptProxyProtocol: false
                            },
                            realitySettings: {
                                show: false,
                                xver: 0,
                                dest: $dest,
                                target: $dest,
                                serverNames: [$v_dom],
                                privateKey: $pk,
                                shortIds: [$sid]
                            }
                        }
                    },
                    {
                        tag: $x_tag,
                        port: $x_port,
                        listen: "127.0.0.1",
                        protocol: "vless",
                        settings: {
                            clients: [],
                            decryption: "none"
                        },
                        sniffing: {
                            enabled: true,
                            routeOnly: true,
                            destOverride: ["http", "tls", "quic"]
                        },
                        streamSettings: {
                            network: "xhttp",
                            security: "reality",
                            xhttpSettings: {
                                host: $x_dom,
                                path: $x_path,
                                mode: "auto"
                            },
                            realitySettings: {
                                show: false,
                                xver: 0,
                                dest: $dest,
                                target: $dest,
                                serverNames: [$x_dom],
                                privateKey: $pk,
                                shortIds: [$sid]
                            }
                        }
                    }
                ],
                outbounds: [
                    {
                        tag: "DIRECT",
                        protocol: "freedom",
                        settings: {
                            domainStrategy: "UseIPv4"
                        }
                    },
                    {
                        tag: "BLOCK",
                        protocol: "blackhole"
                    }
                ],
                routing: {
                    domainStrategy: "IPIfNonMatch",
                    rules: [
                        {
                            type: "field",
                            protocol: ["bittorrent"],
                            outboundTag: "BLOCK"
                        },
                        {
                            type: "field",
                            ip: ["geoip:private"],
                            outboundTag: "BLOCK"
                        },
                        {
                            type: "field",
                            domain: ["geosite:private"],
                            outboundTag: "BLOCK"
                        }
                    ]
                }
            }
        }')

    # 1.1 Проверяем, существует ли уже профиль с именем $profile_name
    local existing_profiles=""
    existing_profiles=$(remnawave_api_request "GET" "/api/config-profiles" "" 2>/dev/null || true)
    if [ -n "$existing_profiles" ]; then
        profile_uuid=$(echo "$existing_profiles" | jq -r --arg n "$profile_name" '
            (.response.configProfiles // .response // .data // [])
            | map(select(.name == $n))[0].uuid // empty
        ' 2>/dev/null || true)

        if [ -n "$profile_uuid" ]; then
            log_info "Найден существующий профиль '${profile_name}' (UUID: ${profile_uuid}), обновляем инбаунды..."
            local patch_profile_payload
            patch_profile_payload=$(echo "$profile_payload" | jq --arg u "$profile_uuid" '. + {uuid: $u}')
            if profile_resp=$(remnawave_api_request "PATCH" "/api/config-profiles" "$patch_profile_payload" 2>/dev/null); then
                vision_inbound_uuid=$(echo "$profile_resp" | jq -r --arg t "$vision_tag" '
                    (.response.inbounds // .data.inbounds // .inbounds // [])
                    | (map(select(.tag == $t))[0].uuid // .[0].uuid) // empty
                ' 2>/dev/null || true)
                xhttp_inbound_uuid=$(echo "$profile_resp" | jq -r --arg t "$xhttp_tag" '
                    (.response.inbounds // .data.inbounds // .inbounds // [])
                    | (map(select(.tag == $t))[0].uuid // .[1].uuid) // empty
                ' 2>/dev/null || true)
            else
                vision_inbound_uuid=$(echo "$existing_profiles" | jq -r --arg n "$profile_name" --arg t "$vision_tag" '
                    (.response.configProfiles // .response // .data // [])
                    | map(select(.name == $n))[0].inbounds
                    | (map(select(.tag == $t))[0].uuid // .[0].uuid) // empty
                ' 2>/dev/null || true)
                xhttp_inbound_uuid=$(echo "$existing_profiles" | jq -r --arg n "$profile_name" --arg t "$xhttp_tag" '
                    (.response.configProfiles // .response // .data // [])
                    | map(select(.name == $n))[0].inbounds
                    | (map(select(.tag == $t))[0].uuid // .[1].uuid) // empty
                ' 2>/dev/null || true)
            fi
        fi
    fi

    # 1.2 Если профиль не найден — создаем новый через POST /api/config-profiles
    if [ -z "$profile_uuid" ]; then
        if profile_resp=$(remnawave_api_request "POST" "/api/config-profiles" "$profile_payload"); then
            profile_uuid=$(echo "$profile_resp" | jq -r '.response.uuid // .data.uuid // .uuid // empty')
            vision_inbound_uuid=$(echo "$profile_resp" | jq -r --arg t "$vision_tag" '
                (.response.inbounds // .data.inbounds // .inbounds // [])
                | (map(select(.tag == $t))[0].uuid // .[0].uuid) // empty
            ')
            xhttp_inbound_uuid=$(echo "$profile_resp" | jq -r --arg t "$xhttp_tag" '
                (.response.inbounds // .data.inbounds // .inbounds // [])
                | (map(select(.tag == $t))[0].uuid // .[1].uuid) // empty
            ')
        else
            log_error "Не удалось создать Config Profile через POST /api/config-profiles!"
            STATUS_API="ошибка"
            return 1
        fi
    fi

    # 1.3 Если UUID инбаундов ещё пусты, запрашиваем детали конкретного профиля по UUID
    if [ -n "$profile_uuid" ] && { [ -z "$vision_inbound_uuid" ] || [ -z "$xhttp_inbound_uuid" ]; }; then
        local single_prof=""
        single_prof=$(remnawave_api_request "GET" "/api/config-profiles/${profile_uuid}" "" 2>/dev/null || true)
        if [ -n "$single_prof" ]; then
            [ -z "$vision_inbound_uuid" ] && vision_inbound_uuid=$(echo "$single_prof" | jq -r --arg t "$vision_tag" '
                (.response.inbounds // .data.inbounds // [])
                | (map(select(.tag == $t))[0].uuid // .[0].uuid) // empty
            ')
            [ -z "$xhttp_inbound_uuid" ] && xhttp_inbound_uuid=$(echo "$single_prof" | jq -r --arg t "$xhttp_tag" '
                (.response.inbounds // .data.inbounds // [])
                | (map(select(.tag == $t))[0].uuid // .[1].uuid) // empty
            ')
        fi
    fi

    DETAIL_PROFILE_UUID="$profile_uuid"
    log_success "Профиль активен: Profile=${profile_uuid} | Vision Inbound=${vision_inbound_uuid} | XHTTP Inbound=${xhttp_inbound_uuid}"

    # ── ШАГ 2: Создание или получение Ноды (/api/nodes + /api/keygen) ───────
    log_info "Шаг 2/3: Регистрация ноды '${NODE_NAME}' (${NODE_ADDRESS})..."
    local req_node_port="${CFG_NODE_PORT:-3000}"
    local node_payload node_resp="" node_uuid="" node_secret="" parsed_port=""

    # 2.1 Проверяем, существует ли уже нода в GET /api/nodes
    local all_nodes=""
    all_nodes=$(remnawave_api_request "GET" "/api/nodes" "" 2>/dev/null || true)
    if [ -n "$all_nodes" ]; then
        node_uuid=$(echo "$all_nodes" | jq -r --arg a "$NODE_ADDRESS" --arg n "$NODE_NAME" '
            (.response.nodes // .response // .data.nodes // .data // [])
            | if type == "array" then map(select(.address == $a or .name == $n))[0].uuid else empty end // empty
        ' 2>/dev/null || true)
        node_secret=$(echo "$all_nodes" | jq -r --arg a "$NODE_ADDRESS" --arg n "$NODE_NAME" '
            (.response.nodes // .response // .data.nodes // .data // [])
            | if type == "array" then map(select(.address == $a or .name == $n))[0] | (.secretKey // .pubKey // .credentials.secretKey) else empty end // empty
        ' 2>/dev/null || true)
        parsed_port=$(echo "$all_nodes" | jq -r --arg a "$NODE_ADDRESS" --arg n "$NODE_NAME" '
            (.response.nodes // .response // .data.nodes // .data // [])
            | if type == "array" then map(select(.address == $a or .name == $n))[0].port else empty end // empty
        ' 2>/dev/null || true)
    fi

    # 2.2 Если нода ещё не создана — регистрируем через POST /api/nodes с обоими инбаундами
    if [ -z "$node_uuid" ]; then
        node_payload=$(jq -n \
            --arg name "$NODE_NAME" \
            --arg addr "$NODE_ADDRESS" \
            --argjson port "$req_node_port" \
            --arg p_uuid "$profile_uuid" \
            --arg v_uuid "$vision_inbound_uuid" \
            --arg x_uuid "$xhttp_inbound_uuid" \
            '{
                name: $name,
                address: $addr,
                port: $port,
                isTrafficTrackingActive: false,
                configProfile: {
                    activeConfigProfileUuid: $p_uuid,
                    activeInbounds: ([$v_uuid, $x_uuid] | map(select(. != "")))
                }
            }')

        if node_resp=$(remnawave_api_request "POST" "/api/nodes" "$node_payload"); then
            node_uuid=$(echo "$node_resp" | jq -r '.response.uuid // .data.uuid // .uuid // empty' 2>/dev/null || true)
            node_secret=$(echo "$node_resp" | jq -r '.response.secretKey // .response.pubKey // .data.secretKey // .data.pubKey // .secretKey // .pubKey // empty' 2>/dev/null || true)
            parsed_port=$(echo "$node_resp" | jq -r '.response.port // .data.port // .port // empty' 2>/dev/null || true)
        else
            log_error "Не удалось зарегистрировать ноду через POST /api/nodes!"
            STATUS_API="ошибка"
            return 1
        fi
    else
        log_info "Найдена существующая нода '${NODE_NAME}' (UUID: ${node_uuid})"
        # Обновляем привязку профиля и обоих инбаундов у существующей ноды
        local update_node_payload
        update_node_payload=$(jq -n \
            --arg uuid "$node_uuid" \
            --arg p_uuid "$profile_uuid" \
            --arg v_uuid "$vision_inbound_uuid" \
            --arg x_uuid "$xhttp_inbound_uuid" \
            '{
                uuid: $uuid,
                configProfile: {
                    activeConfigProfileUuid: $p_uuid,
                    activeInbounds: ([$v_uuid, $x_uuid] | map(select(. != "")))
                }
            }')
        remnawave_api_request "PATCH" "/api/nodes" "$update_node_payload" >/dev/null 2>&1 || true
    fi

    # 2.3 В Remnawave Panel SECRET_KEY (pubKey) выдаётся эндпоинтом GET /api/keygen
    if [ -z "$node_secret" ] || [ "$node_secret" = "null" ]; then
        local keygen_resp=""
        keygen_resp=$(remnawave_api_request "GET" "/api/keygen" "" 2>/dev/null || true)
        if [ -n "$keygen_resp" ]; then
            node_secret=$(echo "$keygen_resp" | jq -r '
                if (.response | type) == "string" then .response
                elif (.data | type) == "string" then .data
                else (.response.pubKey // .response.secretKey // .response.key // .data.pubKey // .data.secretKey // .pubKey // .secretKey // empty)
                end
            ' 2>/dev/null || true)
        fi
    fi

    # 2.4 Fallback: проверяем GET /api/nodes/{uuid}, если ключ всё ещё не получен
    if { [ -z "$node_secret" ] || [ "$node_secret" = "null" ]; } && [ -n "$node_uuid" ]; then
        local single_node_resp=""
        single_node_resp=$(remnawave_api_request "GET" "/api/nodes/${node_uuid}" "" 2>/dev/null || true)
        if [ -n "$single_node_resp" ]; then
            node_secret=$(echo "$single_node_resp" | jq -r '
                .response.secretKey // .response.pubKey // .data.secretKey // .data.pubKey // .secretKey // .pubKey // empty
            ' 2>/dev/null || true)
        fi
    fi

    # Очищаем префиксы SECRET_KEY= / SSL_CERT= и пробельные символы, если API вернул строку формата KEY=VALUE
    node_secret=$(echo "${node_secret:-}" | sed -E 's/^(SECRET_KEY|SSL_CERT)=//; s/^"//; s/"$//' | tr -d '\r\n ')
    if [ "$node_secret" = "null" ]; then
        node_secret=""
    fi

    # 2.5 Fallback на CFG_SECRET_KEY или ручной ввод в интерактивном режиме
    if [ -z "$node_secret" ] && [ -n "${CFG_SECRET_KEY:-}" ]; then
        node_secret="$CFG_SECRET_KEY"
    fi

    if [ -z "$node_secret" ] && [ "${NON_INTERACTIVE:-false}" != true ]; then
        log_warning "API не вернул публичный ключ через /api/keygen. Вставьте SECRET_KEY из панели вручную:"
        while IFS= read -r line; do
            if [ -z "$line" ]; then break; fi
            node_secret="${node_secret}${line}"
        done
        node_secret=$(echo "$node_secret" | sed -E 's/^(SECRET_KEY|SSL_CERT)=//; s/^"//; s/"$//' | tr -d '\r\n ')
    fi

    if [ -z "$node_secret" ]; then
        log_error "Не удалось извлечь secretKey ноды из ответа API (/api/keygen и /api/nodes)!"
        STATUS_API="ошибка"
        return 1
    fi

    CFG_SECRET_KEY="$node_secret"
    CFG_NODE_PORT="${parsed_port:-$req_node_port}"
    DETAIL_REMNANODE_PORT="$CFG_NODE_PORT"
    DETAIL_NODE_UUID="$node_uuid"
    log_success "Нода синхронизирована: UUID=${node_uuid} | NODE_PORT=${CFG_NODE_PORT}"

    # ── ШАГ 3: Создание двух Хостов (/api/hosts) на публичном порту 443 ─────
    log_info "Шаг 3/3: Привязка 2 Хостов (Reality Vision + XHTTP на :443) к Инбаундам..."
    local vision_host_payload xhttp_host_payload host_resp="" host_uuid="" xhttp_host_uuid=""

    # 3.1 Хост 1: VLESS Reality Vision (порт 443 -> Caddy L4 -> 127.0.0.1:10443)
    if [ -n "$vision_inbound_uuid" ]; then
        vision_host_payload=$(jq -n \
            --arg remark "${NODE_NAME} [Reality]" \
            --arg addr "$SELF_STEAL_DOMAIN" \
            --arg sni "$SELF_STEAL_DOMAIN" \
            --arg p_uuid "$profile_uuid" \
            --arg i_uuid "$vision_inbound_uuid" \
            --arg n_uuid "$node_uuid" \
            '{
                remark: $remark,
                address: $addr,
                port: 443,
                sni: $sni,
                securityLayer: "DEFAULT",
                fingerprint: "chrome",
                nodes: (if $n_uuid != "" then [$n_uuid] else [] end),
                inbound: {
                    configProfileUuid: $p_uuid,
                    configProfileInboundUuid: $i_uuid
                }
            }')

        if host_resp=$(remnawave_api_request "POST" "/api/hosts" "$vision_host_payload" 2>/dev/null) \
           || host_resp=$(remnawave_api_request "POST" "/api/hosts" "$(echo "$vision_host_payload" | jq 'del(.nodes)')" 2>/dev/null); then
            host_uuid=$(echo "$host_resp" | jq -r '.response.uuid // .data.uuid // .uuid // empty')
            DETAIL_HOST_UUID="$host_uuid"
            log_success "Хост Reality Vision создан: UUID=${host_uuid} (${SELF_STEAL_DOMAIN}:443 -> 127.0.0.1:${vision_port})"
        else
            log_warning "Хост Reality Vision (${SELF_STEAL_DOMAIN}) уже существует или требует проверки в панели."
        fi
    fi

    # 3.2 Хост 2: VLESS Reality XHTTP (порт 443 -> Caddy L4 -> 127.0.0.1:10444)
    if [ -n "$xhttp_inbound_uuid" ]; then
        xhttp_host_payload=$(jq -n \
            --arg remark "${NODE_NAME} [XHTTP]" \
            --arg addr "$xhttp_dom" \
            --arg sni "$xhttp_dom" \
            --arg path "$xhttp_path" \
            --arg p_uuid "$profile_uuid" \
            --arg i_uuid "$xhttp_inbound_uuid" \
            --arg n_uuid "$node_uuid" \
            '{
                remark: $remark,
                address: $addr,
                port: 443,
                sni: $sni,
                host: $addr,
                path: $path,
                securityLayer: "DEFAULT",
                alpn: "h2,http/1.1",
                fingerprint: "chrome",
                nodes: (if $n_uuid != "" then [$n_uuid] else [] end),
                inbound: {
                    configProfileUuid: $p_uuid,
                    configProfileInboundUuid: $i_uuid
                }
            }')

        if host_resp=$(remnawave_api_request "POST" "/api/hosts" "$xhttp_host_payload" 2>/dev/null) \
           || host_resp=$(remnawave_api_request "POST" "/api/hosts" "$(echo "$xhttp_host_payload" | jq 'del(.nodes)')" 2>/dev/null); then
            xhttp_host_uuid=$(echo "$host_resp" | jq -r '.response.uuid // .data.uuid // .uuid // empty')
            DETAIL_XHTTP_HOST_UUID="$xhttp_host_uuid"
            log_success "Хост Reality XHTTP создан: UUID=${xhttp_host_uuid} (${xhttp_dom}:443 path=${xhttp_path} -> 127.0.0.1:${xhttp_port})"
        else
            log_warning "Хост Reality XHTTP (${xhttp_dom}) уже существует или требует проверки в панели."
        fi
    fi

    umask 077
    cat > "$API_STATE_FILE" << EOF
REMNAWAVE_API_URL="${REMNAWAVE_API_URL}"
NODE_NAME="${NODE_NAME}"
NODE_ADDRESS="${NODE_ADDRESS}"
NODE_UUID="${DETAIL_NODE_UUID}"
PROFILE_UUID="${DETAIL_PROFILE_UUID}"
VISION_INBOUND_UUID="${vision_inbound_uuid}"
XHTTP_INBOUND_UUID="${xhttp_inbound_uuid}"
VISION_HOST_UUID="${DETAIL_HOST_UUID}"
XHTTP_HOST_UUID="${DETAIL_XHTTP_HOST_UUID}"
SELF_STEAL_DOMAIN="${SELF_STEAL_DOMAIN}"
XHTTP_STEAL_DOMAIN="${xhttp_dom}"
XHTTP_PATH="${xhttp_path}"
SELF_STEAL_PORT="${SELF_STEAL_PORT}"
VISION_INBOUND_PORT="${vision_port}"
XHTTP_INBOUND_PORT="${xhttp_port}"
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
    print_header "УСТАНОВКА И НАСТРОЙКА FAIL2BAN (SYSTEMD + UFW + PORTSCAN)"

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

    cat > /etc/fail2ban/filter.d/portscan.conf << 'EOF'
[Definition]
failregex = ^.*\[UFW BLOCK\].*SRC=<HOST>.*$
            ^.*PORTSCAN BLOCK:.*SRC=<HOST>.*$
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

    local portscan_log="/var/log/kern.log"
    local portscan_backend="auto"
    local portscan_extra="logpath = /var/log/kern.log"
    if [ ! -f "$portscan_log" ] && [ -f /var/log/messages ]; then
        portscan_log="/var/log/messages"
        portscan_extra="logpath = /var/log/messages"
    elif [ ! -f "$portscan_log" ]; then
        if [ "$ssh_backend" = "systemd" ]; then
            portscan_backend="systemd"
            portscan_extra="journalmatch = _TRANSPORT=kernel"
        else
            touch /var/log/kern.log
            chmod 640 /var/log/kern.log
            portscan_backend="polling"
            portscan_extra="logpath = /var/log/kern.log"
        fi
    fi

    local f2b_banaction="iptables-multiport"
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
        f2b_banaction="ufw"
    elif command -v iptables >/dev/null 2>&1; then
        local c_port n_port
        c_port=$(get_saved_caddy_port)
        n_port=$(get_saved_node_port)
        cat > /etc/systemd/system/portscan-detect.service << PORTSCAN_EOF
[Unit]
Description=Portscan detection iptables rules for Fail2ban
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'iptables -N PORTSCAN 2>/dev/null || iptables -F PORTSCAN; iptables -A PORTSCAN -p tcp --syn -m limit --limit 10/min --limit-burst 20 -j RETURN; iptables -A PORTSCAN -p tcp --syn -j LOG --log-prefix "PORTSCAN BLOCK: " --log-level 4; iptables -C INPUT -p tcp --syn -m multiport ! --dports ${ssh_port},80,443,${c_port},${n_port} -j PORTSCAN 2>/dev/null || iptables -A INPUT -p tcp --syn -m multiport ! --dports ${ssh_port},80,443,${c_port},${n_port} -j PORTSCAN'
ExecStop=/bin/sh -c 'iptables -D INPUT -p tcp --syn -m multiport ! --dports ${ssh_port},80,443,${c_port},${n_port} -j PORTSCAN 2>/dev/null || true; iptables -F PORTSCAN 2>/dev/null || true; iptables -X PORTSCAN 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
PORTSCAN_EOF
        systemctl daemon-reload
        systemctl enable --now portscan-detect.service >/dev/null 2>&1 || true
    fi

    local panel_ip_ignore
    panel_ip_ignore=$(get_saved_panel_ip)

    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
banaction = ${f2b_banaction}
banaction_allports = ${f2b_banaction}
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 ${panel_ip_ignore}
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

[portscan]
enabled = true
filter = portscan
backend = ${portscan_backend}
${portscan_extra}
maxretry = 5
findtime = 10m
bantime = 24h
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
#  Установка NetBird VPN, Стека Мониторинга и Генератор Защиты (Protect)
# ═══════════════════════════════════════════════════════════════════
connect_netbird() {
    local setup_key=""
    if [ "${NON_INTERACTIVE:-false}" = true ] && [ -n "$CFG_NETBIRD_SETUP_KEY" ]; then
        setup_key="$CFG_NETBIRD_SETUP_KEY"
    else
        while [ -z "$setup_key" ]; do
            read -p "  ${ORANGE}>${NC} Введите Setup Key для NetBird: " -r setup_key
            if [ -z "$setup_key" ]; then
                log_error "Setup Key не может быть пустым."
            elif ! validate_setup_key "$setup_key"; then
                setup_key=""
            fi
        done
    fi

    log_info "Подключение к сети NetBird..."
    if netbird up --setup-key "$setup_key"; then
        log_success "NetBird подключен!"
        local nb_ip=""
        for _ in $(seq 1 15); do
            nb_ip=$(ip -4 addr show wt0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || true)
            [ -n "$nb_ip" ] && break
            sleep 1
        done
        if [ -n "$nb_ip" ]; then
            DETAIL_NETBIRD_IP="$nb_ip"
            log_info "Внутренний IP в сети NetBird (wt0): ${ORANGE}${nb_ip}${NC}"
        fi
        STATUS_NETBIRD="подключен"
        return 0
    else
        log_error "Ошибка подключения NetBird. Проверьте правильность Setup Key."
        STATUS_NETBIRD="ошибка"
        return 1
    fi
}

install_netbird() {
    print_header "УСТАНОВКА NETBIRD MESH VPN"

    local nb_status=0
    check_existing_netbird || nb_status=$?
    if [ $nb_status -eq 0 ]; then
        log_info "NetBird уже установлен и подключен (${DETAIL_NETBIRD_IP:-wt0})."
        if ! prompt_yn "Переподключить с новым Setup Key? (y/n): " "n" "$CFG_INSTALL_NETBIRD"; then
            STATUS_NETBIRD="уже подключен"
            return 0
        fi
        connect_netbird
        return $?
    elif [ $nb_status -eq 2 ]; then
        log_info "NetBird установлен, но не подключен."
        if prompt_yn "Подключить NetBird по Setup Key? (y/n): " "y" "$CFG_INSTALL_NETBIRD"; then
            connect_netbird
            return $?
        fi
        return 0
    fi

    if ! prompt_yn "Установить и подключить NetBird VPN? (y/n): " "n" "$CFG_INSTALL_NETBIRD"; then
        return 0
    fi

    log_info "Скачивание официального установщика NetBird..."
    local nb_script
    nb_script=$(create_temp_file)
    if ! curl -fsSL https://pkgs.netbird.io/install.sh -o "$nb_script" || [ ! -s "$nb_script" ]; then
        log_error "Не удалось скачать скрипт установки NetBird."
        STATUS_NETBIRD="ошибка"
        return 1
    fi

    if sh "$nb_script"; then
        log_success "Клиент NetBird установлен."
        connect_netbird
    else
        log_error "Ошибка при установке NetBird."
        STATUS_NETBIRD="ошибка"
        return 1
    fi
}

install_monitoring() {
    print_header "УСТАНОВКА МОНИТОРИНГА (CADVISOR + NODE EXPORTER + VMAGENT)"

    if ! command -v docker >/dev/null 2>&1; then
        log_warning "Для стека мониторинга требуется Docker Engine."
        return 1
    fi

    local mon_status=0
    check_existing_monitoring || mon_status=$?
    if [ $mon_status -eq 0 ]; then
        log_info "Стек мониторинга уже запущен в ${MONITORING_DIR}."
        if ! prompt_yn "Переустановить и перезаписать конфигурацию мониторинга? (y/n): " "n" "$CFG_INSTALL_MONITORING"; then
            STATUS_MONITORING="уже установлен"
            return 0
        fi
        docker compose --project-directory "$MONITORING_DIR" down 2>/dev/null || true
    else
        if ! prompt_yn "Установить стек мониторинга (cAdvisor + Node Exporter + vmagent)? (y/n): " "n" "$CFG_INSTALL_MONITORING"; then
            return 0
        fi
    fi

    update_component_versions

    local instance_name="" grafana_ip=""
    if [ "${NON_INTERACTIVE:-false}" = true ] && [ -n "$CFG_INSTANCE_NAME" ]; then
        instance_name="$CFG_INSTANCE_NAME"
    else
        while [ -z "$instance_name" ]; do
            read -p "  ${ORANGE}>${NC} Имя ноды для меток в Grafana [${NODE_NAME:-$(hostname)}]: " -r instance_name
            instance_name="${instance_name:-${NODE_NAME:-$(hostname)}}"
            if ! validate_instance_name "$instance_name"; then
                instance_name=""
            fi
        done
    fi

    if [ "${NON_INTERACTIVE:-false}" = true ] && [ -n "$CFG_GRAFANA_IP" ]; then
        grafana_ip="$CFG_GRAFANA_IP"
    else
        while [ -z "$grafana_ip" ]; do
            read -p "  ${ORANGE}>${NC} IP сервера Grafana / VictoriaMetrics (например 100.64.0.1): " -r grafana_ip
            if ! validate_ip "$grafana_ip"; then
                log_error "Введите корректный IPv4-адрес."
                grafana_ip=""
            fi
        done
    fi

    mkdir -p "$MONITORING_DIR/vmagent_data"

    cat > "$MONITORING_DIR/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  external_labels:
    instance: '${instance_name}'

scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['127.0.0.1:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['127.0.0.1:9101']

  - job_name: 'vmagent'
    static_configs:
      - targets: ['127.0.0.1:8429']
EOF

    cat > "$MONITORING_DIR/docker-compose.yml" << EOF
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v${CADVISOR_VERSION}
    container_name: cadvisor
    restart: unless-stopped
    network_mode: host
    pid: host
    command:
      - '--port=9101'
      - '--listen_ip=127.0.0.1'
      - '--docker_only=true'
      - '--housekeeping_interval=15s'
      - '--disable_metrics=percpu,sched,tcp,udp,disk,diskIO,hugetlb,referenced_memory,cpu_topology,resctrl,process,advtcp,memory_numa'
      - '--store_container_labels=false'
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    devices:
      - /dev/kmsg
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  node-exporter:
    image: prom/node-exporter:v${NODE_EXPORTER_VERSION}
    container_name: node-exporter
    restart: unless-stopped
    network_mode: host
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
      - '--web.listen-address=127.0.0.1:9100'
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  vmagent:
    image: victoriametrics/vmagent:v${VMAGENT_VERSION}
    container_name: vmagent
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./vmagent_data:/vmagent_data
    command:
      - '--promscrape.config=/etc/prometheus/prometheus.yml'
      - '--remoteWrite.url=http://${grafana_ip}:8428/api/v1/write'
      - '--remoteWrite.tmpDataPath=/vmagent_data'
      - '--remoteWrite.maxDiskUsagePerURL=1073741824'
      - '--httpListenAddr=127.0.0.1:8429'
      - '--memory.allowedPercent=40'
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

    if docker compose --project-directory "$MONITORING_DIR" up -d --remove-orphans; then
        sleep 2
        if is_container_running "cadvisor" && is_container_running "node-exporter" && is_container_running "vmagent"; then
            STATUS_MONITORING="установлен"
            DETAIL_GRAFANA_IP="$grafana_ip"
            _log_fix "Monitoring stack deployed (instance=${instance_name}, remoteWrite=${grafana_ip}:8428)"
            log_success "Мониторинг запущен! Метрики отправляются на http://${grafana_ip}:8428/api/v1/write"
        else
            STATUS_MONITORING="ошибка"
            log_error "Не все контейнеры мониторинга запустились. Проверьте: docker compose --project-directory $MONITORING_DIR ps"
            return 1
        fi
    else
        STATUS_MONITORING="ошибка"
        log_error "Ошибка при запуске контейнеров мониторинга."
        return 1
    fi
}

run_verify_stack() {
    _init_env
    print_header "E2E ВЕРИФИКАЦИЯ СТЕКА: CADDY L4 ──► XRAY REALITY ──► SELFSTEAL"

    local v_dom x_dom c_port v_port x_port
    v_dom=$(get_saved_caddy_domain)
    x_dom=$(get_saved_xhttp_domain)
    c_port=$(get_saved_caddy_port)
    v_port="${VISION_INBOUND_PORT:-$DEFAULT_VISION_PORT}"
    x_port="${XHTTP_INBOUND_PORT:-$DEFAULT_XHTTP_PORT}"

    local xray_ver="не запущен" caddy_ver="не запущен"
    if is_container_running "remnanode"; then
        xray_ver=$(docker exec remnanode xray version 2>/dev/null | head -1 | awk '{print $1, $2}' || echo "running")
    fi
    if is_container_running "$CADDY_CONTAINER_NAME"; then
        caddy_ver=$(docker exec "$CADDY_CONTAINER_NAME" caddy version 2>/dev/null | head -1 || echo "running")
    fi

    box_top "1/3 · ВЕРСИИ ЯДРА И L4 СОКЕТЫ"
    box_kv "Ядро Xray (remnanode)" "${xray_ver}"
    box_kv "Сервер Caddy L4" "${caddy_ver}"

    local ss_out
    ss_out=$(ss -tlnp 2>/dev/null || true)
    if echo "$ss_out" | grep -qE ':443[[:space:]]'; then
        box_row "${GREEN}${BOLD}[ PASS ]${NC} Внешний сокет :443/tcp (Caddy L4 SNI Router) активен"
    else
        box_row "${RED}${BOLD}[ FAIL ]${NC} Порт :443/tcp НЕ слушается! Проверьте контейнер ${CADDY_CONTAINER_NAME}"
    fi
    if echo "$ss_out" | grep -qE "127\.0\.0\.1:${v_port}[[:space:]]"; then
        box_row "${GREEN}${BOLD}[ PASS ]${NC} Инбаунд VLESS Reality Vision слушает 127.0.0.1:${v_port}"
    else
        box_row "${YELLOW}${BOLD}[ WARN ]${NC} Сокет 127.0.0.1:${v_port} (Vision) не обнаружен (ожидание конфига от панели)"
    fi
    if echo "$ss_out" | grep -qE "127\.0\.0\.1:${x_port}[[:space:]]"; then
        box_row "${GREEN}${BOLD}[ PASS ]${NC} Инбаунд VLESS Reality XHTTP слушает 127.0.0.1:${x_port}"
    else
        box_row "${YELLOW}${BOLD}[ WARN ]${NC} Сокет 127.0.0.1:${x_port} (XHTTP) не обнаружен (ожидание конфига от панели)"
    fi
    if echo "$ss_out" | grep -qE "127\.0\.0\.1:${c_port}[[:space:]]"; then
        box_row "${GREEN}${BOLD}[ PASS ]${NC} Внутренний Selfsteal слушает строго 127.0.0.1:${c_port}"
    else
        box_row "${RED}${BOLD}[ FAIL ]${NC} Сокет Selfsteal 127.0.0.1:${c_port} не активен"
    fi
    box_bottom
    echo

    box_top "2/3 · СКВОЗНОЙ ТЕСТ РУКОПОЖАТИЙ И МАСКИРОВКИ (E2E PROBE)"
    if [ -n "$v_dom" ]; then
        local v_probe=""
        v_probe=$(curl -sS -I --http2 --tlsv1.3 --connect-timeout 5 --max-time 8 \
            --resolve "${v_dom}:443:127.0.0.1" "https://${v_dom}/" 2>/dev/null | head -1 | tr -d '\r' || true)
        if echo "$v_probe" | grep -qE "HTTP/(2|1\.1) 200"; then
            box_row "${GREEN}${BOLD}[ PASS ]${NC} Vision E2E (${v_dom}:443 -> :${v_port} -> :${c_port}): ${v_probe}"
        else
            box_row "${YELLOW}${BOLD}[ WARN ]${NC} Vision E2E (${v_dom}:443): ${v_probe:-нет ответа HTTP 200}"
        fi
    else
        box_row "${YELLOW}${BOLD}[ SKIP ]${NC} SELF_STEAL_DOMAIN ещё не настроен"
    fi

    if [ -n "$x_dom" ]; then
        local x_probe=""
        x_probe=$(curl -sS -I --http2 --tlsv1.3 --connect-timeout 5 --max-time 8 \
            --resolve "${x_dom}:443:127.0.0.1" "https://${x_dom}/" 2>/dev/null | head -1 | tr -d '\r' || true)
        if echo "$x_probe" | grep -qE "HTTP/(2|1\.1) 200"; then
            box_row "${GREEN}${BOLD}[ PASS ]${NC} XHTTP E2E  (${x_dom}:443 -> :${x_port} -> :${c_port}): ${x_probe}"
        else
            box_row "${YELLOW}${BOLD}[ WARN ]${NC} XHTTP E2E  (${x_dom}:443): ${x_probe:-нет ответа HTTP 200}"
        fi
    else
        box_row "${YELLOW}${BOLD}[ SKIP ]${NC} XHTTP_STEAL_DOMAIN ещё не настроен"
    fi

    local scan_probe=""
    scan_probe=$(curl -k -sS -o /dev/null -w "%{http_code}" --connect-timeout 4 --max-time 6 \
        --resolve "scanner-probe.invalid:443:127.0.0.1" "https://scanner-probe.invalid/" 2>/dev/null || echo "000")
    if [ "$scan_probe" = "204" ] || [ "$scan_probe" = "000" ]; then
        box_row "${GREEN}${BOLD}[ PASS ]${NC} Защита от сканеров (чужой SNI -> catch-all): HTTP ${scan_probe} (реальный домен скрыт)"
    else
        box_row "${YELLOW}${BOLD}[ WARN ]${NC} Защита от сканеров (чужой SNI): вернул HTTP ${scan_probe}"
    fi
    box_bottom
    echo

    box_top "3/3 · ПРОВЕРКА DNS И ОТСУТСТВИЯ CLOUDFLARE ПРОКСИ (ORANGE CLOUD)"
    for dom in "$v_dom" "$x_dom"; do
        [ -z "$dom" ] && continue
        local r_ip=""
        r_ip=$(resolve_host_to_ip "$dom")
        if [ "$r_ip" = "$NODE_IP" ]; then
            box_row "${GREEN}${BOLD}[ PASS ]${NC} DNS ${dom} -> ${r_ip} (DNS-only, указывает прямо на ноду)"
        elif [ -n "$r_ip" ]; then
            box_row "${RED}${BOLD}[ FAIL ]${NC} DNS ${dom} -> ${r_ip} (НЕ совпадает с IP ноды ${NODE_IP}! Отключите прокси Cloudflare)"
        else
            box_row "${YELLOW}${BOLD}[ WARN ]${NC} DNS ${dom}: A-запись не найдена"
        fi
    done
    box_bottom
    echo
}

run_protect() {
    _init_env
    print_header "ГЕНЕРАТОР ЗАЩИТНЫХ КОНФИГОВ (NFTABLES ANTI-DDOS + SSH HARDENING)"

    mkdir -p "$PROTECT_OUT_DIR"
    local ssh_port node_port panel_ip
    ssh_port=$(detect_ssh_port)
    node_port=$(get_saved_node_port)
    panel_ip=$(get_saved_panel_ip)

    local ssh_keys_ok=0
    local ak
    for ak in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
        [ -f "$ak" ] || continue
        if grep -qE '^(ssh-(rsa|ed25519|ecdsa)|ecdsa-sha2-)' "$ak" 2>/dev/null; then
            ssh_keys_ok=1
            break
        fi
    done

    local panel_rule="# Panel API port ${node_port}/tcp (uncomment and set panel IP if needed)
        # ip saddr 127.0.0.1 tcp dport ${node_port} accept"
    if [ -n "$panel_ip" ]; then
        panel_rule="# Remnawave Panel ACL (${panel_ip} -> ${node_port}/tcp)
        ip saddr ${panel_ip} tcp dport ${node_port} accept"
    fi

    cat > "${PROTECT_OUT_DIR}/firewall.nft" << EOF
#!/usr/sbin/nft -f
# Generated by node-mgr v${SCRIPT_VERSION} (protect module)
# Dedicated table 'inet vpn_protect' — safe alongside Docker iptables rules.

table inet vpn_protect
delete table inet vpn_protect

table inet vpn_protect {
    set ipv4_Allowlist {
        type ipv4_addr
        flags interval
        elements = { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10${panel_ip:+, ${panel_ip}} }
    }

    set ssh_meter4 {
        type ipv4_addr
        size 65535
        flags dynamic, timeout
        timeout 10m
    }

    set syn_443_meter4 {
        type ipv4_addr
        size 131072
        flags dynamic, timeout
        timeout 1m
    }

    set udp_443_meter4 {
        type ipv4_addr
        size 131072
        flags dynamic, timeout
        timeout 1m
    }

    chain input {
        type filter hook input priority filter - 5; policy accept;

        iif "lo" accept
        iifname "wt0" accept
        iifname "docker*" accept
        iifname "br-*" accept

        ct state vmap { established : accept, related : accept, invalid : drop }

        ip saddr @ipv4_Allowlist accept

        # ICMP rate-limited
        ip protocol icmp icmp type { echo-request, destination-unreachable, time-exceeded } limit rate 10/second accept
        ip6 nexthdr icmpv6 limit rate 20/second accept

        # SSH brute-force protection (port ${ssh_port})
        tcp dport ${ssh_port} ct state new add @ssh_meter4 { ip saddr limit rate 6/minute burst 10 packets } accept
        tcp dport ${ssh_port} ct state new drop

        ${panel_rule}
        tcp dport ${node_port} drop

        # HTTP ACME port 80
        tcp dport 80 accept

        # VLESS Reality / XHTTP port 443/tcp per-IP new connection limit (anti-SYN flood)
        tcp dport 443 ct state new add @syn_443_meter4 { ip saddr limit rate 60/second burst 120 packets } accept
        tcp dport 443 ct state new drop

        # QUIC / Hysteria2 / UDP 443 per-IP rate limit
        udp dport 443 ct state new add @udp_443_meter4 { ip saddr limit rate 120/second burst 200 packets } accept
        udp dport 443 ct state new drop
    }
}
EOF
    chmod 644 "${PROTECT_OUT_DIR}/firewall.nft"

    local pwd_auth="no"
    local pwd_comment="# SSH-ключи обнаружены — парольный вход безопасно отключён"
    if [ "$ssh_keys_ok" -eq 0 ]; then
        pwd_auth="yes"
        pwd_comment="# ВНИМАНИЕ: SSH-ключи не найдены в authorized_keys! PasswordAuthentication оставлен 'yes' во избежание потери доступа."
    fi

    cat > "${PROTECT_OUT_DIR}/sshd-hardening.conf" << EOF
# Generated by node-mgr v${SCRIPT_VERSION} (protect module)
# Copy to /etc/ssh/sshd_config.d/99-vpn-hardening.conf and test with 'sshd -t'
${pwd_comment}
Port ${ssh_port}
PasswordAuthentication ${pwd_auth}
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PermitRootLogin prohibit-password
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 20
ClientAliveInterval 60
ClientAliveCountMax 3
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
EOF

    cat > "${PROTECT_OUT_DIR}/APPLY.txt" << EOF
====================================================================
 ИНСТРУКЦИЯ ПО БЕЗОПАСНОМУ ПРИМЕНЕНИЮ ЗАЩИТЫ (AUTO-ROLLBACK 5 МИН)
====================================================================

1. Проверка синтаксиса nftables:
   nft -c -f ${PROTECT_OUT_DIR}/firewall.nft

2. Безопасное тестовое применение с авто-откатом через 5 минут
   (если вы потеряете доступ, таймер удалит таблицу автоматически):
   systemd-run --on-active=300 --unit=nft-rollback /usr/sbin/nft delete table inet vpn_protect
   nft -f ${PROTECT_OUT_DIR}/firewall.nft

3. Если SSH и VPN работают штатно — отмените таймер авто-отката:
   systemctl stop nft-rollback.timer nft-rollback.service 2>/dev/null || true

4. Применение SSH Hardening:
   cp ${PROTECT_OUT_DIR}/sshd-hardening.conf /etc/ssh/sshd_config.d/99-vpn-hardening.conf
   sshd -t && systemctl reload sshd
====================================================================
EOF

    box_top "СГЕНЕРИРОВАННЫЕ ФАЙЛЫ ЗАЩИТЫ (${PROTECT_OUT_DIR})"
    box_kv "Таблица nftables" "${PROTECT_OUT_DIR}/firewall.nft"
    box_kv "SSH Hardening" "${PROTECT_OUT_DIR}/sshd-hardening.conf"
    box_kv "Инструкция + таймер" "${PROTECT_OUT_DIR}/APPLY.txt"
    if [ "$ssh_keys_ok" -eq 1 ]; then
        box_row "${GREEN}${BOLD}[ OK ]${NC} SSH authorized_keys найдены — PasswordAuthentication no"
    else
        box_row "${YELLOW}${BOLD}[WARN]${NC} SSH authorized_keys НЕ найдены — PasswordAuthentication оставлен yes"
    fi
    box_bottom
    echo
    log_success "Файлы защиты сохранены в ${PROTECT_OUT_DIR} (система не изменена, см. APPLY.txt)"
}

dry_run() {
    _init_env
    if [ -f "$CONFIG_FILE" ]; then
        load_config_file "$CONFIG_FILE"
    fi
    print_header "РЕЖИМ ПРОВЕРКИ ПЛАНА РАЗВЕРТЫВАНИЯ (--DRY-RUN)"
    box_top "ПЛАН КОНФИГУРАЦИИ И МОДУЛЕЙ (БЕЗ ВНЕСЕНИЯ ИЗМЕНЕНИЙ)"
    box_kv "ОС / Ядро" "${OS} ($(uname -r)) | Пакетный менеджер: ${PKG_MANAGER}"
    box_kv "IP узла / SSH порт" "${NODE_ADDRESS:-$NODE_IP} | SSH: $(detect_ssh_port)/tcp"
    box_kv "Remnawave API URL" "${REMNAWAVE_API_URL:-не задан (интерактивный запрос)}"
    box_kv "Vision SNI (:10443)" "${SELF_STEAL_DOMAIN:-$(get_saved_caddy_domain)} -> Selfsteal 127.0.0.1:${SELF_STEAL_PORT}"
    box_kv "XHTTP SNI (:10444)" "${XHTTP_STEAL_DOMAIN:-$(get_saved_xhttp_domain)} (path: ${XHTTP_PATH:-$DEFAULT_XHTTP_PATH})"
    box_kv "Метод выпуска SSL" "$([ "${CFG_CERT_TYPE:-1}" = "2" ] && echo "Cloudflare DNS-01" || echo "Let's Encrypt HTTP-01 (:80)")"
    box_kv "Порт API Ноды" "${CFG_NODE_PORT:-$(get_saved_node_port)}/tcp (ACL для панели: ${CFG_PANEL_IP:-$(get_saved_panel_ip)})"
    box_kv "Сетевой стек Highload" "BBR + sch_cake/fq + 64MB buffers + RPS/XPS + NIC + TCPMSS + FD 1M"
    box_kv "UFW + Fail2ban" "UFW=${CFG_SETUP_UFW:-y} | Fail2ban=${CFG_INSTALL_FAIL2BAN:-y} (sshd, caddy-status, portscan)"
    box_kv "NetBird / Мониторинг" "NetBird=${CFG_INSTALL_NETBIRD:-n} | Monitoring=${CFG_INSTALL_MONITORING:-n} (${CFG_GRAFANA_IP:-нет IP})"
    box_bottom
    echo
    log_success "Dry-run завершён. Никакие изменения в систему не вносились."
}

# ═══════════════════════════════════════════════════════════════════
#  Сценарии развертывания: API Auto-Deploy и Интерактивная установка
# ═══════════════════════════════════════════════════════════════════
run_api_auto_deploy() {
    _init_env
    print_header "АВТОМАТИЧЕСКОЕ РАЗВЕРТЫВАНИЕ ЧЕРЕЗ REMNAWAVE API [1/8 .. 8/8]"

    if ! check_disk_space 500 "/opt"; then
        if ! prompt_yn "Продолжить? (y/n): " "n"; then exit 1; fi
    fi

    ensure_package_manager_available
    _RESTORE_AUTO_UPDATES=true

    echo -e "\n  ${ORANGE}${BOLD}[1/8] Проверка утилит (curl, jq, openssl, ethtool) и сбор параметров API${NC}"
    install_base_utilities
    collect_api_inputs

    echo -e "\n  ${ORANGE}${BOLD}[2/8] Highload-оптимизация ядра, RPS/XPS, NIC и лимитов${NC}"
    run_optimize "--all"

    echo -e "\n  ${ORANGE}${BOLD}[3/8] Проверка и установка Docker Engine & Compose v2${NC}"
    if install_docker && check_docker_compose; then
        STATUS_DOCKER="установлен"
    else
        STATUS_DOCKER="ошибка"
        exit 1
    fi

    echo -e "\n  ${ORANGE}${BOLD}[4/8] Развертывание Caddy L4 Selfsteal (/opt/selfsteel) и выпуск SSL${NC}"
    install_caddy_selfsteal

    echo -e "\n  ${ORANGE}${BOLD}[5/8] Автоматическое создание Профиля, Ноды и 2 Хостов через Remnawave API${NC}"
    automate_remnawave_api

    echo -e "\n  ${ORANGE}${BOLD}[6/8] Развертывание Remnanode (/opt/remnanode) с пробросом /certs:ro${NC}"
    deploy_remnanode_container "$CFG_NODE_PORT" "$CFG_SECRET_KEY" "$CFG_PANEL_IP"

    echo -e "\n  ${ORANGE}${BOLD}[7/8] Опциональные модули: NetBird Mesh VPN и Стек Мониторинга${NC}"
    if [[ "${CFG_INSTALL_NETBIRD:-n}" =~ ^[Yy]$ ]]; then
        install_netbird || true
    fi
    if [[ "${CFG_INSTALL_MONITORING:-n}" =~ ^[Yy]$ ]]; then
        install_monitoring || true
    fi

    echo -e "\n  ${ORANGE}${BOLD}[8/8] Изоляция периметра UFW и запуск Fail2ban${NC}"
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
    echo -e "    ${ORANGE}${BOLD}[1]${NC} ${WHITE}Автоматическая регистрация через Remnawave API${NC} ${DIM}(Caddy L4 + Reality Vision + XHTTP + 2 Хоста)${NC}"
    echo -e "    ${ORANGE}${BOLD}[2]${NC} ${WHITE}Ручная установка по готовому SECRET_KEY${NC}       ${DIM}(Классический режим + опции NetBird/Monitoring)${NC}"
    echo
    local mode_c="1"
    prompt_choice "Выберите режим [1-2, Enter=1]: " 2 mode_c "1"

    if [ "$mode_c" = "1" ]; then
        run_api_auto_deploy
        return 0
    fi

    print_header "КЛАССИЧЕСКАЯ УСТАНОВКА УЗЛА [1/8 .. 8/8]"
    if ! check_disk_space 500 "/opt"; then
        if ! prompt_yn "Продолжить? (y/n): " "n"; then exit 1; fi
    fi
    ensure_package_manager_available
    _RESTORE_AUTO_UPDATES=true
    install_base_utilities

    echo -e "\n  ${ORANGE}${BOLD}[1/8] Оптимизация ядра, RPS/XPS, NIC и лимитов${NC}"
    run_optimize "--all"

    echo -e "\n  ${ORANGE}${BOLD}[2/8] Установка Docker Engine${NC}"
    if install_docker && check_docker_compose; then
        STATUS_DOCKER="установлен"
    else
        STATUS_DOCKER="ошибка"
        exit 1
    fi

    echo -e "\n  ${ORANGE}${BOLD}[3/8] Установка Caddy Selfsteal (/opt/selfsteel)${NC}"
    install_caddy_selfsteal

    echo -e "\n  ${ORANGE}${BOLD}[4/8] Установка RemnawaveNode (/opt/remnanode)${NC}"
    install_remnanode_manual

    echo -e "\n  ${ORANGE}${BOLD}[5/8] Установка NetBird Mesh VPN (опционально)${NC}"
    install_netbird || true

    echo -e "\n  ${ORANGE}${BOLD}[6/8] Установка стека мониторинга Grafana/vmagent (опционально)${NC}"
    install_monitoring || true

    echo -e "\n  ${ORANGE}${BOLD}[7/8] Настройка UFW Firewall (Strict Panel ACL)${NC}"
    setup_ufw

    echo -e "\n  ${ORANGE}${BOLD}[8/8] Установка и запуск Fail2ban${NC}"
    install_fail2ban

    restore_auto_updates
    _RESTORE_AUTO_UPDATES=false
    show_installation_summary
}

run_selective_install() {
    _init_env
    print_header "ВЫБОРОЧНАЯ УСТАНОВКА / ПОЧИНКА МОДУЛЕЙ"
    echo -e "    ${ORANGE}${BOLD}[1]${NC} Оптимизация ядра (sysctl/BBR/sch_cake/FD/RPS+XPS/NIC/MSS/journald)"
    echo -e "    ${ORANGE}${BOLD}[2]${NC} Docker Engine & Compose v2"
    echo -e "    ${ORANGE}${BOLD}[3]${NC} Caddy L4 Selfsteal (/opt/selfsteel + /opt/html, HTTP-01 или Cloudflare DNS-01)"
    echo -e "    ${ORANGE}${BOLD}[4]${NC} Регистрация через Remnawave API + запуск Remnanode"
    echo -e "    ${ORANGE}${BOLD}[5]${NC} Ручная установка Remnanode (по SECRET_KEY)"
    echo -e "    ${ORANGE}${BOLD}[6]${NC} UFW Firewall (доступ к порту ноды только с IP панели)"
    echo -e "    ${ORANGE}${BOLD}[7]${NC} Fail2ban (sshd + caddy-status + portscan)"
    echo -e "    ${ORANGE}${BOLD}[8]${NC} NetBird Mesh VPN (установка и подключение по Setup Key)"
    echo -e "    ${ORANGE}${BOLD}[9]${NC} Стек мониторинга (cAdvisor + Node Exporter + vmagent)"
    echo -e "    ${ORANGE}${BOLD}[10]${NC} Генератор защитных профилей (nftables + sshd hardening в ${PROTECT_OUT_DIR})"
    echo -e "    ${ORANGE}${BOLD}[11]${NC} Smart Traffic Shaper (CAKE dual-srchost для честного деления канала)"
    echo

    local selection_raw
    read -p "  ${ORANGE}>${NC} Номера через пробел [1-11]: " -r selection_raw
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
            8) install_netbird ;;
            9) install_monitoring ;;
            10) run_protect ;;
            11) opt_shaper ;;
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
        monitoring|vmagent|cadvisor)
            docker compose --project-directory "$MONITORING_DIR" logs -f --tail=100
            ;;
        f2b|fail2ban)
            journalctl -u fail2ban -n 100 -f
            ;;
        *)
            log_error "Использование: node-mgr logs {node|caddy|monitoring|f2b}"
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
    print_live_statusbar
    echo
    local cc qdisc rmem_mb ssh_p panel_ip node_p caddy_p caddy_dom xhttp_dom
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "?")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "?")
    rmem_mb=$(( $(sysctl -n net.core.rmem_max 2>/dev/null || echo 0) / 1048576 ))
    ssh_p=$(detect_ssh_port)
    panel_ip=$(get_saved_panel_ip)
    node_p=$(get_saved_node_port)
    caddy_p=$(get_saved_caddy_port)
    caddy_dom=$(get_saved_caddy_domain)
    xhttp_dom=$(get_saved_xhttp_domain)
    check_existing_netbird || true
    check_existing_monitoring || true

    box_top "СОСТОЯНИЕ УЗЛА И СЕТЕВОГО СТЕКА"
    box_kv "ОС / Ядро" "${OS} ($(uname -r))"
    box_kv "TCP Congestion" "${cc} + ${qdisc} (rmem_max: ${rmem_mb} MB)"
    box_kv "SSH порт" "${ssh_p}/tcp"
    box_kv "IP Панели (UFW ACL)" "${panel_ip:-не привязан} -> порт ${node_p}/tcp"
    box_kv "Vision SNI (:10443)" "${caddy_dom:-не настроен} (Selfsteal 127.0.0.1:${caddy_p})"
    box_kv "XHTTP SNI (:10444)" "${xhttp_dom:-не настроен} (path: ${XHTTP_PATH:-$DEFAULT_XHTTP_PATH})"
    box_kv "NetBird IP (wt0)" "${DETAIL_NETBIRD_IP:-не подключен}"
    box_kv "Мониторинг Grafana" "${DETAIL_GRAFANA_IP:+http://${DETAIL_GRAFANA_IP}:8428}${DETAIL_GRAFANA_IP:-не настроен}"
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
        box_row "${GREEN}${BOLD}[ RUNNING ]${NC} Контейнер ${CADDY_CONTAINER_NAME} (L4 :443 | Selfsteal 127.0.0.1:${caddy_p})"
    else
        box_row "${YELLOW}${BOLD}[ STOPPED ]${NC} Контейнер ${CADDY_CONTAINER_NAME}"
    fi

    if is_container_running "vmagent" && is_container_running "node-exporter" && is_container_running "cadvisor"; then
        box_row "${GREEN}${BOLD}[ RUNNING ]${NC} Мониторинг (cAdvisor + node-exporter + vmagent -> ${DETAIL_GRAFANA_IP:-remoteWrite})"
    elif [ -d "$MONITORING_DIR" ]; then
        box_row "${YELLOW}${BOLD}[ PARTIAL ]${NC} Мониторинг (${MONITORING_DIR})"
    else
        box_row "${GRAPHITE}[ NOT SET ]${NC} Мониторинг (cAdvisor + node-exporter + vmagent)"
    fi

    if [ -n "$DETAIL_NETBIRD_IP" ]; then
        box_row "${GREEN}${BOLD}[ ONLINE  ]${NC} NetBird VPN (wt0: ${DETAIL_NETBIRD_IP})"
    elif command -v netbird >/dev/null 2>&1; then
        box_row "${YELLOW}${BOLD}[ OFFLINE ]${NC} NetBird VPN (установлен, не подключен)"
    else
        box_row "${GRAPHITE}[ NOT SET ]${NC} NetBird VPN"
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
    box_top "ИТОГИ РАЗВЕРТЫВАНИЯ УЗЛА LISSVPN (CADDY L4 MULTI-PROTOCOL)"
    box_kv "Сетевой стек Highload" "$STATUS_NETWORK"
    box_kv "Docker Engine" "$STATUS_DOCKER"
    box_kv "Caddy L4 + Selfsteal" "$STATUS_CADDY (Vision: $(get_saved_caddy_domain) | XHTTP: $(get_saved_xhttp_domain))"
    box_kv "L4 Маршрутизация :443" "Vision -> 127.0.0.1:${VISION_INBOUND_PORT} | XHTTP -> 127.0.0.1:${XHTTP_INBOUND_PORT}"
    box_kv "Remnawave API" "$STATUS_API ${DETAIL_NODE_UUID:+(Node UUID: $DETAIL_NODE_UUID)}"
    box_kv "RemnawaveNode" "$STATUS_REMNANODE (порт: $(get_saved_node_port), /certs:ro)"
    box_kv "NetBird VPN" "${STATUS_NETBIRD}${DETAIL_NETBIRD_IP:+ (IP: $DETAIL_NETBIRD_IP)}"
    box_kv "Стек Мониторинга" "${STATUS_MONITORING}${DETAIL_GRAFANA_IP:+ (-> $DETAIL_GRAFANA_IP:8428)}"
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
        log_info "Пересборка и обновление образа Caddy L4 Selfsteal..."
        docker compose --project-directory "$CADDY_DIR" build --pull
        docker compose --project-directory "$CADDY_DIR" up -d --remove-orphans
    fi
    if [ -f "$MONITORING_DIR/docker-compose.yml" ]; then
        log_info "Обновление версий и образов стека мониторинга (cAdvisor / node-exporter / vmagent)..."
        update_component_versions
        sed -i -E "s|gcr.io/cadvisor/cadvisor:v[0-9.]+|gcr.io/cadvisor/cadvisor:v${CADVISOR_VERSION}|g" "$MONITORING_DIR/docker-compose.yml" 2>/dev/null || true
        sed -i -E "s|prom/node-exporter:v[0-9.]+|prom/node-exporter:v${NODE_EXPORTER_VERSION}|g" "$MONITORING_DIR/docker-compose.yml" 2>/dev/null || true
        sed -i -E "s|victoriametrics/vmagent:v[0-9.]+|victoriametrics/vmagent:v${VMAGENT_VERSION}|g" "$MONITORING_DIR/docker-compose.yml" 2>/dev/null || true
        docker compose --project-directory "$MONITORING_DIR" pull
        docker compose --project-directory "$MONITORING_DIR" up -d --remove-orphans
    fi
    if command -v netbird >/dev/null 2>&1; then
        log_info "Проверка обновлений пакета NetBird..."
        install_package netbird >/dev/null 2>&1 || true
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
    check_existing_monitoring || true

    umask 077
    cat > "$output" << EOF
# LissVPN Node Orchestrator Configuration (v${SCRIPT_VERSION})
REMNAWAVE_API_URL="${REMNAWAVE_API_URL}"
REMNAWAVE_API_TOKEN="${REMNAWAVE_API_TOKEN}"
NODE_NAME="${NODE_NAME:-$(hostname)}"
NODE_ADDRESS="${NODE_ADDRESS:-$NODE_IP}"
SELF_STEAL_DOMAIN="$(get_saved_caddy_domain)"
XHTTP_STEAL_DOMAIN="$(get_saved_xhttp_domain)"
XHTTP_PATH="${XHTTP_PATH:-$DEFAULT_XHTTP_PATH}"
SELF_STEAL_PORT=$(get_saved_caddy_port)
VISION_INBOUND_PORT=${VISION_INBOUND_PORT:-$DEFAULT_VISION_PORT}
XHTTP_INBOUND_PORT=${XHTTP_INBOUND_PORT:-$DEFAULT_XHTTP_PORT}
CFG_CERT_TYPE="${CFG_CERT_TYPE:-1}"
CFG_CLOUDFLARE_TOKEN="${CFG_CLOUDFLARE_TOKEN}"
CFG_SECRET_KEY="${cfg_secret}"
CFG_NODE_PORT=$(get_saved_node_port)
CFG_PANEL_IP="$(get_saved_panel_ip)"
CFG_APPLY_NETWORK=y
CFG_SETUP_UFW=y
CFG_INSTALL_FAIL2BAN=y
CFG_INSTALL_NETBIRD="${CFG_INSTALL_NETBIRD:-n}"
CFG_NETBIRD_SETUP_KEY="${CFG_NETBIRD_SETUP_KEY}"
CFG_INSTALL_MONITORING="$([ -d "$MONITORING_DIR" ] && echo "y" || echo "n")"
CFG_INSTANCE_NAME="${CFG_INSTANCE_NAME:-$(hostname)}"
CFG_GRAFANA_IP="${DETAIL_GRAFANA_IP:-$CFG_GRAFANA_IP}"
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
    if [ -f "$MONITORING_DIR/docker-compose.yml" ]; then
        docker compose --project-directory "$MONITORING_DIR" down 2>/dev/null || true
    fi
    docker rm -f remnanode "$CADDY_CONTAINER_NAME" caddy-selfsteal cadvisor node-exporter vmagent 2>/dev/null || true

    if systemctl is-active --quiet portscan-detect.service 2>/dev/null; then
        systemctl disable --now portscan-detect.service 2>/dev/null || true
    fi
    rm -f /etc/systemd/system/portscan-detect.service

    run_rollback
    rm -f /etc/fail2ban/jail.local /etc/fail2ban/filter.d/caddy-status.conf /etc/fail2ban/filter.d/portscan.conf
    systemctl restart fail2ban 2>/dev/null || true

    rm -rf "$REMNANODE_DIR" "$REMNANODE_DATA_DIR" "$CADDY_DIR" "$CADDY_HTML_DIR" "$MONITORING_DIR" "$PROTECT_OUT_DIR" /var/log/remnanode /etc/logrotate.d/remnanode
    log_success "Все компоненты узла удалены."
}

show_help() {
    print_banner
    cat << 'HELP'

  Использование: node-mgr [КОМАНДА] [ОПЦИИ]

  Основные команды тулкита (v4.0):
    auto-deploy                  Полное авто-развертывание ноды, L4-профиля (Reality+XHTTP) и 2 хостов по API
    diagnose [-q|--no-net|--json] Диагностика ноды (33 чека, Score 0..100, отчёт, JSON-экспорт)
    verify                       Сквозной E2E-тест рукопожатий (Caddy L4 :443 -> Xray Reality -> Selfsteal :9443)
    optimize [--all|--from-findings|--zram|--shaper [MBIT]|--sysctl|--rps|--nic|--mss]
                                 Тюнинг ядра, BBR + sch_cake/fq, FD, RPS/XPS, NIC (LRO off), TCPMSS, Zram, Shaper
    shape [MBIT]                 Включить CAKE Traffic Shaper (dual-srchost) для защиты от перегрузки канала
    protect                      Генерация защитных конфигов nftables (anti-DDoS) и sshd hardening
    bbr3                         Установка ядра XanMod с поддержкой BBRv3 (с проверкой релиза и GPG)
    rollback                     Откат всех наложенных оптимизаций
    status                       Показать состояние узла, контейнеров, NetBird, мониторинга и артефактов
    logs {node|caddy|monitoring|f2b}
                                 Просмотр логов RemnaNode, Caddy, Мониторинга или Fail2ban
    install                      Установка ноды (с выбором API или ручного режима)
    selective                    Выборочная установка модулей (включая NetBird, Monitoring, Protect, Shaper)
    netbird                      Установка и подключение NetBird Mesh VPN по Setup Key
    monitoring                   Установка стека мониторинга (cAdvisor + Node Exporter + vmagent)
    change-template              Смена HTML-шаблона маскировки (/opt/html, 10 шаблонов)
    update                       Обновление Docker-образов (RemnaNode, Caddy L4, Monitoring) и NetBird
    self-update                  Обновление самого скрипта node-mgr из GitHub
    export-config [FILE]         Экспорт текущих настроек в конфиг-файл (chmod 600)
    dry-run                      Показать план развертывания без внесения изменений в систему
    uninstall                    Удаление всех компонентов и откат настроек
    --config FILE                Автоматическая установка по конфиг-файлу

  Переменные окружения для Zero-Touch API деплоя (Caddy L4: Reality Vision + XHTTP):
    REMNAWAVE_API_URL="https://panel.example.com"
    REMNAWAVE_API_TOKEN="eyJ..."
    NODE_NAME="NL-Ruby-01"
    NODE_ADDRESS="82.47.155.72"
    SELF_STEAL_DOMAIN="nl1.example.com"
    XHTTP_STEAL_DOMAIN="nl2.example.com"
    XHTTP_PATH="/api/v3/sync/r1"
    SELF_STEAL_PORT="9443"
    CFG_CERT_TYPE="1"            # 1 = Let's Encrypt HTTP-01 (:80), 2 = Cloudflare DNS-01
    CFG_CLOUDFLARE_TOKEN="..."   # API-токен Cloudflare (при CFG_CERT_TYPE=2)
HELP
    echo
}

# ═══════════════════════════════════════════════════════════════════
#  Интерактивное меню v4.0
# ═══════════════════════════════════════════════════════════════════
show_main_menu() {
    while true; do
        print_banner
        print_live_statusbar
        echo -e "  ${SLATE}${BOLD}ДИАГНОСТИКА И ТЮНИНГ ЯДРА${NC}"
        echo -e "    ${ORANGE}${BOLD}[1]${NC} ${WHITE}Диагностика ноды${NC}     ${DIM}33 чека, Score 0..100, PSI, MSS, порт-аудит, JSON/отчёт${NC}"
        echo -e "    ${ORANGE}${BOLD}[2]${NC} ${WHITE}Оптимизация стека${NC}    ${DIM}sysctl / BBR+CAKE / FD / RPS+XPS / NIC / Shaper / Zram${NC}"
        echo -e "    ${ORANGE}${BOLD}[3]${NC} ${WHITE}Тест L4 и Selfsteal${NC}  ${DIM}E2E-проверка рукопожатий :443 -> Xray -> Selfsteal :9443${NC}"
        echo -e "    ${ORANGE}${BOLD}[4]${NC} ${WHITE}Ядро BBRv3 (XanMod)${NC}  ${DIM}установка ядра XanMod под микроархитектуру CPU${NC}"
        echo
        echo -e "  ${SLATE}${BOLD}РАЗВЕРТЫВАНИЕ И СТЕК ПРОТОКОЛОВ${NC}"
        echo -e "    ${ORANGE}${BOLD}[5]${NC} ${WHITE}Авто-деплой по API${NC}   ${DIM}Caddy L4 + 2 Инбаунда (Reality + XHTTP) + 2 Хоста${NC}"
        echo -e "    ${ORANGE}${BOLD}[6]${NC} ${WHITE}Выборочный запуск${NC}    ${DIM}модули: Docker, Caddy, API, NetBird, Monitoring, Protect${NC}"
        echo -e "    ${ORANGE}${BOLD}[7]${NC} ${WHITE}Сменить шаблон SNI${NC}   ${DIM}быстрая смена HTML-лендинга в /opt/html (10 тем)${NC}"
        echo
        echo -e "  ${SLATE}${BOLD}БЕЗОПАСНОСТЬ И ОБСЛУЖИВАНИЕ${NC}"
        echo -e "    ${ORANGE}${BOLD}[8]${NC} ${WHITE}Статус и Логи${NC}        ${DIM}дашборд служб, NetBird, Мониторинг, просмотр логов${NC}"
        echo -e "    ${ORANGE}${BOLD}[9]${NC} ${WHITE}Защита (Protect)${NC}     ${DIM}генератор таблиц nftables anti-DDoS + SSH Hardening${NC}"
        echo -e "   ${ORANGE}${BOLD}[10]${NC} ${WHITE}Обновить компоненты${NC}  ${DIM}docker pull (Node/Caddy/Monitoring) + self-update${NC}"
        echo -e "   ${ORANGE}${BOLD}[11]${NC} ${WHITE}Откат / Удаление${NC}     ${DIM}снять оптимизации (rollback), экспорт или удалить узел${NC}"
        echo -e "    ${ORANGE}${BOLD}[0]${NC} ${GRAPHITE}Выход${NC}"
        echo
        printf "  ${BOLD}Выбор${NC} ${DIM}[0-11]${NC}: "
        local c=""
        read -r c
        echo

        case "$c" in
            1) run_diagnose ;;
            2)
                echo -e "  ${BOLD}Режим оптимизации:${NC}"
                echo -e "    ${ORANGE}[a]${NC} Применить всё (sysctl + BBR/CAKE + FD + RPS/XPS + NIC + MSS + journald)"
                echo -e "    ${ORANGE}[f]${NC} Исправить только найденное диагностикой (--from-findings)"
                echo -e "    ${ORANGE}[s]${NC} Включить Smart Traffic Shaper (CAKE dual-srchost — честный канал)"
                echo -e "    ${ORANGE}[z]${NC} Включить сжатый Zram-swap (50% RAM)"
                printf "  ${ORANGE}>${NC} Выбор [Enter=a]: "
                local oc=""
                read -r oc
                case "${oc,,}" in
                    f) run_optimize "--from-findings" ;;
                    s) opt_shaper ;;
                    z) run_optimize "--zram" ;;
                    *) run_optimize "--all" ;;
                esac
                ;;
            3|v) run_verify_stack ;;
            4) run_bbr3_xanmod ;;
            5) run_full_install ;;
            6) run_selective_install ;;
            7) change_template ;;
            8)
                show_status
                echo -e "    ${ORANGE}[Enter]${NC} Вернуться в меню   ${ORANGE}[1]${NC} Логи RemnaNode   ${ORANGE}[2]${NC} Логи Caddy   ${ORANGE}[3]${NC} Логи Fail2ban"
                printf "  ${ORANGE}>${NC} Выбор: "
                local lc=""
                read -r lc
                case "$lc" in
                    1) show_logs "node" ;;
                    2) show_logs "caddy" ;;
                    3) show_logs "f2b" ;;
                esac
                ;;
            9) run_protect ;;
            10)
                echo -e "    ${ORANGE}[1]${NC} Обновить контейнеры (RemnaNode, Caddy L4, Мониторинг)"
                echo -e "    ${ORANGE}[2]${NC} Обновить сам скрипт node-mgr с GitHub (self-update)"
                printf "  ${ORANGE}>${NC} Выбор [Enter=1]: "
                local uc=""
                read -r uc
                if [ "$uc" = "2" ]; then self_update; else update_components; fi
                ;;
            11)
                echo -e "    ${ORANGE}[1]${NC} Откатить только сетевые оптимизации (rollback)"
                echo -e "    ${ORANGE}[2]${NC} Экспортировать конфигурацию в /etc/remnanode-install.conf"
                echo -e "    ${ORANGE}[3]${NC} Полностью удалить RemnawaveNode, Caddy, Мониторинг и конфиги (uninstall)"
                printf "  ${ORANGE}>${NC} Выбор [1-3]: "
                local rc=""
                read -r rc
                if [ "$rc" = "1" ]; then run_rollback; fi
                if [ "$rc" = "2" ]; then export_config; fi
                if [ "$rc" = "3" ]; then uninstall_all; fi
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
    verify|check|probe|--verify)       run_verify_stack ;;
    optimize|opt|tune|--optimize)      run_optimize "${1:---all}" "${2:-}" ;;
    shape|shaper|--shaper)             _init_env; opt_shaper "${1:-}" ;;
    protect|hardening|--protect)       run_protect ;;
    bbr3|kernel|--bbr3)                run_bbr3_xanmod ;;
    rollback|revert|--rollback)        run_rollback ;;
    status|st|--status)                show_status ;;
    logs|--logs)                       show_logs "${1:-node}" ;;
    install|--install)                 run_full_install ;;
    selective|--selective)             run_selective_install ;;
    netbird|--netbird)                 _init_env; install_netbird ;;
    monitoring|--monitoring)           _init_env; install_monitoring ;;
    change-template|--change-template) change_template ;;
    update|--update)                   update_components ;;
    self-update|--self-update)         self_update ;;
    export-config|--export-config)     export_config "${1:-/etc/remnanode-install.conf}" ;;
    dry-run|--dry-run)                 dry_run ;;
    uninstall|--uninstall)             uninstall_all ;;
    --config)
        if [ -n "${1:-}" ] && [ -f "$1" ]; then
            CONFIG_FILE="$1"
            NON_INTERACTIVE=true
            load_config_file "$CONFIG_FILE"
            if [ "${1:-}" = "--dry-run" ] || [ "${2:-}" = "--dry-run" ]; then
                dry_run
            else
                main
            fi
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
