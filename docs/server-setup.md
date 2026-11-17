# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Имя виртуальной машины | devops-vm |
| Гостевая система | Ubuntu Server 24.04 LTS (64-bit) |
| Оперативная память | 2048 МБ |
| Количество ядер | 2 |
| Диск | 25 ГБ, динамически расширяемый |
| Средство виртуализации | Oracle VirtualBox 7.x |

## 2. Сетевые интерфейсы

| Адаптер | Тип | Адрес | Назначение |
|---|---|---|---|
| enp0s3 | NAT | 10.0.2.15/24 | Доступ в Интернет, обновление пакетов, проброс порта SSH |
| enp0s8 | Host-only | 192.168.56.101/24 | Прямой доступ с хостовой системы, веб-сервер в работе № 6 |

Сеть Host-only: `192.168.56.0/24`, шлюз хостовой системы `192.168.56.1`.

## 3. Правило проброса портов

| Параметр | Значение |
|---|---|
| Имя правила | ssh |
| Протокол | TCP |
| Адрес хостовой системы | 127.0.0.1 |
| Порт хостовой системы | 2222 |
| Порт гостевой системы | 2222 (после усиления SSH; до задания 2 — 22) |

## 4. Учётные записи

| Имя | Группы | Аутентификация |
|---|---|---|
| student | student, adm, sudo, … | Пароль (используется для sudo) |
| devops | devops, sudo, users | Ключ ED25519 `~/.ssh/devops_vm` (пароль отключён) |
| root | root | Вход по SSH запрещён (`PermitRootLogin no`) |

Ключ хоста: `/etc/ssh/ssh_host_ed25519_key`; отпечаток сверяется при первом подключении.

## 5. Служба SSH

- Порт: **2222**.
- Файл конфигурации: `/etc/ssh/sshd_config.d/99-hardening.conf` (основной `sshd_config` не изменялся, сохранена копия `sshd_config.backup`).
- Изменённые директивы:

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

- В `/etc/ssh/sshd_config.d/50-cloud-init.conf` директива `PasswordAuthentication yes` закомментирована: файлы читаются в лексикографическом порядке, поэтому `99-hardening.conf` не переопределяет значение из `50-cloud-init.conf`.
- Активация: `ssh.socket` отключён (`systemctl disable --now ssh.socket`), служба `ssh.service` включена (`systemctl enable --now ssh.service`).
- Проверка: `sudo sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)"`.

## 6. Правила межсетевого экрана

Политики по умолчанию: `deny (incoming)`, `allow (outgoing)`, `disabled (routed)`.

| Порт | Действие | Комментарий |
|---|---|---|
| 80/tcp | ALLOW IN | HTTP (работа № 6) |
| 443/tcp | ALLOW IN | HTTPS |
| 2222/tcp | LIMIT IN | SSH rate-limited |

Регистрация событий: `ufw logging medium`, журнал `/var/log/ufw.log`.

## 7. Снимки состояния

| Снимок | Момент создания | Содержание |
|---|---|---|
| 01-clean-install | 26.10.2026 20:27 | Чистая установка Ubuntu Server 24.04 |
| 02-keys-configured | 26.10.2026 21:57 | Учётная запись devops, ключевая аутентификация |
| 03-ssh-hardened | 26.10.2026 22:01 | Усиленная конфигурация SSH (порт 2222) |
| 04-nginx-https | 26.10.2026 23:08 | Nginx: HTTPS, самоподписанный сертификат, редирект HTTP → HTTPS, деплой rsync |
| 05-docker-compose | 27.10.2026 00:11 | Docker Compose: приложение и PostgreSQL, том db_data |

## 8. Веб-сервер

- Устанавливаемый пакет: `nginx` (Ubuntu 24.04, версия nginx/1.24.0).
- Конфигурация ресурса: `/etc/nginx/sites-available/devops-site`; символическая ссылка в `/etc/nginx/sites-enabled/`; стандартный ресурс `default` отключён.
- Каталог ресурса: `/var/www/devops-site`, владелец `devops:devops`, права каталога 755, файлов 644 (модель «владелец пишет, веб-сервер читает»).
- Сертификат: `/etc/ssl/certs/devops.crt` (права 644, владелец root); закрытый ключ: `/etc/ssl/private/devops.key` (права 600, владелец root).
- Команда формирования сертификата:

```
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

- Срок действия сертификата: 365 дней; поле SAN: `DNS:devops.local`.
- HTTP перенаправляется на HTTPS директивой `return 301 https://$host$request_uri`; протоколы TLS 1.2 и 1.3.

## 9. Контейнеризация

- Docker Engine 29.9.2 установлен из официального репозитория Docker; плагин Compose v5.6.1. Учётная запись `devops` входит в группу `docker`.
- Каталог проекта на сервере: `/home/devops/app`; файлы доставляются из каталога `app/` репозитория средствами rsync, каталог `.env` исключён из передачи и из репозитория.
- Файл `.env` хранится только на сервере, права 600; содержит `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `DB_HOST=db`.
- Сервисы Compose: `app` (образ `devops-app:1.0`, сборка из `app/Dockerfile`, процесс от имени `app`, публикация `127.0.0.1:5000:5000`) и `db` (`postgres:16-alpine`, healthcheck `pg_isready`, том `db_data`).
- Сеть проекта: пользовательская bridge-сеть `app_backend`; приложение обращается к СУБД по имени `db`; порт 5432 не публикуется.
- Том `app_db_data` сохраняется при `docker compose down` и удаляется при `docker compose down -v`.
- Публикация через Nginx: `location /app/` с `proxy_pass http://127.0.0.1:5000/` и заголовками `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`; статический ресурс `location /` сохранён.

## 10. Ansible

- Проект: каталог `ansible/` в репозитории `devops-course-2026`, ветка `feature/ansible`.
- Управляющий узел: WSL1 (Ubuntu 24.04) на хосте; Ansible core 2.16.3, sshpass 1.09; коллекции `ansible.posix` 1.6.2, `community.docker` 4.5.0, `community.general` 9.5.0.
- Управляемый узел: VM `devops-vm`, host-only `192.168.56.101:22`, Ubuntu Server 24.04.
- Inventory: `inventory/bootstrap.ini` — пользователь `student`, пароль через `--ask-pass`, только первичный запуск; `inventory/prod.ini` — пользователь `devops`, ключ `~/.ssh/devops_vm`, неинтерактивные запуски.
- Роли: `base` (проверка ОС, базовые пакеты, официальный репозиторий Docker, служба Docker); `ssh` (пользователь devops, ключ, sudo NOPASSWD, hardening SSH, UFW); `nginx` (reverse proxy на `127.0.0.1:5000`, отключение default site, проверка `nginx -t` перед reload); `app` (образ GHCR по полному SHA, контейнер, health-check).
- Образ: `ghcr.io/git867867/devops-ci-app`; тег `ded7489e859121016e4c51b797a14f875a4a549c`; публикация `127.0.0.1:5000:5000`; health endpoint `GET /health` → `{"status":"ok"}`.
- Первичный запуск: `cd ansible && ansible-playbook -i inventory/bootstrap.ini site.yml --ask-pass --ask-become-pass`.
- Повторный запуск: `ansible-playbook site.yml` (prod, без ввода пароля).
- Read-only аудит: `ansible-playbook verify.yml` (проверяет `sshd -T`, состояние контейнера и `/health`; изменений не вносит).
- Примечание: на стенде запуски выполняются с `ANSIBLE_PIPELINING=False` — на данной связке SSH pipelining приводит к зависанию на `Gathering Facts`; `ansible.cfg` при этом соответствует методичке.