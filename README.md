<div align="center">

# 🦊 LissVPN Node Orchestrator (`node-mgr`)

**Production-ready оркестратор v4.3, автоматизатор Remnawave API (Caddy L4: VLESS Reality Vision + VLESS XHTTP TLS Cloudflare CDN-резерв с `/certs:ro`), Anti-Detect DPI/uTLS твики, авто-регистратор Cloudflare WARP (Gemini + OpenAI/ChatGPT), E2E-тестер рукопожатий, Highload-оптимизатор ядра (BBR + CAKE Shaper), генератор защиты (`nftables`) и 33-точечный диагностический тулкит**

[![Version](https://img.shields.io/badge/version-v4.3.0-F56E0F?style=for-the-badge&logo=linux&logoColor=white)](https://github.com/Lissovich-Liss/vpn-node)
[![OS](https://img.shields.io/badge/Ubuntu_22.04%2F24.04_%7C_Debian_11%2F12-151419?style=for-the-badge&logo=debian&logoColor=F56E0F)](https://github.com/Lissovich-Liss/vpn-node)
[![Docker](https://img.shields.io/badge/Docker_Compose_v2_+_Caddy_L4-151419?style=for-the-badge&logo=docker&logoColor=F56E0F)](https://github.com/Lissovich-Liss/vpn-node)
[![Security](https://img.shields.io/badge/UFW_+_Fail2ban_+_nftables-Strict_ACL-2ECC71?style=for-the-badge&logo=shield&logoColor=white)](https://github.com/Lissovich-Liss/vpn-node)

</div>

---

## ⚡ Что нового в версии v4.3

* **☁️ VLESS XHTTP TLS как Cloudflare CDN-резерв (оранжевое облако, `CFG_XHTTP_CDN=y`):**
  * **Vision (`SELF_STEAL_DOMAIN`)** остаётся на прямом IP (серое облако DNS-only) для максимальной скорости и минимального пинга.
  * **XHTTP (`XHTTP_STEAL_DOMAIN`)** настраивается для работы за **Cloudflare CDN (Proxied / оранжевое облако)**: `mode: "packet-up"`, `scMaxEachPostBytes: 1000000`, `scMinPostsIntervalMs: 30`, `xPaddingBytes: "100-1000"`, SSL/TLS `Full (strict)` с реальным сертификатом `/certs:ro` и хостом `[XHTTP CDN]` в панели Remnawave.
  * При `CFG_XHTTP_CDN=y` мастер рекомендует **Cloudflare DNS-01** (выпуск и продление сертификатов работают при включённом оранжевом облаке), а `node-mgr verify` отдельно проверяет DNS-only для Vision и живой сквозной HTTPS-маршрут **Cloudflare CDN -> Caddy L4 -> Xray XHTTP** (ловит `525/526/522`).
* **🛡️ Anti-Detect пакет против эвристики ТСПУ и активного пробинга (v4.2):**
  * **Выбор uTLS Fingerprint (`CFG_FINGERPRINT`):** в мастере и API-хостах (`/api/hosts`) по умолчанию используется `randomized` (генерация свежего ClientHello при каждом подключении вместо статичного `chrome`, с возможностью выбрать `chrome`, `firefox`, `ios`).
  * **Уникальный `XHTTP_PATH` для каждой ноды:** вместо одного шаблона `/api/v3/sync/r1` генерируется индивидуальный правдоподобный путь (`/api/v2/telemetry/<hex>`, `/cdn/assets/v1/<hex>` и др.) с сохранением в стейте и конфиге.
  * **Усиление XHTTP + TLS + Reality:** добавлены `xhttpSettings.extra.xPaddingBytes: "100-1000"` (рандомизация размеров HTTP-пакетов), `tlsSettings.rejectUnknownSni: true` и `realitySettings.maxTimeDiff: 300000` (anti-replay окно 5 минут).
  * **Captive Portal / Connectivity `DIRECT`:** домены проверки интернета Android/iOS/Windows (`cp.cloudflare.com`, `connectivitycheck.gstatic.com`, `captive.apple.com`, `www.msftconnecttest.com` и др.) явно направляются в `DIRECT`.
  * **Web-заголовки Selfsteal Caddy:** добавлены `Strict-Transport-Security`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` и полное удаление заголовка `Server` на `:443`, `:9443` и `:80`.
* **🔀 VLESS XHTTP TLS за Caddy L4 SNI Router + проброс `/certs:ro`:**
  * На внешнем порту `:443/tcp` работает **Caddy L4** (`caddy-l4:local`, `github.com/mholt/caddy-l4`), разделяя входящий TLS-трафик по `SNI` без терминации:
    * `SELF_STEAL_DOMAIN` ──► `127.0.0.1:10443` (**VLESS Reality Vision** ──► fallback `127.0.0.1:9443`).
    * `XHTTP_STEAL_DOMAIN` ──► `127.0.0.1:10444` (**VLESS XHTTP + TLS**, который использует реальные SSL-сертификаты Let's Encrypt от Caddy из тома `${CADDY_DATA_VOL}:/certs:ro`).
    * Любой другой SNI / IP-скан ──► `127.0.0.1:9443` (catch-all `HTTP 204`).
* **🌐 Cloudflare WARP WireGuard outbound (`WARP`) для Gemini и OpenAI/ChatGPT:**
  * Во время развертывания (или командой `node-mgr warp`) автоматически генерируется WireGuard X25519-ключ и регистрируется бесплатный WARP-аккаунт в Cloudflare API с сохранением в `/var/lib/node-mgr/warp.env` (`chmod 600`).
  * В Config Profile панели добавляется нативный outbound `WARP` (`protocol: "wireguard"`, `mtu: 1280`) и правила маршрутизации для доменов **Gemini**, **Google AI Studio**, **NotebookLM**, **ChatGPT**, **OpenAI** и **Sora**.
* **🔬 Сквозной E2E-верификатор рукопожатий (`node-mgr verify`):**
  * Проверка `Caddy L4 (:443)` ──► `Xray Vision (:10443)` ──► `Selfsteal (:9443)` и реального TLS-рукопожатия `Caddy L4 (:443)` ──► `XHTTP TLS (:10444)` с проверкой читаемости сертификатов в `remnanode:/certs:ro`.
  * Имитация активного пробинга сканером с чужим SNI (`scanner-probe.invalid:443`) -> `HTTP 204`.
  * Проверка DNS A-записей (DNS-only) для обоих доменов и состояния WARP.
* **⚖️ Smart Traffic Shaper (`node-mgr shape` / `sch_cake` `dual-srchost`):**
  * Честное разделение полосы пропускания на уровне ядра (`CAKE diffserv4 nat dual-srchost` с fallback на `fq_codel`).
* **🤖 Zero-Touch авто-деплой через Remnawave API (Panel 3.x Ready):**
  * Автоматическое создание и синхронизация **Config Profile** (`POST / PATCH /api/config-profiles`) с двумя инбаундами (`VLESS_REALITY_<NODE>` + `VLESS_XHTTP_<NODE>`) и аутбаундами `DIRECT` / `BLOCK` / `WARP`.
  * Автоматическая регистрация **Ноды** (`/api/nodes`) с привязкой обоих инбаундов и получением `SECRET_KEY` через `GET /api/keygen`.
  * Автоматическое создание **2 Хостов** (`/api/hosts`) на порту `443`: `[Reality]` (`securityLayer: DEFAULT`) и `[XHTTP]` (`securityLayer: TLS`, `host`, `path`, `alpn`).
* **🔒 Caddy L4 Selfsteal (HTTP-01 или Cloudflare DNS-01):**
  * Выпуск доверенных SSL-сертификатов сразу для обоих доменов (`SELF_STEAL_DOMAIN` и `XHTTP_STEAL_DOMAIN`) через `HTTP-01` (`:80`) или `Cloudflare DNS-01` (`github.com/caddy-dns/cloudflare`).
* **🕸️ NetBird Mesh VPN + 📊 Стек мониторинга + 🛡️ UFW / Fail2ban / Protect + 🩺 Doctor (33 чека).**

---

## 🚀 Быстрый старт (Установка одной командой)

Подключитесь к серверу **Ubuntu 22.04 / 24.04** или **Debian 11 / 12** от имени `root` (`sudo -i`) и выполните:

```bash
curl -fsSL "https://raw.githubusercontent.com/Lissovich-Liss/vpn-node/main/node-mgr.sh?t=$(date +%s)" -o /usr/local/bin/node-mgr && chmod +x /usr/local/bin/node-mgr && node-mgr
```

### ⚡ Полный Zero-Touch авто-деплой одной командой (без вопросов)

Подготовьте две DNS `A`-записи (без проксирования Cloudflare), направленные на IP вашей ноды (например, `nl1.example.com` и `x-nl1.example.com`), и запустите:

```bash
curl -fsSL "https://raw.githubusercontent.com/Lissovich-Liss/vpn-node/main/node-mgr.sh?t=$(date +%s)" -o /usr/local/bin/node-mgr && chmod +x /usr/local/bin/node-mgr && \
REMNAWAVE_API_URL="https://panel.example.com" \
REMNAWAVE_API_TOKEN="ВАШ_BEARER_ТОКЕН_ИЗ_ПАНЕЛИ" \
NODE_NAME="Ruby-NL-01" \
NODE_ADDRESS="82.47.155.72" \
SELF_STEAL_DOMAIN="nl1.example.com" \
XHTTP_STEAL_DOMAIN="x-nl1.example.com" \
CFG_ENABLE_WARP="y" \
node-mgr auto-deploy
```

> 💡 После первого запуска утилита доступна глобально из любой точки терминала по команде `node-mgr`.

---

## 🔀 Архитектура Caddy L4 (:443) + Vision + XHTTP TLS (/certs:ro) + WARP

На внешнем интерфейсе порт `:443/tcp` принимает **Caddy L4** (`caddy-l4:local`), маршрутизируя соединения по SNI без разрыва TLS:

| Тип подключения на `:443/tcp` | Маршрут внутри узла | Поведение |
| :--- | :--- | :--- |
| `SNI = SELF_STEAL_DOMAIN` (Клиенты Vision / браузер) | `Caddy L4` ──► `127.0.0.1:10443` (**Xray VLESS Reality Vision**) | Валидные клиенты устанавливают `VLESS + XTLS-Vision`; чужой пробинг уходит на `dest: 127.0.0.1:9443` (Caddy Selfsteal HTML) |
| `SNI = XHTTP_STEAL_DOMAIN` (Клиенты XHTTP) | `Caddy L4` ──► `127.0.0.1:10444` (**Xray VLESS XHTTP + TLS**) | Xray читает Let's Encrypt сертификаты из `/certs:ro` (том `selfsteel_caddy_data_selfsteal`) и принимает `XHTTP` (`h2,http/1.1`) |
| Сканер по IP / неизвестный SNI | `Caddy L4` ──► `127.0.0.1:9443` (Catch-all) | Возврат `HTTP 204` без раскрытия реальных доменов |
| Трафик Gemini / AI Studio / OpenAI / ChatGPT | Xray Routing ──► **`WARP`** (`WireGuard`) | Автоматически уходит через Cloudflare WARP (`172.16.0.2`), остальной трафик идёт в `DIRECT` |

---

## 🖥️ Интерактивное меню (TUI v4.0)

При запуске `node-mgr` без аргументов открывается интерактивная панель управления с живым статус-баром:

```text
  🦊 LISSVPN NODE ORCHESTRATOR  v4.0.0 · VLESS Reality + Selfsteal Toolkit
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  2026-11-07 01:25 UTC · ruby-nl-01 · kvm · TCP: bbr+cake · IP: 82.47.155.72
  ● RemnaNode   ● Caddy   ● UFW   ● Fail2ban   ○ NetBird
  ──────────────────────────────────────────────────────────────────────
  ДИАГНОСТИКА И ТЮНИНГ ЯДРА
    [1] Диагностика ноды     33 чека, Score 0..100, PSI, MSS, порт-аудит, JSON/отчёт
    [2] Оптимизация стека    sysctl / BBR+CAKE / FD / RPS+XPS / NIC / Shaper / Zram
    [3] Тест Reality/Steal   E2E-проверка рукопожатий :443 -> Xray -> Selfsteal :9443
    [4] Ядро BBRv3 (XanMod)  установка ядра XanMod под микроархитектуру CPU

  РАЗВЕРТЫВАНИЕ И КОНФИГУРАЦИЯ
    [5] Авто-деплой по API   Caddy Selfsteal + VLESS Reality Vision (:443) + Хост
    [6] Выборочный запуск    модули: Docker, Caddy, API, NetBird, Monitoring, Protect
    [7] Сменить шаблон SNI   быстрая смена HTML-лендинга в /opt/html (10 тем)

  БЕЗОПАСНОСТЬ И ОБСЛУЖИВАНИЕ
    [8] Статус и Логи        дашборд служб, NetBird, Мониторинг, просмотр логов
    [9] Защита (Protect)     генератор таблиц nftables anti-DDoS + SSH Hardening
   [10] Обновить компоненты  docker pull (Node/Caddy/Monitoring) + self-update
   [11] Откат / Удаление     снять оптимизации (rollback), экспорт или удалить узел
    [0] Выход
```

---

## 🛠️ Справочник команд CLI

| Команда | Описание |
| :--- | :--- |
| `node-mgr` | Запуск интерактивного TUI-меню v4.0 |
| `node-mgr auto-deploy` | Полный цикл установки и авто-регистрации в панели Remnawave через API |
| `node-mgr diagnose` | Запуск полной диагностики ноды (33 чека, Score `0..100`, текстовый отчёт в `/tmp`) |
| `node-mgr diagnose -q` | Быстрая диагностика без внешних сетевых тестов |
| `node-mgr diagnose --json` | Вывод результатов диагностики и метрик в машиночитаемом формате JSON |
| `node-mgr verify` | Сквозной E2E-тест `Caddy L4 (:443) -> Vision (:10443) + XHTTP TLS (:10444 /certs:ro) -> Selfsteal (:9443)` и WARP |
| `node-mgr warp` | Регистрация / перерегистрация бесплатного Cloudflare WARP WireGuard (маршрутизация Gemini + OpenAI) |
| `node-mgr optimize --all` | Применить весь комплекс оптимизаций (`sysctl`, `FD`, `RPS/XPS`, `NIC`, `MSS`, `journald`) |
| `node-mgr optimize --from-findings` | Автоматически исправить только те проблемы, которые выявила диагностика |
| `node-mgr optimize --zram` | Активировать сжатый Zram-swap в оперативной памяти (50% от RAM) |
| `node-mgr shape [MBIT]` | Включить Smart Traffic Shaper (`CAKE dual-srchost`) для честного деления канала между клиентами |
| `node-mgr protect` | Сгенерировать профили `firewall.nft`, `sshd-hardening.conf` и `APPLY.txt` в `/var/lib/node-mgr/protect` |
| `node-mgr netbird` | Установить клиент NetBird Mesh VPN и подключить узел по Setup Key |
| `node-mgr monitoring` | Развернуть стек мониторинга (`cAdvisor` + `node-exporter` + `vmagent`) |
| `node-mgr status` | Показать дашборд состояния ядра, домена Reality, NetBird, мониторинга и контейнеров |
| `node-mgr logs {node\|caddy\|monitoring\|f2b}` | Просмотр логов контейнеров или службы `Fail2ban` в реальном времени |
| `node-mgr change-template` | Быстрая смена HTML-шаблона маскировки в `/opt/html` на лету |
| `node-mgr bbr3` | Установка кастомного ядра **XanMod** с поддержкой **BBRv3** |
| `node-mgr update` | Обновление образов `remnanode`, `caddy`, стека мониторинга и пакета `netbird` |
| `node-mgr self-update` | Обновление самого скрипта `node-mgr` напрямую с GitHub |
| `node-mgr export-config` | Экспорт текущей конфигурации в `/etc/remnanode-install.conf` (права `0600`) |
| `node-mgr dry-run` | Показать полный план развертывания без внесения изменений в систему |
| `node-mgr rollback` | Безопасный откат всех наложенных сетевых оптимизаций и шейпера до заводских |
| `node-mgr uninstall` | Полное удаление контейнеров, конфигураций и откат настроек |

---

## 🤖 Автоматическая (Unattended) установка через конфиг-файл

Экспортируйте готовую конфигурацию на настроенном сервере:
```bash
node-mgr export-config /etc/remnanode-install.conf
```
Либо создайте `/etc/remnanode-install.conf` (права `chmod 600`):

```ini
REMNAWAVE_API_URL="https://panel.example.com"
REMNAWAVE_API_TOKEN="eyJ..."
NODE_NAME="Ruby-NL-01"
NODE_ADDRESS="82.47.155.72"
SELF_STEAL_DOMAIN="nl1.example.com"
XHTTP_STEAL_DOMAIN="x-nl1.example.com"
XHTTP_PATH="/api/v3/sync/r1"
SELF_STEAL_PORT=9443
CFG_ENABLE_WARP=y
CFG_CERT_TYPE="1"              # 1 = Let's Encrypt HTTP-01, 2 = Cloudflare DNS-01
CFG_CLOUDFLARE_TOKEN=""        # API Token Cloudflare (если CFG_CERT_TYPE="2")
CFG_NODE_PORT=3000
CFG_PANEL_IP="203.0.113.10"
CFG_APPLY_NETWORK=y
CFG_SETUP_UFW=y
CFG_INSTALL_FAIL2BAN=y
CFG_INSTALL_NETBIRD=n
CFG_NETBIRD_SETUP_KEY=""
CFG_INSTALL_MONITORING=n
CFG_INSTANCE_NAME="Ruby-NL-01"
CFG_GRAFANA_IP="100.64.0.1"
```

Проверить план развертывания без изменений или запустить установку:
```bash
node-mgr --config /etc/remnanode-install.conf --dry-run
node-mgr --config /etc/remnanode-install.conf
```

---

## 📂 Структура файлов на сервере

* `/usr/local/bin/node-mgr` — глобальный исполняемый файл оркестратора.
* `/opt/selfsteel/` — `Caddyfile`, `.env`, `docker-compose.yml` и JSON-логи Caddy (`/opt/selfsteel/logs/access.log`).
* `/opt/html/` — активный HTML-шаблон маскировки для Selfsteal-домена.
* `/opt/remnanode/` — конфигурация `.env` и `docker-compose.yml` контейнера `remnanode` с подключенным томом `/certs:ro`.
* `/opt/monitoring/` — `docker-compose.yml` и `prometheus.yml` стека мониторинга (`cAdvisor`, `node-exporter`, `vmagent`).
* `/var/lib/node-mgr/` — сохраненные UUID и ключи API-деплоя (`remnawave-api.env`), результаты диагностики (`findings.env`), лог фиксов (`applied-fixes.log`) и сгенерированные профили защиты (`protect/`).
* `/etc/sysctl.d/99-lissvpn-sysctl.conf` — адаптивный Highload-профиль сетевого стека.
* `/etc/fail2ban/jail.local` — правила блокировки брутфорса SSH, сканеров Caddy и SYN-портскана.
* `/var/log/remnanode-install.log` — подробный журнал операций установщика.
