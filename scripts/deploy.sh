#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="${REMOTE:-devops}"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${CA_CERT:-${HOME}/devops.crt}"
ROOT="$(git rev-parse --show-toplevel)"

# Каталог site в форме, понятной rsync на текущей платформе.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        export MSYS2_ARG_CONV_EXCL="*"
        CA_CERT="$(cygpath -m "${CA_CERT}")"
        DRIVE="$(printf '%s' "${ROOT}" | cut -d: -f1 | tr 'A-Z' 'a-z')"
        REST="$(printf '%s' "${ROOT}" | cut -d: -f2-)"
        LOCAL_DIR="${ROOT}/site/"
        RSYNC_DIR="/cygdrive/${DRIVE}${REST}/site/"
        ;;
    *)
        LOCAL_DIR="${ROOT}/site/"
        RSYNC_DIR="${LOCAL_DIR}"
        ;;
esac

DRY_RUN=0
if [[ $# -gt 0 ]]; then
    if [[ "$1" == "--dry-run" ]]; then
        DRY_RUN=1
    else
        echo "Использование: $0 [--dry-run]" >&2
        exit 1
    fi
fi

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: не найден ${ROOT}/site/index.html — доставка отменена." >&2
    exit 1
fi

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения — доставка отменена." >&2
    exit 1
fi

# 3. Синхронизация каталога site/ на сервер
export RSYNC_RSH="${RSYNC_RSH:-ssh -o BatchMode=yes -o ConnectTimeout=5}"
RSYNC_DIR="${RSYNC_DIR:-${LOCAL_DIR}}"
RSYNC=(rsync -avz --delete --chmod=D755,F644)

if [[ ${DRY_RUN} -eq 1 ]]; then
    "${RSYNC[@]}" --dry-run "${RSYNC_DIR}" "${REMOTE}:${REMOTE_DIR}/"
    # 4. При --dry-run — завершение с кодом 0 без проверки доступности
    echo "Пробный запуск: изменения не вносились."
    exit 0
fi

"${RSYNC[@]}" "${RSYNC_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 5. Проверка доступности и завершение с корректным кодом возврата
if ! curl -fsS --cacert "${CA_CERT}" "${SITE_URL}/" > /dev/null; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен после доставки." >&2
    exit 1
fi
echo "Доставлен коммит $(git -C "${ROOT}" rev-parse --short HEAD)"
