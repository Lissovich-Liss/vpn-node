<div align="center">

# 🦊 LissVPN Node Orchestrator (`node-mgr`)

**Production-ready оркестратор, автоматизатор Remnawave API (Caddy L4 + Reality Vision & XHTTP), Highload-оптимизатор ядра и 27-точечный диагностический тулкит**

[![Version](https://img.shields.io/badge/version-v3.4.0-F56E0F?style=for-the-badge&logo=linux&logoColor=white)](https://github.com/Lissovich-Liss/vpn-node)
[![OS](https://img.shields.io/badge/Ubuntu_22.04%2F24.04_%7C_Debian_11%2F12-151419?style=for-the-badge&logo=debian&logoColor=F56E0F)](https://github.com/Lissovich-Liss/vpn-node)
[![Docker](https://img.shields.io/badge/Docker_Compose_v2_+_Caddy_L4-151419?style=for-the-badge&logo=docker&logoColor=F56E0F)](https://github.com/Lissovich-Liss/vpn-node)
[![Security](https://img.shields.io/badge/UFW_+_Fail2ban-Strict_ACL-2ECC71?style=for-the-badge&logo=shield&logoColor=white)](https://github.com/Lissovich-Liss/vpn-node)

</div>

---

## ⚡ Ключевые возможности v3.4

* **🤖 Zero-Touch авто-деплой через Remnawave API:**
  * Автоматическое создание и синхронизация **Config Profile** (`POST / PATCH /api/config-profiles`) сразу с **двумя инбаундами**: `VLESS Reality Vision` (`127.0.0.1:10443`) и `VLESS Reality XHTTP` (`127.0.0.1:10444`).
  * Автоматическая регистрация или обновление **Ноды** (`/api/nodes`) с привязкой обоих инбаундов и автоматическим получением `SECRET_KEY` через `GET /api/keygen`.
  * Автоматическое создание **двух Хостов** (`/api/hosts`) на публичном порту `443` (`[Reality]` и `[XHTTP]`).
* **🔀 L4 SNI-маршрутизация (`mholt/caddy-l4`) + двойной Selfsteal:**
  * Сборка изолированного Docker-образа `caddy-l4:local` на базе `xcaddy` и модуля `github.com/mholt/caddy-l4` без установки Go и компиляторов в хостовую ОС.
  * Разведение входящего TLS-трафика на порту `:443/tcp` по SNI до расшифровки:
    * `SELF_STEAL_DOMAIN` → `127.0.0.1:10443` (**VLESS Reality Vision**)
    * `XHTTP_STEAL_DOMAIN` → `127.0.0.1:10444` (**VLESS Reality XHTTP**, путь `/api/v3/sync/r1`)
    * Неизвестные SNI и fallback невалидных рукопожатий → `127.0.0.1:9443` (**Caddy Selfsteal HTTPS**)
  * Автоматический выпуск Let's Encrypt сертификатов для **обоих поддоменов** по HTTP-01 (`disable_tlsalpn_challenge`) без конфликта с L4-слушателем на `:443` и монтирование тома сертификатов в `remnanode` (`/certs:ro`).
  * **11 готовых SNI-шаблонов** маскировки в `/opt/html` с уникальной криптографической сигнатурой `data-edge-rev` при каждой установке.
* **🛡️ Жесткая сетевая изоляция (Strict Panel ACL):**
  * Порт управления нодой (`3000/tcp`) закрыт от всего интернета и открывается в `UFW` **строго для белого IP-адреса панели Remnawave** (IP панели определяется автоматически из `REMNAWAVE_API_URL`).
  * Внутренний сокет Selfsteal (`127.0.0.1:9443`) принудительно изолирован от внешних интерфейсов.
* **🚫 Защита от сканеров и брутфорса (Fail2ban):**
  * Нативная работа через `systemd-journald` (`python3-systemd`) на Debian 12 / Ubuntu 24.04.
  * Автоматический бан SSH-брутфорса и веб-сканеров по JSON-логам Caddy (`/opt/selfsteel/logs/access.log`) с прогрессивным ростом времени бана до 7 суток и исключением IP панели из блокировок.
* **🚀 Адаптивный Highload-тюнинг ядра Linux:**
  * Автоматический расчет буферов сокетов (`rmem_max`/`wmem_max` до 64 МБ) и таблицы `nf_conntrack` (до 1 млн сессий) под объем RAM сервера (*Lite* / *Standard* / *Highload*).
  * Включение **BBR / BBRv3 (XanMod)**, планировщика `fq`, распределение сетевых прерываний по всем ядрам **RPS/RFS**, аппаратные оффлоады сетевой карты **GRO/GSO/TSO**, фиксация **TCPMSS clamp to PMTU** и сжатый **Zram-swap**.
* **🩺 Встроенная 27-точечная диагностика (`Doctor`):** полный аудит ресурсов, CPU Steal, параметров ядра, контейнеров, обоих SSL-сертификатов и правил безопасности с авто-исправлением находок одной командой (`node-mgr optimize --from-findings`).

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
| `SELF_STEAL_DOMAIN` *(напр. `nl1.example.com`)* | `127.0.0.1:10443` | `VLESS-REALITY-<NODE>` (`network: raw`, Vision) | `127.0.0.1:9443` (Caddy Selfsteal SSL #1 + HTML) |
| `XHTTP_STEAL_DOMAIN` *(напр. `nl2.example.com`)* | `127.0.0.1:10444` | `VLESS-XHTTP-<NODE>` (`network: xhttp`, Reality) | `127.0.0.1:9443` (Caddy Selfsteal SSL #2 + HTML) |
| Любой другой SNI / скан по IP | `127.0.0.1:9443` | — | Внутренний обработчик Caddy (`204` / закрытие) |

---

## 🖥️ Интерактивное меню (TUI)

При запуске `node-mgr` без аргументов открывается интерактивная панель управления:

```text
  LISSVPN NODE ORCHESTRATOR  v3.4.0 · node-mgr toolkit
  ────────────────────────────────────────────────────────────────────
  2026-11-06 21:00 UTC · ruby-nl-01 · kvm · IP: 82.47.155.72

    [1] Диагностика ноды     27 чеков, дашборд, аудит безопасности и вердикт
    [2] Оптимизация стека    sysctl / BBR / FD / RPS / NIC / TCPMSS / Zram
    [3] Авто-деплой по API   Caddy L4 + 2 Инбаунда (Reality + XHTTP) + 2 Хоста
    [4] Выборочный запуск    ручная установка или починка отдельных модулей
    [5] Статус системы       контейнеры, ядро, UFW ACL, наложенные артефакты
    [6] Ядро BBRv3 (XanMod)  установка ядра XanMod под микроархитектуру CPU
    [7] Сменить шаблон SNI   быстрая смена HTML-лендинга в /opt/html
    [8] Обновить компоненты  docker pull + self-update скрипта с GitHub
    [9] Откат / Удаление     снять оптимизации (rollback) или удалить узел
    [0] Выход
```

---

## 🛠️ Справочник команд CLI

| Команда | Описание |
| :--- | :--- |
| `node-mgr` | Запуск интерактивного TUI-меню |
| `node-mgr auto-deploy` | Полный цикл установки и авто-регистрации в панели Remnawave через API |
| `node-mgr diagnose` | Запуск полной диагностики ноды (27 чеков + сохранение находок) |
| `node-mgr diagnose -q` | Быстрая диагностика без внешних сетевых тестов |
| `node-mgr optimize --all` | Применить весь комплекс оптимизаций (`sysctl`, `FD`, `RPS`, `NIC`, `MSS`, `journald`) |
| `node-mgr optimize --from-findings` | Автоматически исправить только те проблемы, которые выявила диагностика |
| `node-mgr optimize --zram` | Активировать сжатый Zram-swap в оперативной памяти (50% от RAM) |
| `node-mgr status` | Показать дашборд состояния ядра, L4-доменов, контейнеров и правил UFW |
| `node-mgr logs node` | Просмотр логов контейнера `remnanode` в реальном времени |
| `node-mgr logs caddy` | Просмотр логов контейнера `caddy-remnawave` в реальном времени |
| `node-mgr logs f2b` | Просмотр журнала службы `Fail2ban` |
| `node-mgr change-template` | Быстрая смена HTML-шаблона маскировки в `/opt/html` на лету |
| `node-mgr bbr3` | Установка кастомного ядра **XanMod** с поддержкой **BBRv3** |
| `node-mgr update` | Обновление образа `remnanode` и пересборка `caddy-l4:local` |
| `node-mgr self-update` | Обновление самого скрипта `node-mgr` напрямую с GitHub |
| `node-mgr export-config` | Экспорт текущей конфигурации в `/etc/remnanode-install.conf` |
| `node-mgr rollback` | Безопасный откат всех наложенных сетевых оптимизаций до заводских |
| `node-mgr uninstall` | Полное удаление контейнеров, конфигураций и откат настроек |

---

## 🤖 Автоматическая (Unattended) установка через конфиг-файл

Экспортируйте готовую конфигурацию на настроенном сервере:
```bash
node-mgr export-config /etc/remnanode-install.conf
```
Либо создайте `/etc/remnanode-install.conf`:

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
CFG_NODE_PORT=3000
CFG_PANEL_IP="203.0.113.10"
CFG_APPLY_NETWORK=y
CFG_SETUP_UFW=y
CFG_INSTALL_FAIL2BAN=y
```

Запустите установку:
```bash
node-mgr --config /etc/remnanode-install.conf
```

---

## 🩺 Что проверяет 27-точечная диагностика (`node-mgr diagnose`)

1. **Блок 1 — Система и ресурсы (Чеки 01–05):**
   * `01` Количество ядер vCPU и Load Average.
   * `02` **CPU Steal Time** — детект оверселлинга процессора со стороны хостинг-провайдера.
   * `03` Доступная оперативная память RAM и наличие Swap / Zram.
   * `04` Свободное место на диске `/` и запас индексных дескрипторов (`Inodes`).
   * `05` Системные лимиты открытых файлов (`fs.file-max` и `ulimit -n`).
2. **Блок 2 — Сетевой стек ядра (Чеки 06–13):**
   * `06` Активный алгоритм контроля перегрузки TCP (`BBR` / `BBR2` / `BBR3`).
   * `07` Дисциплина очереди пакетов (`default_qdisc = fq`).
   * `08` Размер буферов сокетов под высокий BDP (`rmem_max` / `wmem_max`).
   * `09` Статус `tcp_fastopen = 3` и отключение просадок после простоя (`tcp_slow_start_after_idle = 0`).
   * `10` Быстрая утилизация сокетов (`tcp_tw_reuse`) и диапазон эфемерных портов.
   * `11` Очереди входящих подключений (`somaxconn` и `tcp_max_syn_backlog`).
   * `12` Автоподбор MTU (`tcp_mtu_probing`) и защита от bufferbloat (`tcp_notsent_lowat`).
   * `13` Заполненность и лимит таблицы отслеживания соединений `nf_conntrack`.
3. **Блок 3 — Сетевая карта и прерывания (Чеки 14–18):**
   * `14` Распределение обработки пакетов по всем ядрам **RPS/RFS**.
   * `15` Длина очереди передачи сетевого интерфейса (`txqueuelen >= 5000`) и оффлоады **GRO/GSO/TSO**.
   * `16` Активность правила `iptables TCPMSS clamp-mss-to-pmtu`.
   * `17` Статус демона балансировки аппаратных прерываний `irqbalance`.
   * `18` Ограничение разрастания системных логов `systemd-journald` (лимит `200M`).
4. **Блок 4 — Контейнеры и L4-маскировка (Чеки 19–23):**
   * `19` Работоспособность демона Docker Engine.
   * `20` Статус контейнера `remnanode` и прослушивание порта управления API.
   * `21` Статус контейнера `caddy-remnawave` и настроенных доменов Vision / XHTTP.
   * `22` Аудит сокетов: проверка строгой изоляции порта `9443` только на `127.0.0.1` при активном L4 на `:443`.
   * `23` Проверка наличия выпущенных Let's Encrypt TLS-сертификатов для обоих поддоменов (`SELF_STEAL_DOMAIN` и `XHTTP_STEAL_DOMAIN`).
5. **Блок 5 — Безопасность периметра и связность (Чеки 24–27):**
   * `24` Активность межсетевого экрана `UFW`.
   * `25` **Strict Panel ACL:** проверка того, что порт ноды (`3000/tcp`) закрыт от мира и открыт строго для IP панели.
   * `26` Статус службы `Fail2ban` и активных джейлов `[sshd, caddy-status]`.
   * `27` Проверка исходящей HTTPS/TLS связности узла с глобальной сетью.

---

## ☁️ Настройка внешнего файрвола у облачных провайдеров

Если вы арендуете VPS у провайдеров с внешним межсетевым экраном (**Cloud.ru**, **Yandex Cloud**, **AWS**, **Oracle Cloud**, **Hetzner Cloud Firewall**), откройте входящие порты в **Security Groups**:

| Протокол | Порт | Источник (Source IP) | Назначение |
| :--- | :--- | :--- | :--- |
| **TCP** | `22` *(или ваш порт SSH)* | `0.0.0.0/0` | Доступ по SSH |
| **TCP** | `3000` *(NODE_PORT)* | `<IP_ВАШЕЙ_ПАНЕЛИ>/32` | Доступ панели Remnawave к управлению нодой |
| **TCP** | `443` | `0.0.0.0/0` | Входящий трафик клиентов (Caddy L4 → Vision / XHTTP) |
| **UDP** | `443` | `0.0.0.0/0` | QUIC / Hysteria2 (при использовании) |
| **TCP** | `80` | `0.0.0.0/0` | Выпуск и продление сертификатов Let's Encrypt (HTTP-01) |

---

## 📂 Структура файлов на сервере

* `/usr/local/bin/node-mgr` — глобальный исполняемый файл оркестратора.
* `/opt/selfsteel/` — `Dockerfile` (`caddy-l4`), `Caddyfile`, `.env`, `docker-compose.yml` и JSON-логи Caddy (`/opt/selfsteel/logs/access.log`).
* `/opt/html/` — активный HTML-шаблон маскировки для обоих Selfsteal-доменов.
* `/opt/remnanode/` — конфигурация `.env` и `docker-compose.yml` контейнера `remnanode` с подключенным томом `/certs:ro`.
* `/var/lib/node-mgr/` — сохраненные UUID и ключи API-деплоя (`remnawave-api.env`), результаты диагностики (`findings.env`) и лог фиксов (`applied-fixes.log`).
* `/etc/sysctl.d/99-lissvpn-sysctl.conf` — адаптивный Highload-профиль сетевого стека.
* `/etc/fail2ban/jail.local` — правила блокировки брутфорса SSH и сканеров Caddy.
* `/var/log/remnanode-install.log` — подробный журнал операций установщика.
