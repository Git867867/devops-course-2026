#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
CERT_MIN_DAYS="${CERT_MIN_DAYS:-30}"
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no"  "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no"  "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
# TODO 1: проверьте, что значение параметра port отлично от 22
check "Порт SSH отличен от 22" "true" "$([ "$(sudo sshd -T | awk '/^port/{print $2}')" != "22" ] && echo true || echo false)"
# TODO 2: проверьте, что значение параметра maxauthtries равно 3
check "MaxAuthTries равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"
echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
# TODO 3: проверьте, что политика по умолчанию для входящего трафика равна deny
#         источник данных: sudo ufw status verbose | grep Default
check "Политика по умолчанию для входящего трафика — deny" "deny" "$(sudo ufw status verbose | grep Default | awk '{print $2}')"
echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
check "Конфигурация nginx корректна" "0" "$(sudo nginx -t >/dev/null 2>&1; echo $?)"
check "Сертификат действует не менее ${CERT_MIN_DAYS} дней" "0" \
      "$(sudo openssl x509 -checkend $((CERT_MIN_DAYS * 86400)) -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; echo $?)"
check "Нет файлов, доступных на запись всем" "" "$(sudo find /var/www/devops-site -perm -o+w)"
check "Права ключа TLS равны 600" "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key)"
echo "[5] Контейнеризация"
check "Служба docker активна" "active" "$(systemctl is-active docker)"
check "СУБД в состоянии healthy" "healthy" "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null)"
check "Порты 5000 и 5432 слушаются только на 127.0.0.1" "" \
      "$(ss -tln | awk '{print $4}' | grep -E ':(5000|5432)$' | grep -vE '^127\.0\.0\.1:(5000|5432)$')"
check "Права файла .env равны 600" "600" "$(sudo stat -c '%a' /home/devops/app/.env 2>/dev/null)"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
