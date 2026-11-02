#!/usr/bin/env bash
# ==============================================================================
#  LissVPN Node Orchestrator & Diagnostic Toolkit v3.2.0 (node-mgr)
#  RemnawaveNode • Caddy Selfsteal • UFW (Strict Panel ACL) • Fail2ban
#  Integrated 27-Point Node Diagnostic & Kernel/NIC/RPS/MSS/Zram Optimizer
# ==============================================================================

set -Eeuo pipefail

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
readonly SCRIPT_VERSION="3.2.0"
readonly BIN_PATH="/usr/local/bin/node-mgr"
readonly INSTALL_LOG="/var/log/remnanode-install.log"

readonly ND_STATE_DIR="/var/lib/node-mgr"
readonly FINDINGS_FILE="${ND_STATE_DIR}/findings.env"
readonly FIX_LOG="${ND_STATE_DIR}/applied-fixes.log"
readonly ND_DROPIN_PREFIX="99-lissvpn"
readonly ND_BOX_W=68

readonly INSTALL_DIR="/opt"
readonly REMNANODE_DIR="${INSTALL_DIR}/remnanode"
readonly REMNANODE_DATA_DIR="/var/lib/remnanode"
readonly CADDY_DIR="${INSTALL_DIR}/caddy"
readonly CADDY_HTML_DIR="${CADDY_DIR}/html"
readonly CADDY_VERSION="2.10.2"
readonly DEFAULT_PORT="9443"

CADDY_IMAGE="caddy:${CADDY_VERSION}"
USE_WILDCARD=false
CLOUDFLARE_API_TOKEN=""

mkdir -p "$(dirname "$INSTALL_LOG")" "$ND_STATE_DIR" 2>/dev/null || true
exec > >(tee -a "$INSTALL_LOG") 2>&1

TEMP_FILES=()

_cleanup_on_exit() {
    local exit_code=$?
    if [ "${_RESTORE_AUTO_UPDATES:-false}" = true ]; then
        restore_auto_updates 2>/dev/null || true
    fi
    for f in "${TEMP_FILES[@]}"; do
        rm -f "$f" 2>/dev/null || true
    done
    if [ -f "$INSTALL_LOG" ]; then
        sed -i 's/\x1b\[[0-9;]*m//g' "$INSTALL_LOG" 2>/dev/null || true
    fi
    return $exit_code
}

trap 'log_error "Сбой на строке $LINENO. Команда: $BASH_COMMAND"' ERR
trap '_cleanup_on_exit' EXIT

# ═══════════════════════════════════════════════════════════════════
#  Non-interactive переменные
# ═══════════════════════════════════════════════════════════════════
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
CONFIG_FILE="${CONFIG_FILE:-/etc/remnanode-install.conf}"

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

STATUS_NETWORK="пропущен"
STATUS_DOCKER="пропущен"
STATUS_REMNANODE="пропущен"
STATUS_CADDY="пропущен"
STATUS_UFW="пропущен"
STATUS_FAIL2BAN="пропущен"

DETAIL_REMNANODE_PORT=""
DETAIL_PANEL_IP=""
DETAIL_CADDY_DOMAIN=""
DETAIL_CADDY_PORT=""
NODE_IP=""
OS=""
PKG_MANAGER=""

# ═══════════════════════════════════════════════════════════════════
#  UI-примитивы (стиль Case211/node-diagnostic + палитра LissVPN)
# ═══════════════════════════════════════════════════════════════════
log_info()    { echo -e "  ${ORANGE}${BOLD}ℹ${NC}  ${WHITE}$*${NC}"; }
log_success() { echo -e "  ${GREEN}${BOLD}✔${NC}  ${WHITE}$*${NC}"; }
log_warning() { echo -e "  ${YELLOW}${BOLD}⚠${NC}  ${YELLOW}$*${NC}"; }
log_error()   { echo -e "  ${RED}${BOLD}✖${NC}  ${RED}$*${NC}" >&2; }

ui_rule() {
    local char="${1:-─}"
    local width="${2:-$ND_BOX_W}"
    printf "  %s" "${GRAPHITE}"
    for ((i=1; i<=width; i++)); do printf "%s" "$char"; done
    printf "%s\n" "${NC}"
}

