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
