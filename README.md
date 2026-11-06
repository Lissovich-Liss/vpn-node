<div align="center">

# 🦊 LissVPN Node Orchestrator (`node-mgr`)

**Production-ready оркестратор v4.0, автоматизатор Remnawave API (Caddy L4 + Reality Vision & XHTTP), E2E-тестер рукопожатий, Highload-оптимизатор ядра (BBR + CAKE Shaper), генератор защиты (`nftables`) и 33-точечный диагностический тулкит**

[![Version](https://img.shields.io/badge/version-v4.0.0-F56E0F?style=for-the-badge&logo=linux&logoColor=white)](https://github.com/Lissovich-Liss/vpn-node)
[![OS](https://img.shields.io/badge/Ubuntu_22.04%2F24.04_%7C_Debian_11%2F12-151419?style=for-the-badge&logo=debian&logoColor=F56E0F)](https://github.com/Lissovich-Liss/vpn-node)
[![Docker](https://img.shields.io/badge/Docker_Compose_v2_+_Caddy_L4-151419?style=for-the-badge&logo=docker&logoColor=F56E0F)](https://github.com/Lissovich-Liss/vpn-node)
[![Security](https://img.shields.io/badge/UFW_+_Fail2ban_+_nftables-Strict_ACL-2ECC71?style=for-the-badge&logo=shield&logoColor=white)](https://github.com/Lissovich-Liss/vpn-node)

</div>

---

## ⚡ Что нового в версии v4.0

* **🔬 Сквозной E2E-верификатор рукопожатий (`node-mgr verify`):**
  * Живая проверка всей цепочки `Caddy L4 (:443) ──► Xray Reality (:10443 / :10444) ──► Selfsteal Fallback (:9443)` для обоих доменов (`SELF_STEAL_DOMAIN` и `XHTTP_STEAL_DOMAIN`) по TLS 1.3 + HTTP/2.
  * Имитация активного пробинга сканером с чужим SNI (`scanner-probe.invalid`) для проверки того, что реальный домен не утекает и возвращается `HTTP 204`.
  * Автоматический детект ошибочно включённого проксирования Cloudflare (*Orange Cloud*), ломающего Reality.
* **⚖️ Smart Traffic Shaper (`node-mgr shape` / `sch_cake` `dual-srchost`):**
  * Честное разделение полосы пропускания на уровне ядра (`CAKE diffserv4 nat dual-srchost` с fallback на `fq_codel`), не позволяющее одному клиенту с торрентом или спидтестом забить весь порт VPS и вызвать потери пакетов у остальных пользователей.
* **🖥️ Обновлённый интерфейс TUI v4.0 с Live-статусбаром:**
  * В шапке главного меню в реальном времени отображаются индикаторы ключевых служб (`● RemnaNode`, `● Caddy L4`, `● UFW`, `● Fail2ban`, `● NetBird`, активная связка `BBR+CAKE/fq`).
  * Меню разделено на логические блоки: **Диагностика и тюнинг ядра**, **Развертывание и стек протоколов**, **Безопасность и обслуживание**.
* **🤖 Zero-Touch авто-деплой через Remnawave API (Panel 3.x Ready):**
  * Автоматическое создание и синхронизация **Config Profile** (`POST / PATCH /api/config-profiles`) сразу с **двумя инбаундами**: `VLESS_REALITY_<NODE>` (`127.0.0.1:10443`) и `VLESS_XHTTP_<NODE>` (`127.0.0.1:10444`).
  * Автоматическая регистрация или обновление **Ноды** (`/api/nodes`) с привязкой обоих инбаундов и автоматическим получением `SECRET_KEY` через `GET /api/keygen`.
  * Автоматическое создание **двух Хостов** (`/api/hosts`) на публичном порту `443` (`[Reality]` и `[XHTTP]`) с прямой привязкой `nodes: [node_uuid]`.
* **🔀 L4 SNI-маршрутизация (`mholt/caddy-l4`) + двойной Selfsteal (HTTP-01 и Cloudflare DNS-01):**
  * Сборка изолированного Docker-образа `caddy-l4:local` на базе `xcaddy` и модуля `github.com/mholt/caddy-l4` (+ автопересборка с `github.com/caddy-dns/cloudflare` при выборе DNS-01).
  * Сжатие `zstd`/`gzip`, удаление заголовка `Server: Caddy` (`header -Server`) и отключение `admin off` в `Caddyfile`.
* **🕸️ NetBird Mesh VPN + 📊 Стек мониторинга (VictoriaMetrics / Grafana):**
  * Встроенная установка и подключение **NetBird VPN** (`netbird up --setup-key`) с автоопределением приватного IP на интерфейсе `wt0` (`100.64.0.0/10`).
  * Развертывание стека мониторинга в `/opt/monitoring`: **cAdvisor** (`127.0.0.1:9101`) + **Node Exporter** (`127.0.0.1:9100`) + **vmagent** (`127.0.0.1:8429`) с отправкой метрик по `remoteWrite` в VictoriaMetrics / Grafana.
* **🛡️ Эшелонированная защита периметра (`UFW` + `Fail2ban` + `Protect`):**
  * **Strict Panel ACL:** порт управления нодой (`3000/tcp`) открывается в `UFW` **строго для IP панели Remnawave**.
  * **Fail2ban 3-в-1:** джейлы `[sshd]`, `[caddy-status]` и `[portscan]` (автоматическое обнаружение SYN-сканирования закрытых портов с баном на 24 часа).
  * **Генератор `node-mgr protect`:** создание выделенной таблицы `nftables` (`inet vpn_protect` с per-IP rate-limit на `443/tcp`, `443/udp` и `SSH`), профиля `sshd-hardening.conf` (с проверкой наличия `authorized_keys`) и инструкции с 5-минутным таймером авто-отката (`systemd-run --on-active=300`).
* **🩺 Встроенная 33-точечная диагностика (`Doctor`):** полный аудит ресурсов, PSI (`/proc/pressure`), CPU Steal, UDP `RcvbufErrors`, live-сессий с провалом MSS `<256`, открытых наружу портов, IP-репутации (YouTube / Google / ChatGPT), контейнеров, обоих SSL-сертификатов, интегральная оценка **Score `0..100`**, текстовый отчёт в `/tmp/node-diagnostic-summary-*.txt` и JSON-экспорт (`node-mgr diagnose --json`).

---

## 🚀 Быстрый старт (Установка одной командой)

Подключитесь к серверу **Ubuntu 22.04 / 24.04** или **Debian 11 / 12** от имени `root` (`sudo -i`) и выполните:

```bash
curl -fsSL "https://raw.githubusercontent.com/Lissovich-Liss/vpn-node/main/node-mgr.sh?t=$(date +%s)" -o /usr/local/bin/node-mgr && chmod +x /usr/local/bin/node-mgr && node-mgr
```

### ⚡ Полный Zero-Touch авто-деплой одной командой (без вопросов)

Подготовьте две DNS `A`-записи, направленные на IP вашей ноды (например, `nl1.example.com` для Vision и `nl2.example.com` для XHTTP), и запустите:

```bash
curl -fsSL "https://raw.githubusercontent.com/Lissovich-Liss/vpn-node/main/node-mgr.sh?t=$(date +%s)" -o /usr/local/bin/node-mgr && chmod +x /usr/local/bin/node-mgr && \
REMNAWAVE_API_URL="https://panel.example.com" \
REMNAWAVE_API_TOKEN="ВАШ_BEARER_ТОКЕН_ИЗ_ПАНЕЛИ" \
NODE_NAME="Ruby-NL-01" \
NODE_ADDRESS="82.47.155.72" \
SELF_STEAL_DOMAIN="nl1.example.com" \
XHTTP_STEAL_DOMAIN="nl2.example.com" \
XHTTP_PATH="/api/v3/sync/r1" \
node-mgr auto-deploy
```

> 💡 После первого запуска утилита доступна глобально из любой точки терминала по команде `node-mgr`.

---

## 🔀 Схема L4-маршрутизации на узле

На внешнем интерфейсе порт `:443/tcp` принимает **Caddy L4** (`github.com/mholt/caddy-l4`), который анализирует TLS `ClientHello` (SNI) без завершения TLS-сессии и маршрутизирует соединение:

| Входящий SNI на `:443/tcp` | Внутренний таргет | Инбаунд в Xray (`remnanode`) | Fallback при проверке цензором |
| :--- | :--- | :--- | :--- |
| `SELF_STEAL_DOMAIN` *(напр. `nl1.example.com`)* | `127.0.0.1:10443` | `VLESS_REALITY_<NODE>` (`network: raw`, Vision) | `127.0.0.1:9443` (Caddy Selfsteal SSL #1 + HTML) |
| `XHTTP_STEAL_DOMAIN` *(напр. `nl2.example.com`)* | `127.0.0.1:10444` | `VLESS_XHTTP_<NODE>` (`network: xhttp`, Reality) | `127.0.0.1:9443` (Caddy Selfsteal SSL #2 + HTML) |
| Любой другой SNI / скан по IP | `127.0.0.1:9443` | — | Внутренний обработчик Caddy (`204` / закрытие) |

---

## 🖥️ Интерактивное меню (TUI v4.0)

При запуске `node-mgr` без аргументов открывается интерактивная панель управления с живым статус-баром:

```text
  🦊 LISSVPN NODE ORCHESTRATOR  v4.0.0 · L4 Multi-Protocol Toolkit
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  2026-11-07 01:25 UTC · ruby-nl-01 · kvm · TCP: bbr+cake · IP: 82.47.155.72
  ● RemnaNode   ● Caddy L4   ● UFW   ● Fail2ban   ○ NetBird
  ──────────────────────────────────────────────────────────────────────
  ДИАГНОСТИКА И ТЮНИНГ ЯДРА
    [1] Диагностика ноды     33 чека, Score 0..100, PSI, MSS, порт-аудит, JSON/отчёт
    [2] Оптимизация стека    sysctl / BBR+CAKE / FD / RPS+XPS / NIC / Shaper / Zram
    [3] Тест L4 и Selfsteal  E2E-проверка рукопожатий :443 -> Xray -> Selfsteal :9443
    [4] Ядро BBRv3 (XanMod)  установка ядра XanMod под микроархитектуру CPU

  РАЗВЕРТЫВАНИЕ И СТЕК ПРОТОКОЛОВ
    [5] Авто-деплой по API   Caddy L4 + 2 Инбаунда (Reality + XHTTP) + 2 Хоста
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
| `node-mgr verify` | Сквозной E2E-тест рукопожатий `Caddy L4 (:443) -> Xray Reality -> Selfsteal (:9443)` и защита от сканеров |
| `node-mgr optimize --all` | Применить весь комплекс оптимизаций (`sysctl`, `FD`, `RPS/XPS`, `NIC`, `MSS`, `journald`) |
| `node-mgr optimize --from-findings` | Автоматически исправить только те проблемы, которые выявила диагностика |
| `node-mgr optimize --zram` | Активировать сжатый Zram-swap в оперативной памяти (50% от RAM) |
| `node-mgr shape [MBIT]` | Включить Smart Traffic Shaper (`CAKE dual-srchost`) для честного деления канала между клиентами |
| `node-mgr protect` | Сгенерировать профили `firewall.nft`, `sshd-hardening.conf` и `APPLY.txt` в `/var/lib/node-mgr/protect` |
| `node-mgr netbird` | Установить клиент NetBird Mesh VPN и подключить узел по Setup Key |
| `node-mgr monitoring` | Развернуть стек мониторинга (`cAdvisor` + `node-exporter` + `vmagent`) |
| `node-mgr status` | Показать дашборд состояния ядра, L4-доменов, NetBird, мониторинга и контейнеров |
| `node-mgr logs {node\|caddy\|monitoring\|f2b}` | Просмотр логов контейнеров или службы `Fail2ban` в реальном времени |
| `node-mgr change-template` | Быстрая смена HTML-шаблона маскировки в `/opt/html` на лету |
| `node-mgr bbr3` | Установка кастомного ядра **XanMod** с поддержкой **BBRv3** |
| `node-mgr update` | Обновление образов `remnanode`, `caddy-l4:local`, стека мониторинга и пакета `netbird` |
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
XHTTP_STEAL_DOMAIN="nl2.example.com"
XHTTP_PATH="/api/v3/sync/r1"
SELF_STEAL_PORT=9443
VISION_INBOUND_PORT=10443
XHTTP_INBOUND_PORT=10444
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
* `/opt/selfsteel/` — `Dockerfile` (`caddy-l4`), `Caddyfile`, `.env`, `docker-compose.yml` и JSON-логи Caddy (`/opt/selfsteel/logs/access.log`).
* `/opt/html/` — активный HTML-шаблон маскировки для обоих Selfsteal-доменов.
* `/opt/remnanode/` — конфигурация `.env` и `docker-compose.yml` контейнера `remnanode` с подключенным томом `/certs:ro`.
* `/opt/monitoring/` — `docker-compose.yml` и `prometheus.yml` стека мониторинга (`cAdvisor`, `node-exporter`, `vmagent`).
* `/var/lib/node-mgr/` — сохраненные UUID и ключи API-деплоя (`remnawave-api.env`), результаты диагностики (`findings.env`), лог фиксов (`applied-fixes.log`) и сгенерированные профили защиты (`protect/`).
* `/etc/sysctl.d/99-lissvpn-sysctl.conf` — адаптивный Highload-профиль сетевого стека.
* `/etc/fail2ban/jail.local` — правила блокировки брутфорса SSH, сканеров Caddy и SYN-портскана.
* `/var/log/remnanode-install.log` — подробный журнал операций установщика.