box_top() {
    local title="$1"
    local tlen=${#title}
    local pad=$(( ND_BOX_W - tlen - 5 ))
    [ $pad -lt 2 ] && pad=2
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
        [ "$v" = "none" ] && v="bare-metal"
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
#  Базовые хелперы и детекторы
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
        if [ "$src_script" != "$BIN_PATH" ]; then
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

get_server_ip() {
    local ip
    ip=$(curl -s -4 --connect-timeout 4 ifconfig.io 2>/dev/null | tr -d '[:space:]') || \
    ip=$(curl -s -4 --connect-timeout 4 icanhazip.com 2>/dev/null | tr -d '[:space:]') || \
    ip=$(curl -s -4 --connect-timeout 4 ipecho.net/plain 2>/dev/null | tr -d '[:space:]') || \
    ip=$(hostname -I 2>/dev/null | awk '{print $1}') || \
    ip="127.0.0.1"
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
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
        return 0
    fi
    if [[ "$ip" =~ : ]]; then
        return 0
    fi
    return 1
}

get_saved_panel_ip() {
    local pip="${CFG_PANEL_IP:-}"
    if [ -z "$pip" ] && [ -f "$REMNANODE_DIR/.env" ]; then
        pip=$(grep -E '^PANEL_IP=' "$REMNANODE_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    echo "$pip"
}

get_saved_node_port() {
    local nport="${DETAIL_REMNANODE_PORT:-}"
    if [ -z "$nport" ] && [ -f "$REMNANODE_DIR/.env" ]; then
        nport=$(grep -E '^NODE_PORT=' "$REMNANODE_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    echo "${nport:-3000}"
}

get_saved_caddy_port() {
    local cport="${DETAIL_CADDY_PORT:-}"
    if [ -z "$cport" ] && [ -f "$CADDY_DIR/.env" ]; then
        cport=$(grep -E '^SELF_STEAL_PORT=' "$CADDY_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    echo "${cport:-$DEFAULT_PORT}"
}

get_saved_caddy_domain() {
    local cdom="${DETAIL_CADDY_DOMAIN:-}"
    if [ -z "$cdom" ] && [ -f "$CADDY_DIR/.env" ]; then
        cdom=$(grep -E '^SELF_STEAL_DOMAIN=' "$CADDY_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'\''' || true)
    fi
    echo "$cdom"
}

spinner() {
    local pid=$1
    local msg="${2:-Выполнение...}"
    local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    if [ "${NON_INTERACTIVE:-false}" = true ]; then
        wait "$pid" 2>/dev/null
        return $?
    fi

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${ORANGE}%s${NC} ${WHITE}%s${NC}" "${frames[$i]}" "$msg"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
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
    spinner "$pid" "$msg"
    return $?
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
        read -p "  ${ORANGE}▸${NC} $prompt" -r _choice
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
        [[ "$val" =~ ^[Yy]$ ]] && return 0 || return 1
    fi

    while true; do
        read -p "  ${ORANGE}▸${NC} $prompt" -r _answer
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
    if [ -f /etc/lsb-release ]; then
        OS=$(lsb_release -si)
    elif [ -f /etc/os-release ]; then
        OS=$(awk -F= '/^NAME=/{print $2}' /etc/os-release | tr -d '"')
        [[ "$OS" == "Amazon Linux" ]] && OS="Amazon"
    elif [ -f /etc/redhat-release ]; then
        OS=$(awk '{print $1}' /etc/redhat-release)
    elif [ -f /etc/arch-release ]; then
        OS="Arch"
    else
        log_error "Неподдерживаемая операционная система"
        exit 1
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
    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "AlmaLinux"* ]] || [[ "$OS" == "Amazon"* ]]; then
        PKG_MANAGER="yum"
    elif [[ "$OS" == "Fedora"* ]]; then
        PKG_MANAGER="dnf"
    elif [[ "$OS" == "Arch"* ]]; then
        PKG_MANAGER="pacman"
    else
        log_error "Неподдерживаемая ОС: $OS"
        exit 1
    fi
}

_init_env() {
    check_root
    self_install
    [ -z "$NODE_IP" ] && NODE_IP=$(get_server_ip)
    [ -z "$OS" ] && detect_os
    [ -z "$PKG_MANAGER" ] && detect_package_manager
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
           fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

wait_for_dpkg_lock() {
    local max_wait=180
    local waited=0
    ! is_dpkg_locked && return 0
    log_warning "Ожидание освобождения пакетного менеджера APT..."
    while [ $waited -lt $max_wait ]; do
        if ! is_dpkg_locked; then
            dpkg --configure -a >/dev/null 2>&1 && return 0
        fi
        sleep 3
        waited=$((waited + 3))
    done
    return 1
}

ensure_package_manager_available() {
    [[ "$PKG_MANAGER" != "apt-get" ]] && return 0
    local services_to_stop=("unattended-upgrades" "apt-daily.service" "apt-daily-upgrade.service")
    for svc in "${services_to_stop[@]}"; do
        systemctl is-active --quiet "$svc" 2>/dev/null && systemctl stop "$svc" 2>/dev/null || true
    done
    if is_dpkg_locked; then
        wait_for_dpkg_lock || {
            killall unattended-upgr apt-get apt 2>/dev/null || true
            rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock 2>/dev/null || true
            dpkg --configure -a >/dev/null 2>&1 || true
        }
    fi
}

restore_auto_updates() {
    [[ "${PKG_MANAGER:-}" != "apt-get" ]] && return 0
    systemctl start apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
}

install_package() {
    local package="$1"
    local install_log
    install_log=$(create_temp_file)
    local ok=false

    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        is_dpkg_locked && wait_for_dpkg_lock
        if [ "${_APT_UPDATED:-}" != "true" ]; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq >"$install_log" 2>&1 || true
            _APT_UPDATED=true
        fi
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$package" >>"$install_log" 2>&1 && ok=true
    elif [[ "$PKG_MANAGER" == "yum" ]] || [[ "$PKG_MANAGER" == "dnf" ]]; then
        $PKG_MANAGER install -y -q "$package" >"$install_log" 2>&1 && ok=true
    elif [[ "$PKG_MANAGER" == "pacman" ]]; then
        pacman -S --noconfirm --quiet "$package" >"$install_log" 2>&1 && ok=true
    fi

    rm -f "$install_log"
    [ "$ok" = true ] && return 0 || return 1
}

install_base_utilities() {
    local -a required=("curl" "wget" "openssl" "tar" "jq" "ethtool" "iproute2")
    for pkg in "${required[@]}"; do
        local bin="$pkg"
        [ "$pkg" = "iproute2" ] && bin="ss"
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
    available_mb=$(df -m "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}')
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
            [ -f "$f" ] && cp -f "$f" "$backup_dir/" 2>/dev/null || true
        done
        chmod 700 "$backup_dir"
        log_info "Бэкап сохранен: $backup_dir"
    fi
}

load_config_file() {
    local config_file="${1:-$CONFIG_FILE}"
    if [ -f "$config_file" ]; then
        log_info "Загрузка конфигурации из $config_file"
        local _allowed_vars="CFG_SECRET_KEY CFG_NODE_PORT CFG_PANEL_IP CFG_INSTALL_XRAY CFG_DOMAIN CFG_CERT_TYPE CFG_CLOUDFLARE_TOKEN CFG_CADDY_PORT CFG_APPLY_NETWORK CFG_SETUP_UFW CFG_INSTALL_FAIL2BAN NON_INTERACTIVE"
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
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

    # Сброс файла находок
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

    # [1] CPU Cores & Load Average
    local cores load1
    cores=$(nproc 2>/dev/null || echo 1)
    load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0.00")
    if awk "BEGIN {exit !($load1 < $cores * 1.5)}"; then
        _chk_ok "01. CPU & Load Average" "${cores} vCPU, LA 1m: ${load1}"
    else
        _chk_warn "01. CPU & Load Average" "Высокая нагрузка: LA ${load1} на ${cores} vCPU"
    fi

    # [2] CPU Steal Time (проверка оверселлинга хостера)
    local steal="0.0"
    if [ -r /proc/stat ]; then
        local s1 t1 s2 t2
        read -r _ u1 n1 sy1 id1 io1 ir1 so1 st1 _ < /proc/stat
        s1=${st1:-0}; t1=$((u1+n1+sy1+id1+io1+ir1+so1+s1))
        sleep 0.2
        read -r _ u2 n2 sy2 id2 io2 ir2 so2 st2 _ < /proc/stat
        s2=${st2:-0}; t2=$((u2+n2+sy2+id2+io2+ir2+so2+s2))
        local dt=$((t2 - t1)) ds=$((s2 - s1))
        [ $dt -gt 0 ] && steal=$(awk "BEGIN {printf \"%.1f\", ($ds * 100.0) / $dt}")
    fi
    if awk "BEGIN {exit !($steal < 5.0)}"; then
        _chk_ok "02. CPU Steal Time" "${steal}% (хост не перегружен)"
    elif awk "BEGIN {exit !($steal < 15.0)}"; then
        _chk_warn "02. CPU Steal Time" "${steal}% (заметен оверселлинг гипервизора)"
    else
        _chk_fail "02. CPU Steal Time" "${steal}% (критический Steal CPU у хостера!)"
    fi

    # [3] Память RAM + Swap / Zram
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

    # [4] Дисковое пространство и Inodes
    local disk_mb inode_use
    disk_mb=$(df -m / | awk 'NR==2 {print $4}')
    inode_use=$(df -i / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    if [ "${disk_mb:-0}" -ge 1024 ] && [ "${inode_use:-0}" -lt 85 ]; then
        _chk_ok "04. Диск и Inodes (/)" "Свободно ${disk_mb} МБ, Inodes: ${inode_use}%"
    else
        _chk_warn "04. Диск и Inodes (/)" "Свободно ${disk_mb} МБ, Inodes: ${inode_use}%"
    fi

    # [5] Файловые дескрипторы (FD Limits)
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

    # [6] TCP Congestion Control (BBR)
    local tcp_cc
    tcp_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "cubic")
    if [[ "$tcp_cc" =~ ^bbr ]]; then
        _chk_ok "06. TCP Congestion" "${tcp_cc} активен"
    else
        _chk_fail "06. TCP Congestion" "${tcp_cc} (требуется BBR / BBRv3)"
        _mark_finding "NEED_SYSCTL"
    fi

    # [7] Packet Scheduler (qdisc)
    local qdisc
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "pfifo_fast")
    if [[ "$qdisc" == "fq" ]] || [[ "$qdisc" == "fq_pie" ]] || [[ "$qdisc" == "cake" ]]; then
        _chk_ok "07. Дисциплина очереди" "default_qdisc = ${qdisc}"
    else
        _chk_warn "07. Дисциплина очереди" "default_qdisc = ${qdisc} (рекомендуется fq)"
        _mark_finding "NEED_SYSCTL"
    fi

    # [8] Буферы сокетов BDP (rmem_max / wmem_max)
    local rmem_max
    rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null || echo 0)
    if [ "$rmem_max" -ge 16777216 ]; then
        _chk_ok "08. Буферы сокетов BDP" "rmem_max = $((rmem_max / 1048576)) МБ"
    else
        _chk_warn "08. Буферы сокетов BDP" "rmem_max = $((rmem_max / 1024)) КБ (узкое окно для 1Гбит/с+)"
        _mark_finding "NEED_SYSCTL"
    fi

    # [9] TCP Fast Open & Slow Start After Idle
    local tfo ss_idle
    tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo 0)
    ss_idle=$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null || echo 1)
    if [ "$tfo" -ge 3 ] && [ "$ss_idle" -eq 0 ]; then
        _chk_ok "09. TFO & SlowStart Idle" "tcp_fastopen=${tfo}, slow_start_after_idle=0"
    else
        _chk_warn "09. TFO & SlowStart Idle" "fastopen=${tfo}, slow_start_after_idle=${ss_idle}"
        _mark_finding "NEED_SYSCTL"
    fi

    # [10] TIME_WAIT Reuse & Ephemeral Ports
    local tw_reuse port_range
    tw_reuse=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo 0)
    port_range=$(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null | tr '\t' ' ')
    if [ "$tw_reuse" -ge 1 ]; then
        _chk_ok "10. TIME_WAIT & Порты" "tw_reuse=${tw_reuse}, range: ${port_range}"
    else
        _chk_warn "10. TIME_WAIT & Порты" "tcp_tw_reuse=${tw_reuse} (риск исчерпания сокетов)"
        _mark_finding "NEED_SYSCTL"
    fi

    # [11] Очереди Сокетов (somaxconn & syn_backlog)
    local somax syn_bl
    somax=$(sysctl -n net.core.somaxconn 2>/dev/null || echo 128)
    syn_bl=$(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null || echo 128)
    if [ "$somax" -ge 8192 ] && [ "$syn_bl" -ge 8192 ]; then
        _chk_ok "11. Очереди SYN/Accept" "somaxconn=${somax}, syn_backlog=${syn_bl}"
    else
        _chk_warn "11. Очереди SYN/Accept" "somaxconn=${somax}, syn_backlog=${syn_bl} (мало для пиков)"
        _mark_finding "NEED_SYSCTL"
    fi

    # [12] TCP MTU Probing & Notsent Lowat
    local mtu_p lowat
    mtu_p=$(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null || echo 0)
    lowat=$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null || echo 4294967295)
    if [ "$mtu_p" -ge 1 ] && [ "$lowat" -le 131072 ]; then
        _chk_ok "12. MTU Probing & Lowat" "mtu_probing=${mtu_p}, notsent_lowat=${lowat}"
    else
        _chk_warn "12. MTU Probing & Lowat" "mtu_probing=${mtu_p}, notsent_lowat не ограничен"
        _mark_finding "NEED_SYSCTL"
    fi

    # [13] Таблица отслеживания соединений nf_conntrack
    local ct_max ct_cnt
    ct_max=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo 0)
    ct_cnt=$(sysctl -n net.netfilter.nf_conntrack_count 2>/dev/null || echo 0)
    if [ "$ct_max" -eq 0 ] || [ "$ct_max" -ge 262144 ]; then
        _chk_ok "13. Таблица nf_conntrack" "Активно: ${ct_cnt} / Лимит: ${ct_max:-модуль не загружен}"
    else
        _chk_warn "13. Таблица nf_conntrack" "Лимит мал: ${ct_cnt}/${ct_max} (риск дропа пакетов)"
        _mark_finding "NEED_SYSCTL"
    fi
    box_bottom
    echo

    # ── Блок 3: Сетевой интерфейс, RPS, NIC, MSS, Сервисы (14-18) ──
    box_top "3/5 · СЕТЕВАЯ КАРТА, RPS, MSS И СИСТЕМНЫЕ СЛУЖБЫ (ЧЕКИ 14–18)"
    local iface
    iface=$(detect_default_iface)

    # [14] Receive Packet Steering (RPS)
    local rps_val="0"
    if [ -n "$iface" ] && [ -r "/sys/class/net/${iface}/queues/rx-0/rps_cpus" ]; then
        rps_val=$(cat "/sys/class/net/${iface}/queues/rx-0/rps_cpus" 2>/dev/null | tr -d '0,' || true)
    fi
    if [ "$cores" -le 1 ] || [ -n "$rps_val" ]; then
        _chk_ok "14. Балансировка RPS/RFS" "Активна на интерфейсе ${iface:-?}"
    else
        _chk_warn "14. Балансировка RPS/RFS" "RPS выключен на ${iface:-eth0} (вся сеть на 1 ядре CPU)"
        _mark_finding "NEED_RPS"
    fi

    # [15] NIC Offloads (GRO / GSO / TSO) и txqueuelen
    local txq="0"
    [ -n "$iface" ] && [ -r "/sys/class/net/${iface}/tx_queue_len" ] && txq=$(cat "/sys/class/net/${iface}/tx_queue_len" 2>/dev/null || echo 0)
    if [ "${txq:-0}" -ge 5000 ]; then
        _chk_ok "15. Очередь NIC (txqueuelen)" "${iface}: txqueuelen = ${txq}"
    else
        _chk_warn "15. Очередь NIC (txqueuelen)" "${iface:-eth0}: txqueuelen = ${txq} (рекомендуется >= 5000)"
        _mark_finding "NEED_NIC"
    fi

    # [16] iptables TCPMSS Clamp to PMTU
    if command -v iptables >/dev/null 2>&1 && iptables -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
        _chk_ok "16. TCPMSS Clamp to PMTU" "Правило mangle OUTPUT активно"
    else
        _chk_warn "16. TCPMSS Clamp to PMTU" "Не активно (возможны зависания TLS при узком MTU)"
        _mark_finding "NEED_MSS"
    fi

    # [17] Демон распределения прерываний irqbalance
    if [ "$cores" -le 1 ] || systemctl is-active --quiet irqbalance 2>/dev/null; then
        _chk_ok "17. Служба irqbalance" "Активна"
    else
        _chk_warn "17. Служба irqbalance" "Не запущена (прерывания NIC не распределяются)"
        _mark_finding "NEED_IRQBALANCE"
    fi

    # [18] Лимиты systemd-journald
    if [ -f "/etc/systemd/journald.conf.d/${ND_DROPIN_PREFIX}.conf" ] || grep -Eq '^[[:space:]]*SystemMaxUse=' /etc/systemd/journald.conf 2>/dev/null; then
        _chk_ok "18. Журнал systemd-journald" "Размер логов ограничен"
    else
        _chk_warn "18. Журнал systemd-journald" "SystemMaxUse не задан (логи могут забить диск)"
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

    # [19] Docker Engine
    if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
        _chk_ok "19. Служба Docker Engine" "Работает ($(docker --version | awk '{print $3}' | tr -d ','))"
    else
        _chk_fail "19. Служба Docker Engine" "Docker не установлен или не запущен"
    fi

    # [20] Контейнер RemnawaveNode и его ulimits
    if [ -f "$REMNANODE_DIR/docker-compose.yml" ] && docker compose --project-directory "$REMNANODE_DIR" ps 2>/dev/null | grep -qE "Up|running"; then
        if ss -tlnp 2>/dev/null | grep -q ":${node_port} "; then
            _chk_ok "20. Контейнер RemnawaveNode" "Запущен, слушает порт ${node_port}/tcp"
        else
            _chk_warn "20. Контейнер RemnawaveNode" "Контейнер Up, но порт ${node_port}/tcp не слушается"
        fi
    else
        _chk_fail "20. Контейнер RemnawaveNode" "Не установлен или остановлен"
    fi

    # [21] Контейнер Caddy Selfsteal
    if [ -f "$CADDY_DIR/docker-compose.yml" ] && docker compose --project-directory "$CADDY_DIR" ps 2>/dev/null | grep -qE "Up|running"; then
        _chk_ok "21. Контейнер Caddy Selfsteal" "Запущен (домен: ${caddy_domain:-?})"
    else
        _chk_fail "21. Контейнер Caddy Selfsteal" "Не установлен или остановлен"
    fi

    # [22] Изоляция сокета Caddy Selfsteal на 127.0.0.1
    if ss -tln 2>/dev/null | awk '{print $4}' | grep -q "^127\.0\.0\.1:${caddy_port}$"; then
        _chk_ok "22. Изоляция Selfsteal сокета" "Слушает строго на 127.0.0.1:${caddy_port}"
    elif ss -tln 2>/dev/null | grep -q ":${caddy_port} "; then
        _chk_fail "22. Изоляция Selfsteal сокета" "УТЕЧКА: порт ${caddy_port} слушает на внешнем интерфейсе!"
    else
        _chk_warn "22. Изоляция Selfsteal сокета" "Порт 127.0.0.1:${caddy_port} не прослушивается"
    fi

    # [23] Проверка SSL-сертификата Caddy
    local cert_status="не найден"
    if docker volume inspect caddy_data >/dev/null 2>&1 && [ -n "$caddy_domain" ]; then
        local clean_dom="${caddy_domain#\*.}"
        local cert_end
        cert_end=$(docker run --rm -v caddy_data:/data:ro alpine:latest \
            sh -c 'find /data/caddy/certificates -type f -name "*$1*.crt" | head -1' _ "$clean_dom" 2>/dev/null || true)
        if [ -n "$cert_end" ]; then
            cert_status="выпущен (${clean_dom})"
            _chk_ok "23. TLS-сертификат маскировки" "$cert_status"
        else
            _chk_warn "23. TLS-сертификат маскировки" "Сертификат для ${clean_dom} еще не получен"
        fi
    else
        _chk_warn "23. TLS-сертификат маскировки" "Том caddy_data или домен не настроен"
    fi
    box_bottom
    echo

    # ── Блок 5: Периметр безопасности и связность (Чеки 24-27) ────
    box_top "5/5 · ЗАЩИТА ПЕРИМЕТРА И СВЯЗНОСТЬ (ЧЕКИ 24–27)"
    local panel_ip
    panel_ip=$(get_saved_panel_ip)

    # [24] Статус UFW
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
        _chk_ok "24. Межсетевой экран UFW" "Активен (политика deny incoming)"
    else
        _chk_fail "24. Межсетевой экран UFW" "UFW выключен!"
        _mark_finding "NEED_UFW_FIX"
    fi

    # [25] Изоляция порта ноды (Strict Panel IP ACL)
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
        if ufw status 2>/dev/null | grep -E "^${node_port}(/tcp)?[[:space:]]+ALLOW[[:space:]]+Anywhere" >/dev/null 2>&1; then
            _chk_fail "25. ACL порта RemnaNode" "УЯЗВИМОСТЬ: порт ${node_port} открыт всему миру (Anywhere)!"
            _mark_finding "NEED_UFW_FIX"
        elif [ -n "$panel_ip" ] && ufw status 2>/dev/null | grep -E "${node_port}.*${panel_ip}" >/dev/null 2>&1; then
            _chk_ok "25. ACL порта RemnaNode" "Порт ${node_port}/tcp открыт ТОЛЬКО для ${panel_ip}"
        else
            _chk_warn "25. ACL порта RemnaNode" "Правило для панели (${panel_ip:-не задан}) не найдено в UFW"
            _mark_finding "NEED_UFW_FIX"
        fi
    else
        _chk_fail "25. ACL порта RemnaNode" "UFW неактивен, порт ${node_port} не защищен"
        _mark_finding "NEED_UFW_FIX"
    fi

    # [26] Статус Fail2ban и активных джейлов
    if command -v fail2ban-client >/dev/null 2>&1 && systemctl is-active --quiet fail2ban && fail2ban-client ping >/dev/null 2>&1; then
        local jails
        jails=$(fail2ban-client status 2>/dev/null | awk -F'Jail list:' '/Jail list:/ {gsub(/^[ \t]+/, "", $2); print $2}')
        _chk_ok "26. Защита Fail2ban" "Активен (Jails: ${jails:-нет})"
    else
        _chk_fail "26. Защита Fail2ban" "Fail2ban не запущен или аварийно остановился"
        _mark_finding "NEED_F2B_FIX"
    fi

    # [27] Внешняя связность IPv4 и DNS
    if [ "$mode" != "--no-net" ]; then
        if curl -fsSIL --connect-timeout 4 --max-time 6 https://1.1.1.1 >/dev/null 2>&1; then
            _chk_ok "27. Внешняя связность TLS" "HTTPS до 1.1.1.1 работает штатно"
        else
            _chk_fail "27. Внешняя связность TLS" "Сбой исходящего HTTPS-соединения"
        fi
    else
        _chk_ok "27. Внешняя связность TLS" "Пропущено (--no-net)"
    fi
    box_bottom
    echo

    # ── Итоговый вердикт ──────────────────────────────────────────
    box_top "ВЕРДИКТ ДИАГНОСТИКИ (27 ЧЕКОВ)"
    box_row "Успешно: ${GREEN}${BOLD}${pass_cnt}${NC}   |   Предупреждений: ${YELLOW}${BOLD}${warn_cnt}${NC}   |   Ошибок: ${RED}${BOLD}${fail_cnt}${NC}"
    if [ $fail_cnt -eq 0 ] && [ $warn_cnt -eq 0 ]; then
        box_row "${GREEN}${BOLD}Идеальное состояние! Узел полностью оптимизирован и защищен.${NC}"
    else
        box_row "${SLATE}Для авто-исправления сетевых находок выполните: ${ORANGE}${BOLD}node-mgr optimize --from-findings${NC}"
        box_row "${SLATE}Для применения полного профиля оптимизации:    ${ORANGE}${BOLD}node-mgr optimize --all${NC}"
    fi
    box_bottom
    echo
}

