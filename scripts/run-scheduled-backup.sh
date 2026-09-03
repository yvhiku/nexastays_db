#!/usr/bin/env bash
# systemd wrapper: load root-only config, run backup, and notify both channels.
set -uo pipefail

ENV_FILE="${NEXA_BACKUP_ENV_FILE:-/etc/nexa/backup.env}"
ROOT="${NEXA_DATABASE_ROOT:-/opt/nexa/backup-tools}"
LOG_DIR="${NEXA_BACKUP_LOG_DIR:-/var/log/nexa}"

mkdir -p "${LOG_DIR}"
chmod 750 "${LOG_DIR}" || true
if [[ ! -f "${ENV_FILE}" ]]; then
  printf '{"level":"FAIL","msg":"env.missing","detail":"backup configuration missing"}\n' >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a
exec >>"${LOG_DIR}/nexa-db-backup.log" 2>&1

for name in IDENTITY_DATABASE_URL STAYS_DATABASE_URL AGE_RECIPIENT R2_BUCKET ALERT_EMAIL_TO ALERT_WEBHOOK_URL; do
  if [[ -z "${!name:-}" ]]; then
    printf '{"level":"FAIL","msg":"env.missing","detail":"%s"}\n' "${name}" >&2
    exit 1
  fi
done

export BACKUP_DIR="${BACKUP_DIR:-/var/backups/nexa}"
export BACKUP_LOCK_FILE="${BACKUP_LOCK_FILE:-/var/lock/nexa-db-backup.lock}"
export NEXA_ENV="${NEXA_ENV:-production}"

BACKUP_SCRIPT="${ROOT}/scripts/backup-postgres.sh"
ALERT_SCRIPT="${ROOT}/scripts/backup-alert.sh"
if [[ ! -x "${BACKUP_SCRIPT}" || ! -x "${ALERT_SCRIPT}" ]]; then
  printf '{"level":"FAIL","msg":"tool.missing","detail":"backup or alert script missing"}\n' >&2
  exit 1
fi

"${BACKUP_SCRIPT}" all
backup_rc=$?
if [[ "${backup_rc}" -eq 0 ]]; then
  "${ALERT_SCRIPT}" success all latest-set completed
  alert_rc=$?
  [[ "${alert_rc}" -eq 0 ]] && exit 0
  printf '{"level":"FAIL","msg":"backup.alert.failed","detail":"success notification failed"}\n' >&2
  exit 1
fi

"${ALERT_SCRIPT}" failure all latest-set "backup job failed (exit ${backup_rc})"
alert_rc=$?
printf '{"level":"FAIL","msg":"backup.failed","detail":"backup_exit=%s alert_exit=%s"}\n' "${backup_rc}" "${alert_rc}" >&2
exit "${backup_rc}"
