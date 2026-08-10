#!/usr/bin/env bash
# Wrapper invoked by systemd. Loads /etc/nexa/backup.env (never logs secrets).
set -euo pipefail

ENV_FILE="${NEXA_BACKUP_ENV_FILE:-/etc/nexa/backup.env}"
ROOT="${NEXA_DATABASE_ROOT:-/opt/nexa/database}"
LOG_DIR="${NEXA_BACKUP_LOG_DIR:-/var/log/nexa}"

mkdir -p "${LOG_DIR}"
chmod 750 "${LOG_DIR}" || true

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"FAIL\",\"msg\":\"env.missing\",\"detail\":\"${ENV_FILE}\"}" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

# No credential defaults — /etc/nexa/backup.env must set IDENTITY_DATABASE_URL / STAYS_DATABASE_URL.
if [[ -z "${IDENTITY_DATABASE_URL:-}" || -z "${STAYS_DATABASE_URL:-}" ]]; then
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"FAIL\",\"msg\":\"env.missing\",\"detail\":\"IDENTITY_DATABASE_URL and STAYS_DATABASE_URL required\"}" >&2
  exit 1
fi

export IDENTITY_DATABASE_URL STAYS_DATABASE_URL
export BACKUP_DIR="${BACKUP_DIR:-/var/backups/nexa}"
export BACKUP_LOCK_FILE="${BACKUP_LOCK_FILE:-/var/lock/nexa-db-backup.lock}"
export NEXA_ENV="${NEXA_ENV:-production}"

exec >>"${LOG_DIR}/nexa-db-backup.log" 2>&1

if [[ -x "${ROOT}/scripts/backup-postgres.sh" ]]; then
  exec "${ROOT}/scripts/backup-postgres.sh" all
fi

echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"FAIL\",\"msg\":\"tool.missing\",\"detail\":\"${ROOT}/scripts/backup-postgres.sh\"}" >&2
exit 1