# ═══════════════════════════════════════════════════════════════════
#  МОДУЛЬ 2: ГЛУБОКАЯ ОПТИМИЗАЦИЯ УЗЛА (optimize / rollback / bbr3)
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
[ "$cores" -le 1 ] && exit 0
mask=$(printf '%x' $(( (1 << cores) - 1 )))
entries=32768
sysctl -w net.core.rps_sock_flow_entries=$entries >/dev/null 2>&1 || true
for iface_dir in /sys/class/net/*; do
    iface=$(basename "$iface_dir")
    [ "$iface" = "lo" ] && continue
    rx_cnt=$(ls -d "${iface_dir}/queues/rx-"* 2>/dev/null | wc -l)
    [ "$rx_cnt" -eq 0 ] && continue
    flow_cnt=$(( entries / rx_cnt ))
    for q in "${iface_dir}/queues/rx-"*; do
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
    log_info "Тюнинг сетевой карты (GRO/GSO/TSO offloads & txqueuelen 10000)..."
    command -v ethtool >/dev/null 2>&1 || install_package ethtool >/dev/null 2>&1 || true
    cat > /usr/local/sbin/node-mgr-nic << 'EOF'
#!/usr/bin/env bash
iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
[ -z "$iface" ] && exit 0
ip link set dev "$iface" txqueuelen 10000 2>/dev/null || true
if command -v ethtool >/dev/null 2>&1; then
    ethtool -K "$iface" gro on gso on tso on 2>/dev/null || true
    ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
fi
EOF
    chmod 755 /usr/local/sbin/node-mgr-nic
    /usr/local/sbin/node-mgr-nic || true

    cat > /etc/systemd/system/node-diagnostic-nic.service << 'EOF'
[Unit]
Description=LissVPN NIC Offloads & Queue Tuning
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
    _log_fix "NIC offloads (GRO/GSO/TSO) & txqueuelen=10000 applied"
    log_success "Аппаратные оффлоады NIC и txqueuelen=10000 настроены"
}

opt_mss() {
    log_info "Включение iptables TCPMSS clamp to PMTU..."
    if command -v iptables >/dev/null 2>&1; then
        iptables -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
            iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
        iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
            iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
        _log_fix "iptables TCPMSS clamp-mss-to-pmtu enabled"
        log_success "Правило TCPMSS clamp-mss-to-pmtu добавлено"
    fi
}

opt_irqbalance() {
    local cores
    cores=$(nproc 2>/dev/null || echo 1)
    [ "$cores" -le 1 ] && return 0
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
modprobe zram num_devices=1 2>/dev/null || exit 0
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
            grep -q "^NEED_SYSCTL=1" "$FINDINGS_FILE"     && opt_sysctl
            grep -q "^NEED_LIMITS=1" "$FINDINGS_FILE"     && opt_limits
            grep -q "^NEED_RPS=1" "$FINDINGS_FILE"        && opt_rps
            grep -q "^NEED_NIC=1" "$FINDINGS_FILE"        && opt_nic
            grep -q "^NEED_MSS=1" "$FINDINGS_FILE"        && opt_mss
            grep -q "^NEED_IRQBALANCE=1" "$FINDINGS_FILE" && opt_irqbalance
            grep -q "^NEED_JOURNALD=1" "$FINDINGS_FILE"   && opt_journald
            grep -q "^NEED_ZRAM=1" "$FINDINGS_FILE"       && opt_zram
            grep -q "^NEED_UFW_FIX=1" "$FINDINGS_FILE"    && setup_ufw
            grep -q "^NEED_F2B_FIX=1" "$FINDINGS_FILE"    && install_fail2ban
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

    if ! prompt_yn "Установить пакет linux-xanmod-${xanmod_level} (потребуется ручная перезагрузка)? (y/n): " "y"; then
        return 0
    fi

    command -v gpg >/dev/null 2>&1 || install_package gnupg
    local xanmod_key="/usr/share/keyrings/xanmod-archive-keyring.gpg"
    curl -fsSL https://dl.xanmod.org/archive.key | gpg --dearmor --yes -o "$xanmod_key"
    echo "deb [signed-by=$xanmod_key] http://deb.xanmod.org releases main" > /etc/apt/sources.list.d/xanmod-release.list
    apt-get update -qq >/dev/null 2>&1

    log_info "Установка linux-xanmod-${xanmod_level}..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "linux-xanmod-${xanmod_level}"; then
        _log_fix "XanMod kernel (${xanmod_level}) installed"
        log_success "Ядро XanMod (${xanmod_level}) успешно установлено!"
        log_warning "Выполните 'reboot' в удобное время для загрузки с новым ядром и BBRv3."
    else
        log_error "Не удалось установить пакет ядра XanMod"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  МОДУЛЬ 3: УСТАНОВКА DOCKER, REMNANODE И CADDY SELFSTEAL
# ═══════════════════════════════════════════════════════════════════
install_docker() {
    if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
        log_success "Docker Engine уже установлен и работает"
        return 0
    fi

    [[ "$PKG_MANAGER" == "apt-get" ]] && wait_for_dpkg_lock

    log_info "Установка официального Docker Engine и Docker Compose v2..."
    local docker_install_log docker_script
    docker_install_log=$(create_temp_file)
    docker_script=$(create_temp_file)

    curl -fsSL https://get.docker.com -o "$docker_script" 2>/dev/null || return 1
    sh "$docker_script" >"$docker_install_log" 2>&1 &
    spinner $! "Установка Docker Engine..."

    systemctl enable --now docker >/dev/null 2>&1 || true
    sleep 2
    docker ps >/dev/null 2>&1 && return 0
    return 1
}

check_docker_compose() {
    local retries=0
    while [ $retries -lt 5 ]; do
        docker compose version >/dev/null 2>&1 && return 0
        sleep 2
        retries=$((retries + 1))
    done
    return 1
}

check_existing_remnanode() {
    [ -d "$REMNANODE_DIR" ] && [ -f "$REMNANODE_DIR/docker-compose.yml" ]
}

setup_logrotate() {
    command -v logrotate >/dev/null 2>&1 || install_package logrotate 2>/dev/null || true
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
    command -v unzip >/dev/null 2>&1 || install_package unzip || return 1

    local api_response latest_release
    api_response=$(curl -s --connect-timeout 10 --max-time 25 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null) || true
    latest_release=$(echo "$api_response" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    [ -z "$latest_release" ] && return 1

    local xray_filename="Xray-linux-$ARCH.zip"
    mkdir -p "$REMNANODE_DATA_DIR"
    download_with_progress "https://github.com/XTLS/Xray-core/releases/download/${latest_release}/${xray_filename}" "${REMNANODE_DATA_DIR}/${xray_filename}" "Загрузка Xray-core ${latest_release}..." || return 1

    unzip -o "${REMNANODE_DATA_DIR}/${xray_filename}" -d "$REMNANODE_DATA_DIR" >/dev/null 2>&1
    rm -f "${REMNANODE_DATA_DIR}/${xray_filename}"
    chmod +x "$REMNANODE_DATA_DIR/xray"
    log_success "Xray-core (${latest_release}) установлен в ${REMNANODE_DATA_DIR}/xray"
    return 0
}

install_remnanode() {
    print_header "УСТАНОВКА И НАСТРОЙКА REMNANODE"

    if check_existing_remnanode; then
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

    mkdir -p "$REMNANODE_DIR" "$REMNANODE_DATA_DIR" /var/log/remnanode

    local SECRET_KEY_VALUE=""
    if [ "${NON_INTERACTIVE:-false}" = true ] && [ -n "$CFG_SECRET_KEY" ]; then
        SECRET_KEY_VALUE="$CFG_SECRET_KEY"
    else
        echo -e "  ${ORANGE}🔑 Вставьте SECRET_KEY из панели Remnawave (нажмите ENTER на пустой строке для завершения):${NC}"
        while IFS= read -r line; do
            [ -z "$line" ] && break
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
        read -p "  ${ORANGE}▸${NC} Порт управления NODE_PORT [3000]: " -r NODE_PORT
        NODE_PORT=${NODE_PORT:-3000}
    fi
    DETAIL_REMNANODE_PORT="$NODE_PORT"

    local PANEL_IP_VALUE="${CFG_PANEL_IP:-}"
    if [ "${NON_INTERACTIVE:-false}" != true ] || [ -z "$PANEL_IP_VALUE" ]; then
        local current_pip; current_pip=$(get_saved_panel_ip)
        while [ -z "$PANEL_IP_VALUE" ]; do
            read -p "  ${ORANGE}▸${NC} Белый IP-адрес панели Remnawave (для ACL порта ${NODE_PORT})${current_pip:+ [Enter=$current_pip]}: " -r PANEL_IP_VALUE
            PANEL_IP_VALUE="${PANEL_IP_VALUE:-$current_pip}"
            PANEL_IP_VALUE=$(echo "$PANEL_IP_VALUE" | tr -d '[:space:]')
            if ! validate_ip_or_cidr "$PANEL_IP_VALUE"; then
                log_warning "Введите корректный IP-адрес панели!"
                PANEL_IP_VALUE=""
            fi
        done
    fi
    DETAIL_PANEL_IP="$PANEL_IP_VALUE"
    CFG_PANEL_IP="$PANEL_IP_VALUE"

    local has_host_xray=false
    if install_xray_core; then
        has_host_xray=true
    fi

    umask 077
    cat > "$REMNANODE_DIR/.env" << EOF
NODE_PORT=$NODE_PORT
PANEL_IP=$PANEL_IP_VALUE
SECRET_KEY=$SECRET_KEY_VALUE
EOF
    chmod 600 "$REMNANODE_DIR/.env"
    umask 022

    cat > "$REMNANODE_DIR/docker-compose.yml" << EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: ghcr.io/remnawave/node:latest
    env_file:
      - .env
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"
    volumes:
      - /var/log/remnanode:/var/log/remnanode
      - /dev/shm:/dev/shm
EOF

    if [ "$has_host_xray" = true ] && [ -f "$REMNANODE_DATA_DIR/xray" ]; then
        echo "      - $REMNANODE_DATA_DIR/xray:/usr/local/bin/xray" >> "$REMNANODE_DIR/docker-compose.yml"
        [ -f "$REMNANODE_DATA_DIR/geoip.dat" ]   && echo "      - $REMNANODE_DATA_DIR/geoip.dat:/usr/local/share/xray/geoip.dat" >> "$REMNANODE_DIR/docker-compose.yml"
        [ -f "$REMNANODE_DATA_DIR/geosite.dat" ] && echo "      - $REMNANODE_DATA_DIR/geosite.dat:/usr/local/share/xray/geosite.dat" >> "$REMNANODE_DIR/docker-compose.yml"
    fi

    setup_logrotate
    docker rm -f remnanode 2>/dev/null || true
    docker compose --project-directory "$REMNANODE_DIR" pull --quiet 2>/dev/null || true
    docker compose --project-directory "$REMNANODE_DIR" up -d --remove-orphans

    if check_container_health "$REMNANODE_DIR" "remnanode" 30; then
        log_success "Контейнер remnanode успешно запущен (порт: $NODE_PORT)"
        STATUS_REMNANODE="установлен"
    else
        log_error "Контейнер remnanode не вышел в статус Up"
        STATUS_REMNANODE="ошибка"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  Caddy Selfsteal + 11 SNI шаблонов + Anti-Fingerprint
# ═══════════════════════════════════════════════════════════════════
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

check_existing_caddy() {
    [ -d "$CADDY_DIR" ] && [ -f "$CADDY_DIR/docker-compose.yml" ]
}

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

download_template() {
    local template_folder="$1"
    local template_label="${2:-$1}"
    log_info "Установка шаблона маскировки: ${template_label}..."

    mkdir -p "$CADDY_HTML_DIR"
    find "${CADDY_HTML_DIR:?}" -mindepth 1 -delete 2>/dev/null || true

    local base_url="https://raw.githubusercontent.com/Case211/remnanode-install/main/sni-templates/$template_folder"
    if curl -fsSL --connect-timeout 8 "$base_url/index.html" -o "$CADDY_HTML_DIR/index.html" 2>/dev/null; then
        curl -fsSL --connect-timeout 5 "$base_url/favicon.ico" -o "$CADDY_HTML_DIR/favicon.ico" 2>/dev/null || true
    else
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
    fi
    inject_antifingerprint_hash
}

select_and_download_template() {
    echo -e "  ${WHITE}Выберите HTML-шаблон для маскировки Reality:${NC}"
    local i=1
    for entry in "${TEMPLATES[@]}"; do
        printf "    ${ORANGE}%2d)${NC} %s\n" "$i" "${entry#*:}"
        i=$((i + 1))
    done
    printf "    ${ORANGE}%2d)${NC} ${YELLOW}Случайный шаблон${NC}\n" "$i"
    echo

    local tmpl_choice="$i"
    [ "${NON_INTERACTIVE:-false}" != true ] && prompt_choice "Номер шаблона [1-$i]: " "$i" tmpl_choice "$i"

    local entry
    if [ "$tmpl_choice" -eq "$i" ]; then
        entry="${TEMPLATES[$RANDOM % ${#TEMPLATES[@]}]}"
    else
        entry="${TEMPLATES[$((tmpl_choice - 1))]}"
    fi
    download_template "${entry%%:*}" "${entry#*:}"
}

validate_cloudflare_token() {
    local token="$1"
    local resp
    resp=$(curl -s --connect-timeout 8 --max-time 12 -H "Authorization: Bearer $token" "https://api.cloudflare.com/client/v4/user/tokens/verify" 2>/dev/null) || true
    echo "$resp" | grep -q '"success":true'
}

install_caddy_selfsteal() {
    print_header "УСТАНОВКА CADDY SELFSTEAL (REALITY CAMOUFLAGE)"

    if check_existing_caddy; then
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

    # Гарантируем создание лог-файлов ДО запуска Caddy и Fail2ban
    mkdir -p "$CADDY_DIR" "$CADDY_HTML_DIR" "$CADDY_DIR/logs"
    touch "$CADDY_DIR/logs/access.log" "$CADDY_DIR/logs/default.log"
    chmod 644 "$CADDY_DIR/logs/access.log" "$CADDY_DIR/logs/default.log"

    local original_domain="${CFG_DOMAIN:-}"
    if [ "${NON_INTERACTIVE:-false}" != true ] || [ -z "$original_domain" ]; then
        while [ -z "$original_domain" ]; do
            read -p "  ${ORANGE}▸${NC} Домен маскировки (совпадает с serverNames в Xray): " -r original_domain
            original_domain=$(echo "$original_domain" | tr -d '[:space:]' | sed 's|^https\?://||;s|/.*$||')
            if ! [[ "$original_domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
                log_warning "Некорректный формат домена!"
                original_domain=""
            fi
        done
    fi
    DETAIL_CADDY_DOMAIN="$original_domain"

    local cert_choice="${CFG_CERT_TYPE:-1}"
    if [ "${NON_INTERACTIVE:-false}" != true ]; then
        echo -e "  ${WHITE}Тип SSL-сертификата:${NC}"
        echo -e "    ${ORANGE}1)${NC} Обычный HTTP-01 (Let's Encrypt, порт 80)"
        echo -e "    ${ORANGE}2)${NC} Wildcard DNS-01 (Cloudflare API Token)"
        prompt_choice "Выбор [1-2]: " 2 cert_choice "1"
    fi

    local domain="$original_domain"
    local root_domain=""

    if [ "$cert_choice" = "2" ]; then
        USE_WILDCARD=true
        CADDY_IMAGE="caddybuilds/caddy-cloudflare:latest"
        CLOUDFLARE_API_TOKEN="${CFG_CLOUDFLARE_TOKEN:-}"
        while [ -z "$CLOUDFLARE_API_TOKEN" ]; do
            read -s -p "  ${ORANGE}▸${NC} Cloudflare API Token: " -r CLOUDFLARE_API_TOKEN
            echo
            CLOUDFLARE_API_TOKEN=$(echo "$CLOUDFLARE_API_TOKEN" | tr -d '\r\n ')
        done
        if validate_cloudflare_token "$CLOUDFLARE_API_TOKEN"; then
            log_success "Cloudflare API Token проверен"
        else
            log_warning "Не удалось подтвердить токен через API Cloudflare"
        fi
        root_domain=$(echo "$original_domain" | sed 's/^[^.]*\.//')
        domain="*.$root_domain"
    else
        USE_WILDCARD=false
        CADDY_IMAGE="caddy:${CADDY_VERSION}"
    fi

    local port="${CFG_CADDY_PORT:-$DEFAULT_PORT}"
    if [ "${NON_INTERACTIVE:-false}" != true ]; then
        read -p "  ${ORANGE}▸${NC} Внутренний HTTPS порт Caddy [${DEFAULT_PORT}]: " -r port
        port="${port:-$DEFAULT_PORT}"
    fi
    DETAIL_CADDY_PORT="$port"

    umask 077
    cat > "$CADDY_DIR/.env" << EOF
SELF_STEAL_DOMAIN=$domain
SELF_STEAL_PORT=$port
EOF
    [ "$USE_WILDCARD" = true ] && printf 'CLOUDFLARE_API_TOKEN=%s\n' "$CLOUDFLARE_API_TOKEN" >> "$CADDY_DIR/.env"
    chmod 600 "$CADDY_DIR/.env"
    umask 022

    cat > "$CADDY_DIR/docker-compose.yml" << EOF
services:
  caddy:
    image: ${CADDY_IMAGE}
    container_name: caddy-selfsteal
    restart: unless-stopped
    network_mode: "host"
    env_file:
      - .env
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ${CADDY_HTML_DIR}:/var/www/html
      - ./logs:/var/log/caddy
      - caddy_data:/data
      - caddy_config:/config
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  caddy_data:
    name: caddy_data
  caddy_config:
    name: caddy_config
EOF

    if [ "$USE_WILDCARD" = true ]; then
        cat > "$CADDY_DIR/Caddyfile" << 'EOF'
{
	https_port {$SELF_STEAL_PORT}
	default_bind 127.0.0.1
	auto_https disable_redirects
}

:80 {
	bind 0.0.0.0
	redir https://{host}{uri} permanent
}

https://{$SELF_STEAL_DOMAIN} {
	tls {
		dns cloudflare {env.CLOUDFLARE_API_TOKEN}
	}
	root * /var/www/html
	try_files {path} /index.html
	file_server
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
		X-Content-Type-Options "nosniff"
		-Server
	}
	log {
		output file /var/log/caddy/access.log {
			roll_size 10MB
			roll_keep 5
		}
		format json
	}
}
EOF
    else
        cat > "$CADDY_DIR/Caddyfile" << 'EOF'
{
	https_port {$SELF_STEAL_PORT}
	default_bind 127.0.0.1
	auto_https disable_redirects
}

http://{$SELF_STEAL_DOMAIN} {
	bind 0.0.0.0
	redir https://{host}{uri} permanent
}

https://{$SELF_STEAL_DOMAIN} {
	tls {
		issuer acme {
			disable_tlsalpn_challenge
		}
	}
	root * /var/www/html
	try_files {path} /index.html
	file_server
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
		X-Content-Type-Options "nosniff"
		-Server
	}
	log {
		output file /var/log/caddy/access.log {
			roll_size 10MB
			roll_keep 5
		}
		format json
	}
}

:80 {
	bind 0.0.0.0
	respond 204
	log off
}
EOF
    fi

    echo
    select_and_download_template || true

    # Принудительное удаление старого контейнера во избежание конфликта имен Docker
    docker rm -f caddy-selfsteal 2>/dev/null || true
    docker compose --project-directory "$CADDY_DIR" pull --quiet 2>/dev/null || true
    docker compose --project-directory "$CADDY_DIR" up -d --remove-orphans

    if check_container_health "$CADDY_DIR" "caddy" 30; then
        log_success "Caddy Selfsteal запущен на 127.0.0.1:${port}"
        STATUS_CADDY="установлен"
    else
        log_error "Caddy Selfsteal не запустился. Проверьте: docker logs caddy-selfsteal"
        STATUS_CADDY="ошибка"
    fi
}

change_template() {
    _init_env
    if [ ! -d "$CADDY_HTML_DIR" ]; then
        log_error "Caddy не установлен ($CADDY_HTML_DIR отсутствует)"
        return 1
    fi
    print_header "СМЕНА HTML-ШАБЛОНА МАСКИРОВКИ"
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

    command -v ufw >/dev/null 2>&1 || install_package ufw || { STATUS_UFW="ошибка"; return 1; }

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
        read -p "  ${ORANGE}▸${NC} Введите IP-адрес панели Remnawave (для доступа к порту ${node_port}): " -r panel_ip
        panel_ip=$(echo "$panel_ip" | tr -d '[:space:]')
        ! validate_ip_or_cidr "$panel_ip" && panel_ip=""
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
    [ "$ssh_port" != "22" ] && ufw allow 22/tcp comment 'SSH Default' >/dev/null 2>&1 || true

    # Удаляем любые публичные правила на порт ноды и открываем СТРОГО для IP панели
    ufw delete allow "${node_port}/tcp" >/dev/null 2>&1 || true
    ufw delete allow "${node_port}" >/dev/null 2>&1 || true
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

    command -v fail2ban-client >/dev/null 2>&1 || install_package fail2ban || { STATUS_FAIL2BAN="ошибка"; return 1; }
    [[ "$PKG_MANAGER" == "apt-get" ]] && install_package python3-systemd >/dev/null 2>&1 || true

    # 1. Полная зачистка старых конфликтующих конфигов и зависших процессов
    systemctl stop fail2ban 2>/dev/null || true
    pkill -9 -f fail2ban-server 2>/dev/null || true
    rm -f /var/run/fail2ban/fail2ban.sock /run/fail2ban/fail2ban.sock /var/run/fail2ban/fail2ban.pid 2>/dev/null || true
    rm -f /etc/fail2ban/jail.d/node-mgr.local /etc/fail2ban/jail.d/defaults-debian.conf /etc/fail2ban/jail.d/customisation.local 2>/dev/null || true

    # 2. Гарантируем наличие лог-файла Caddy до старта Fail2ban
    mkdir -p "$CADDY_DIR/logs" /var/log/remnanode /etc/fail2ban/filter.d /etc/fail2ban/action.d
    touch "$CADDY_DIR/logs/access.log"
    chmod 644 "$CADDY_DIR/logs/access.log"

    # 3. Гарантируем наличие корректного /etc/fail2ban/action.d/ufw.conf
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

    # 4. Фильтр для JSON-логов Caddy
    cat > /etc/fail2ban/filter.d/caddy-status.conf << 'EOF'
[Definition]
failregex = ^.*"remote_ip":"<HOST>".*"status":(400|401|403|404|405|444)\b.*$
            ^.*"client_ip":"<HOST>".*"status":(400|401|403|404|405|444)\b.*$
            ^.*"status":(400|401|403|404|405|444)\b.*"remote_ip":"<HOST>".*$
            ^.*"status":(400|401|403|404|405|444)\b.*"client_ip":"<HOST>".*$
ignoreregex =
EOF

    # 5. Определение бэкенда для sshd
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
#  Статус, Сводка, Обновление, Удаление
# ═══════════════════════════════════════════════════════════════════
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

    if check_existing_remnanode && docker compose --project-directory "$REMNANODE_DIR" ps 2>/dev/null | grep -qE "Up|running"; then
        box_row "${GREEN}${BOLD}[ RUNNING ]${NC} Контейнер remnanode (порт ${node_p})"
    else
        box_row "${YELLOW}${BOLD}[ STOPPED ]${NC} Контейнер remnanode"
    fi

    if check_existing_caddy && docker compose --project-directory "$CADDY_DIR" ps 2>/dev/null | grep -qE "Up|running"; then
        box_row "${GREEN}${BOLD}[ RUNNING ]${NC} Контейнер caddy-selfsteal (127.0.0.1:${caddy_p})"
    else
        box_row "${YELLOW}${BOLD}[ STOPPED ]${NC} Контейнер caddy-selfsteal"
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

    box_top "НАЛОЖЕННЫЕ ОПТИМИЗАЦИИ (NODE-MGR TOOLKIT)"
    local found=0 f
    for f in "/etc/sysctl.d/${ND_DROPIN_PREFIX}-sysctl.conf" \
             "/etc/security/limits.d/${ND_DROPIN_PREFIX}-limits.conf" \
             "/etc/modules-load.d/${ND_DROPIN_PREFIX}.conf" \
             "/etc/systemd/journald.conf.d/${ND_DROPIN_PREFIX}.conf"; do
        [ -e "$f" ] && { box_row "${GREEN}✔${NC} ${f}"; found=1; }
    done
    for svc in node-diagnostic-rps node-diagnostic-nic node-diagnostic-zram; do
        [ -e "/etc/systemd/system/${svc}.service" ] && { box_row "${GREEN}✔${NC} ${svc}.service"; found=1; }
    done
    if command -v iptables >/dev/null 2>&1 && iptables -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
        box_row "${GREEN}✔${NC} iptables TCPMSS clamp (mangle OUTPUT)"; found=1
    fi
    [ "$found" -eq 0 ] && box_row "${DIM}Оптимизации еще не наложены (запустите: node-mgr optimize --all)${NC}"
    box_bottom
    echo
}

show_installation_summary() {
    echo
    box_top "ИТОГИ РАЗВЕРТЫВАНИЯ УЗЛА LISSVPN"
    box_kv "Сетевой стек Highload" "$STATUS_NETWORK"
    box_kv "Docker Engine" "$STATUS_DOCKER"
    box_kv "RemnawaveNode" "$STATUS_REMNANODE (порт: $(get_saved_node_port))"
    box_kv "Caddy Selfsteal" "$STATUS_CADDY ($(get_saved_caddy_domain))"
    box_kv "UFW Firewall (ACL)" "$STATUS_UFW (панель: $(get_saved_panel_ip))"
    box_kv "Fail2ban" "$STATUS_FAIL2BAN"
    box_bottom
    echo
}

run_full_install() {
    _init_env
    print_header "ПОЛНАЯ УСТАНОВКА И ОПТИМИЗАЦИЯ УЗЛА [1/6 .. 6/6]"

    check_disk_space 500 "/opt" || { prompt_yn "Продолжить? (y/n): " "n" || exit 1; }
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

    echo -e "\n  ${ORANGE}${BOLD}[3/6] Установка RemnawaveNode${NC}"
    install_remnanode

    echo -e "\n  ${ORANGE}${BOLD}[4/6] Установка Caddy Selfsteal${NC}"
    install_caddy_selfsteal

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
    echo -e "    ${ORANGE}${BOLD}[3]${NC} RemnawaveNode + Xray-core"
    echo -e "    ${ORANGE}${BOLD}[4]${NC} Caddy Selfsteal + Шаблоны"
    echo -e "    ${ORANGE}${BOLD}[5]${NC} UFW Firewall (доступ к порту ноды только с IP панели)"
    echo -e "    ${ORANGE}${BOLD}[6]${NC} Fail2ban (починка конфига и перезапуск)"
    echo

    local selection_raw
    read -p "  ${ORANGE}▸${NC} Номера через пробел [1-6, Enter=все]: " -r selection_raw
    selection_raw="${selection_raw:-1 2 3 4 5 6}"

    ensure_package_manager_available
    _RESTORE_AUTO_UPDATES=true
    install_base_utilities

    for c in $selection_raw; do
        case "$c" in
            1) run_optimize "--all" ;;
            2) install_docker && check_docker_compose && STATUS_DOCKER="установлен" ;;
            3) install_remnanode ;;
            4) install_caddy_selfsteal ;;
            5) setup_ufw ;;
            6) install_fail2ban ;;
        esac
    done

    restore_auto_updates
    _RESTORE_AUTO_UPDATES=false
    show_installation_summary
}

update_components() {
    _init_env
    print_header "ОБНОВЛЕНИЕ КОМПОНЕНТОВ УЗЛА"
    if [ -f "$REMNANODE_DIR/docker-compose.yml" ]; then
        log_info "Обновление образа RemnawaveNode и ядра Xray-core..."
        install_xray_core || true
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
    [ -f "$REMNANODE_DIR/.env" ] && cfg_secret=$(grep "^SECRET_KEY=" "$REMNANODE_DIR/.env" 2>/dev/null | cut -d= -f2- || true)

    umask 077
    cat > "$output" << EOF
# LissVPN Node Orchestrator Configuration
CFG_SECRET_KEY="${cfg_secret}"
CFG_NODE_PORT=$(get_saved_node_port)
CFG_PANEL_IP="$(get_saved_panel_ip)"
CFG_DOMAIN="$(get_saved_caddy_domain | sed 's/^\*\.//')"
CFG_CADDY_PORT=$(get_saved_caddy_port)
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
    read -p "  ${ORANGE}▸${NC} Введите 'YES' для подтверждения удаления: " -r confirm
    [ "$confirm" != "YES" ] && { log_info "Отменено."; return 0; }

    [ -f "$REMNANODE_DIR/docker-compose.yml" ] && docker compose --project-directory "$REMNANODE_DIR" down 2>/dev/null || true
    [ -f "$CADDY_DIR/docker-compose.yml" ] && docker compose --project-directory "$CADDY_DIR" down 2>/dev/null || true
    docker rm -f remnanode caddy-selfsteal 2>/dev/null || true

    run_rollback
    rm -f /etc/fail2ban/jail.local /etc/fail2ban/filter.d/caddy-status.conf
    systemctl restart fail2ban 2>/dev/null || true

    rm -rf "$REMNANODE_DIR" "$REMNANODE_DATA_DIR" "$CADDY_DIR" /var/log/remnanode /etc/logrotate.d/remnanode
    log_success "Все компоненты узла удалены."
}

show_help() {
    print_banner
    cat << 'HELP'

  Использование: node-mgr [КОМАНДА] [ОПЦИИ]

  Основные команды тулкита:
    diagnose [-q|--no-net]       Диагностика ноды (27 чеков, дашборд, вердикт)
    optimize [--all|--from-findings|--zram|--sysctl|--rps|--nic|--mss]
                                 Тюнинг ядра, BBR, лимитов FD, RPS/RFS, NIC, TCPMSS, Zram
    bbr3                         Установка ядра XanMod с поддержкой BBRv3
    rollback                     Откат всех наложенных оптимизаций
    status                       Показать состояние узла, контейнеров и артефактов
    install                      Полная пошаговая установка ноды под ключ
    selective                    Выборочная установка или починка отдельных модулей
    change-template              Смена HTML-шаблона маскировки Caddy Selfsteal
    update                       Обновление Docker-образов и бинарника Xray-core
    export-config [FILE]         Экспорт текущих настроек в конфиг-файл
    uninstall                    Удаление всех компонентов и откат настроек
    --config FILE                Автоматическая установка по конфиг-файлу
    help | --help                Показать эту справку
HELP
    echo
}

# ═══════════════════════════════════════════════════════════════════
#  Интерактивное меню (стиль node-diagnostic)
# ═══════════════════════════════════════════════════════════════════
show_main_menu() {
    while true; do
        print_banner
        echo
        echo -e "    ${ORANGE}${BOLD}[1]${NC} ${WHITE}Диагностика ноды${NC}     ${DIM}27 чеков, дашборд, аудит безопасности и вердикт${NC}"
        echo -e "    ${ORANGE}${BOLD}[2]${NC} ${WHITE}Оптимизация стека${NC}    ${DIM}sysctl / BBR / FD / RPS / NIC / TCPMSS / Zram${NC}"
        echo -e "    ${ORANGE}${BOLD}[3]${NC} ${WHITE}Полная установка${NC}     ${DIM}RemnawaveNode + Caddy Selfsteal + UFW + Fail2ban${NC}"
        echo -e "    ${ORANGE}${BOLD}[4]${NC} ${WHITE}Выборочный запуск${NC}    ${DIM}установка или починка отдельных компонентов${NC}"
        echo -e "    ${ORANGE}${BOLD}[5]${NC} ${WHITE}Статус системы${NC}       ${DIM}контейнеры, ядро, UFW ACL, наложенные артефакты${NC}"
        echo -e "    ${ORANGE}${BOLD}[6]${NC} ${WHITE}Ядро BBRv3 (XanMod)${NC}  ${DIM}установка ядра XanMod под микроархитектуру CPU${NC}"
        echo -e "    ${ORANGE}${BOLD}[7]${NC} ${WHITE}Сменить шаблон SNI${NC}   ${DIM}быстрая смена HTML-лендинга Caddy Selfsteal${NC}"
        echo -e "    ${ORANGE}${BOLD}[8]${NC} ${WHITE}Обновить компоненты${NC}  ${DIM}docker pull + свежий релиз Xray-core${NC}"
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
                printf "  ${ORANGE}▸${NC} Выбор [Enter=a]: "
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
            8) update_components ;;
            9)
                echo -e "    ${ORANGE}[1]${NC} Откатить только сетевые оптимизации (rollback)"
                echo -e "    ${ORANGE}[2]${NC} Полностью удалить RemnawaveNode, Caddy и конфиги (uninstall)"
                printf "  ${ORANGE}▸${NC} Выбор [1-2]: "
                local rc=""
                read -r rc
                [ "$rc" = "1" ] && run_rollback
                [ "$rc" = "2" ] && uninstall_all
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
[ $# -gt 0 ] && shift || true

case "$cmd" in
    diagnose|diag|--diagnose)         run_diagnose "${1:-full}" ;;
    optimize|opt|tune|--optimize)     run_optimize "${1:---all}" ;;
    bbr3|kernel|--bbr3)               run_bbr3_xanmod ;;
    rollback|revert|--rollback)       run_rollback ;;
    status|st|--status)               show_status ;;
    install|--install)                run_full_install ;;
    selective|--selective)            run_selective_install ;;
    change-template|--change-template) change_template ;;
    update|--update)                  update_components ;;
    export-config|--export-config)    export_config "${1:-/etc/remnanode-install.conf}" ;;
    uninstall|--uninstall)            uninstall_all ;;
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
    menu)                             show_main_menu ;;
    help|-h|--help)                   show_help ;;
    --version|-V)                     echo "node-mgr v${SCRIPT_VERSION}" ;;
    "")                               main ;;
    *)
        log_error "Неизвестная команда: $cmd (используйте: node-mgr --help)"
        exit 2
        ;;
esac
