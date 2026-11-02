<div align="center">

# 🦊 LissVPN Node Orchestrator (`node-mgr`)

**Production-ready оркестратор, Highload-оптимизатор ядра и 27-точечный диагностический тулкит для прокси-узлов RemnawaveNode & Xray Reality (Caddy Selfsteal)**

[![Version](https://img.shields.io/badge/version-v3.3.1-F56E0F?style=for-the-badge&logo=linux&logoColor=white)](https://github.com/Lissovich-Liss/vpn-node)
[![OS](https://img.shields.io/badge/Ubuntu_22.04%2F24.04_%7C_Debian_11%2F12-151419?style=for-the-badge&logo=debian&logoColor=F56E0F)](https://github.com/Lissovich-Liss/vpn-node)
[![Docker](https://img.shields.io/badge/Docker-Compose_v2-151419?style=for-the-badge&logo=docker&logoColor=F56E0F)](https://github.com/Lissovich-Liss/vpn-node)
[![Security](https://img.shields.io/badge/UFW_+_Fail2ban-Strict_ACL-2ECC71?style=for-the-badge&logo=shield&logoColor=white)](https://github.com/Lissovich-Liss/vpn-node)

</div>

---

## ⚡ Ключевые возможности

* **📦 Автоматическое развертывание RemnawaveNode:** генерация изолированного окружения `/opt/remnanode`, автоматическое скачивание свежего бинарника `Xray-core` с GitHub, настройка ротации логов и повышенных лимитов дескрипторов (`nofile: 1048576`).
* **🔒 Маскировка трафика Caddy Selfsteal:**
  * Работа на локальном loopback-интерфейсе (`127.0.0.1:9443`) с защитой от внешнего сканирования.
  * Поддержка стандартных сертификатов **Let's Encrypt (HTTP-01)** и **Wildcard-сертификатов (DNS-01)** через Cloudflare API с предварительной валидацией токена.
  * **11 готовых SNI-шаблонов** маскировки с автоматическим внедрением уникальной криптографической сигнатуры (`data-edge-rev`) при каждой установке для защиты от сигнатурного парсинга цензорами.
* **🛡️ Жесткая сетевая изоляция (Strict Panel ACL):**
  * Порт управления нодой (`3000/tcp`) закрыт от внешнего мира и открывается в `UFW` **исключительно для белого IP-адреса панели Remnawave**.
  * Локальный fallback-порт Caddy (`9443`) принудительно блокируется на входящих интерфейсах.
* **🚫 Защита от атак и сканеров (Fail2ban v3):**
  * Автоматическая поддержка `systemd-journald` (`python3-systemd`) на Debian 12 / Ubuntu 24.04 без падений демона.
  * Блокировка брутфорса SSH и веб-сканеров уязвимостей по JSON-логам Caddy с прогрессивным увеличением времени бана до 7 суток.
* **🚀 Адаптивный Highload-тюнинг ядра Linux:**
  * Автоматический расчет буферов сокетов (`rmem_max`/`wmem_max` до 64 МБ) и таблицы `nf_conntrack` (до 1 млн сессий) под объем RAM сервера (*Lite* / *Standard* / *Highload*).
  * Включение **BBR / BBRv3 (XanMod)**, планировщика `fq`, распределение сетевых прерываний по всем ядрам **RPS/RFS**, аппаратные оффлоады сетевой карты **GRO/GSO/TSO**, фиксация **TCPMSS clamp to PMTU** и сжатый **Zram-swap**.
* **🩺 Встроенная 27-точечная диагностика (`Doctor`):** полный аудит ресурсов, CPU Steal, параметров ядра, контейнеров, SSL-сертификатов и правил безопасности с возможностью авто-исправления находок одной командой (`--from-findings`).

---

## 🚀 Быстрый старт (Установка одной командой)

Подключитесь к чистому серверу под управлением **Ubuntu 22.04 / 24.04** или **Debian 11 / 12** от имени `root` (`sudo -i`) и выполните:

```bash
curl -fsSL "[https://raw.githubusercontent.com/Lissovich-Liss/vpn-node/main/node-mgr.sh?t=$(date](https://raw.githubusercontent.com/Lissovich-Liss/vpn-node/main/node-mgr.sh?t=$(date) +%s)" -o /usr/local/bin/node-mgr && chmod +x /usr/local/bin/node-mgr && node-mgr
```

> 💡 После первого запуска утилита прописывается в систему глобально. В дальнейшем для вызова меню из любой точки терминала достаточно ввести:
> ```bash
> node-mgr
> ```

---

## 🖥️ Интерактивное меню (TUI)

При запуске `node-mgr` без аргументов открывается интерактивная панель управления:

```text
  LISSVPN NODE ORCHESTRATOR  v3.3.1 · node-mgr toolkit
  ────────────────────────────────────────────────────────────────────
  2026-11-02 14:00 UTC · edge-node-01 · kvm · IP: 84.54.57.173

    [1] Диагностика ноды     27 чеков, дашборд, аудит безопасности и вердикт
    [2] Оптимизация стека    sysctl / BBR / FD / RPS / NIC / TCPMSS / Zram
    [3] Полная установка     RemnawaveNode + Caddy Selfsteal + UFW + Fail2ban
    [4] Выборочный запуск    установка или починка отдельных компонентов
    [5] Статус системы       контейнеры, ядро, UFW ACL, наложенные артефакты
    [6] Ядро BBRv3 (XanMod)  установка ядра XanMod под микроархитектуру CPU
    [7] Сменить шаблон SNI   быстрая смена HTML-лендинга Caddy Selfsteal
    [8] Обновить компоненты  docker pull + Xray-core + self-update скрипта
    [9] Откат / Удаление     снять оптимизации (rollback) или удалить узел
    [0] Выход
```

### Пошаговый порядок развертывания новой ноды:
1. Запустите `node-mgr` и выберите пункт **`[3] Полная установка`**.
2. Скрипт автоматически применит Highload-оптимизации ядра, настроит RPS/NIC и установит Docker Engine.
3. Вставьте `SECRET_KEY` из панели Remnawave (*Nodes → Add Node*), укажите порт API (по умолчанию `3000`) и введите **белый IP-адрес вашей панели Remnawave**.
4. Укажите домен маскировки для Caddy Selfsteal (например, `cdn.lissvpn.com`), выберите тип сертификата (обычный HTTP-01 или Wildcard Cloudflare) и один из 11 шаблонов сайта.
5. Подтвердите настройку `UFW` и `Fail2ban`.
6. По завершении откройте пункт **`[1] Диагностика ноды`**, чтобы убедиться, что все 27 проверок горят зеленым статусом `[ PASS ]`.

---

## 🛠️ Справочник команд CLI

Утилита поддерживает прямой вызов модулей из командной строки для автоматизации и быстрой диагностики:

| Команда | Описание |
| :--- | :--- |
| `node-mgr` | Запуск интерактивного TUI-меню |
| `node-mgr diagnose` | Запуск полной диагностики ноды (27 чеков + сохранение находок) |
| `node-mgr diagnose -q` | Быстрая диагностика без внешних сетевых тестов |
| `node-mgr optimize --all` | Применить весь комплекс оптимизаций (`sysctl`, `FD`, `RPS`, `NIC`, `MSS`, `journald`) |
| `node-mgr optimize --from-findings` | Автоматически исправить только те проблемы, которые выявила диагностика |
| `node-mgr optimize --zram` | Активировать сжатый Zram-swap в оперативной памяти (50% от RAM) |
| `node-mgr status` | Показать дашборд состояния ядра, контейнеров и наложенных оптимизаций |
| `node-mgr logs node` | Просмотр логов контейнера `remnanode` в реальном времени |
| `node-mgr logs caddy` | Просмотр логов контейнера `caddy-selfsteal` в реальном времени |
| `node-mgr logs f2b` | Просмотр журнала службы `Fail2ban` |
| `node-mgr change-template` | Быстрая смена HTML-шаблона маскировки без перезапуска Caddy |
| `node-mgr bbr3` | Установка кастомного ядра **XanMod** с поддержкой **BBRv3** |
| `node-mgr update` | Обновление Docker-образов ноды, Caddy и бинарника `Xray-core` |
| `node-mgr self-update` | Обновление самого скрипта `node-mgr` напрямую с GitHub |
| `node-mgr export-config` | Экспорт текущей конфигурации в `/etc/remnanode-install.conf` |
| `node-mgr rollback` | Безопасный откат всех наложенных сетевых оптимизаций до заводских |
| `node-mgr uninstall` | Полное удаление контейнеров, конфигураций и откат настроек |

---

## 🤖 Автоматическая (Unattended) установка через конфиг

Для клонирования нод без участия оператора экспортируйте конфиг на настроенном сервере:
```bash
node-mgr export-config /etc/remnanode-install.conf
```
Либо создайте файл `/etc/remnanode-install.conf` вручную на новом сервере:

```ini
CFG_SECRET_KEY="ВАШ_КЛЮЧ_ИЗ_ПАНЕЛИ"
CFG_NODE_PORT=3000
CFG_PANEL_IP="31.59.178.16"
CFG_DOMAIN="edge-01.lissvpn.com"
CFG_CERT_TYPE=1
CFG_CADDY_PORT=9443
CFG_APPLY_NETWORK=y
CFG_SETUP_UFW=y
CFG_INSTALL_FAIL2BAN=y
```

Запустите установку в автоматическом режиме:
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
4. **Блок 4 — Контейнеры и маскировка (Чеки 19–23):**
   * `19` Работоспособность демона Docker Engine.
   * `20` Статус контейнера `remnanode` и прослушивание порта API.
   * `21` Статус контейнера `caddy-selfsteal`.
   * `22` Аудит сокетов: проверка строгой изоляции порта `9443` только на `127.0.0.1` (отсутствие утечки на `0.0.0.0`).
   * `23` Проверка наличия выпущенного TLS-сертификата в хранилище Caddy.
5. **Блок 5 — Безопасность периметра и связность (Чеки 24–27):**
   * `24` Активность межсетевого экрана `UFW`.
   * `25` **Strict Panel ACL:** проверка того, что порт ноды (`3000/tcp`) закрыт от мира и открыт строго для IP панели.
   * `26` Статус службы `Fail2ban` и активных джейлов `[sshd, caddy-status]`.
   * `27` Проверка исходящей HTTPS/TLS связности узла с глобальной сетью.

---

## ☁️ Важно: Настройка внешнего файрвола у облачных провайдеров

Если вы арендуете VPS у облачных провайдеров с внешним межсетевым экраном (**Cloud.ru**, **Yandex Cloud**, **AWS**, **Oracle Cloud**, **Hetzner Cloud Firewall**), обязательно откройте следующие входящие порты в **Группах безопасности (Security Groups)** в личном кабинете хостера:

| Протокол | Порт | Источник (Source IP) | Назначение |
| :--- | :--- | :--- | :--- |
| **TCP** | `22` *(или ваш порт SSH)* | `0.0.0.0/0` | Доступ по SSH |
| **TCP** | `3000` *(NODE_PORT)* | `<IP_ВАШЕЙ_ПАНЕЛИ>/32` | Доступ панели Remnawave к управлению нодой |
| **TCP** | `443` | `0.0.0.0/0` | Входящий трафик клиентов Xray Reality |
| **UDP** | `443` | `0.0.0.0/0` | Трафик Xray QUIC / HTTP3 |
| **TCP** | `80` | `0.0.0.0/0` | Выпуск и продление сертификатов Let's Encrypt |

---

## ⚙️ Настройка Inbound в панели Remnawave под Caddy Selfsteal

После того как нода перешла в статус **Online**, используйте следующие параметры `realitySettings` в конфигурации Inbound в панели Remnawave:

```json
{
  "show": false,
  "dest": "127.0.0.1:9443",
  "xver": 0,
  "serverNames": [
    "ваш-домен-маскировки.com"
  ],
  "privateKey": "СГЕНЕРИРОВАННЫЙ_PRIVATE_KEY",
  "shortIds": [
    "a1b2c3d4",
    "e5f60718293a4b5c"
  ]
}
```

---

## 📂 Структура файлов на сервере

* `/usr/local/bin/node-mgr` — глобальный исполняемый файл оркестратора.
* `/opt/remnanode/` — конфигурация `.env` и `docker-compose.yml` контейнера ноды.
* `/var/lib/remnanode/` — бинарник ядра `xray`, базы `geoip.dat` и `geosite.dat`.
* `/opt/caddy/` — `Caddyfile`, `.env`, логи и директория HTML-шаблона маскировки (`/opt/caddy/html`).
* `/etc/sysctl.d/99-lissvpn-sysctl.conf` — адаптивный Highload-профиль сетевого стека.
* `/etc/fail2ban/jail.local` — правила блокировки брутфорса и сканеров.
* `/var/lib/node-mgr/` — состояние последней диагностики (`findings.env`) и журнал примененных фиксов.
* `/var/log/remnanode-install.log` — подробный журнал операций установщика.
