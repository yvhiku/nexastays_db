#!/usr/bin/env bash
# Restore custom-format dump. Defaults to isolated target.
# Requires: Target DATABASE_URL via TARGET_DATABASE_URL
# Usage: restore-postgres.sh <identity|stays> <dump-file> [isolated|staging|production]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup-common.sh
source "${SCRIPT_DIR}/lib/backup-common.sh"

KEY="${1:?database key identity|stays}"
DUMP="${2:?dump file}"
TARGET="${3:-isolated}"

require_env TARGET_DATABASE_URL
need_cmd pg_restore
need_cmd psql

if [[ "${TARGET}" != "isolated" ]]; then
  if [[ "${RESTORE_CONFIRM:-}" != "YES" ]]; then
    log FAIL restore.denied "RESTORE_CONFIRM=YES required for ${TARGET}"
    exit 1
  fi
fi
if [[ "${TARGET}" == "production" && "${RESTORE_ALLOW_PRODUCTION:-}" != "YES" ]]; then
  log FAIL restore.denied "production restore blocked without RESTORE_ALLOW_PRODUCTION=YES"
  exit 1
fi

[[ -s "${DUMP}" ]] || { log FAIL restore.failed "missing/empty dump"; exit 1; }
pg_restore --list "${DUMP}" >/dev/null

log WARN restore.drop_schema "target=${TARGET}"
psql "${TARGET_DATABASE_URL}" -v ON_ERROR_STOP=1 -c 'DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO PUBLIC;'
set +e
pg_restore --clean --if-exists --no-owner --no-acl -d "${TARGET_DATABASE_URL}" "${DUMP}"
rc=$?
set -e
if [[ "${rc}" -gt 1 ]]; then
  log FAIL restore.failed "pg_restore exit ${rc}"
  exit 1
fi

check_table() {
  local t="$1"
  local v
  v="$(psql "${TARGET_DATABASE_URL}" -tAc "SELECT CASE WHEN to_regclass('public.${t}') IS NULL THEN 'missing' ELSE 'ok' END")"
  [[ "${v}" == "ok" ]] || { log FAIL restore.failed "missing table ${t}"; exit 1; }
}

if [[ "${KEY}" == "identity" ]]; then
  for t in users refresh_tokens otp_codes schema_migrations; do check_table "$t"; done
else
  for t in stays_listings stays_bookings stays_payment_intents stays_ledger_entries schema_migrations; do check_table "$t"; done
  psql "${TARGET_DATABASE_URL}" -tAc "SELECT 1 FROM pg_constraint WHERE conname='ex_stays_bookings_active_overlap'" | grep -q 1
  psql "${TARGET_DATABASE_URL}" -tAc "SELECT 1 FROM pg_indexes WHERE indexname='idx_stays_ledger_settled_guest_payment_unique'" | grep -q 1
fi

psql "${TARGET_DATABASE_URL}" -tAc 'SELECT COUNT(*) FROM schema_migrations' >/dev/null
log SUCCESS restore.completed "target=${TARGET} database=${KEY}"
exit 0
