#!/usr/bin/env bash
# PostgreSQL 16 production backup: custom dump -> age -> checksum/manifest -> R2.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup-common.sh
source "${SCRIPT_DIR}/lib/backup-common.sh"

DATABASE_FILTER="${1:-all}"
case "${DATABASE_FILTER}" in all|identity|stays) ;; *) log FAIL backup.args "expected all|identity|stays"; exit 2 ;; esac

require_env BACKUP_DIR
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_LOCK_FILE="${BACKUP_LOCK_FILE:-/var/lock/nexa-db-backup.lock}"
BACKUP_REMOTE_PATH="${BACKUP_REMOTE_PATH:-production}"

for cmd in pg_dump pg_dumpall pg_restore psql age rclone flock; do need_cmd "${cmd}"; done
assert_remote_policy_configured

mkdir -p "$(dirname "${BACKUP_LOCK_FILE}")" "${BACKUP_DIR}" "${BACKUP_DIR}/.staging"
chmod 700 "${BACKUP_DIR}" "${BACKUP_DIR}/.staging" || true
exec 9>"${BACKUP_LOCK_FILE}"
flock -n 9 || { log FAIL backup.lock "another backup is already running"; exit 1; }

RUN_TMP="$(mktemp -d "${BACKUP_DIR}/.staging/run.XXXXXXXX")"
chmod 700 "${RUN_TMP}"
cleanup() {
  find "${RUN_TMP}" -type f -print0 2>/dev/null | while IFS= read -r -d '' file; do secure_remove "${file}"; done
  rmdir "${RUN_TMP}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

TS="$(date -u +%Y-%m-%d_%H-%M-%S)"
SET_ID="${TS}_$(hostname -s)"
START_EPOCH="$(date +%s)"
TOOL_REV="$(git -C "${SCRIPT_DIR}/.." rev-parse --short HEAD 2>/dev/null || printf unknown)"
PG_DUMP_VERSION="$(pg_dump --version | head -n1)"
log INFO backup.started "set=${SET_ID} databases=${DATABASE_FILTER}"

write_manifest() {
  local db_key="$1" db_name="$2" kind="$3" artifact="$4" plain_bytes="$5" pg_version="$6" object_key="$7" representative_rows="$8" extension_count="$9"
  local enc_bytes enc_sha manifest dump_format
  enc_bytes="$(wc -c < "${artifact}" | tr -d ' ')"
  enc_sha="$(sha256_file "${artifact}")"
  manifest="${artifact}.manifest.json"
  if [[ "${kind}" == database ]]; then dump_format=custom; else dump_format=plain-roles; fi
  printf '%s\n' "{\"backup_timestamp_utc\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"backup_set\":\"${SET_ID}\",\"database_key\":\"${db_key}\",\"database_name\":\"${db_name}\",\"artifact_kind\":\"${kind}\",\"dump_format\":\"${dump_format}\",\"artifact_file\":\"$(basename "${artifact}")\",\"r2_object_key\":\"${object_key}\",\"plaintext_bytes\":${plain_bytes},\"encrypted_bytes\":${enc_bytes},\"sha256_encrypted\":\"${enc_sha}\",\"postgres_server_version\":\"${pg_version}\",\"pg_dump_version\":\"${PG_DUMP_VERSION}\",\"backup_tool_revision\":\"${TOOL_REV}\",\"encryption\":\"age\",\"representative_rows\":${representative_rows},\"extension_count\":${extension_count}}" > "${manifest}"
  chmod 600 "${manifest}"
  printf '%s' "${manifest}"
}

encrypt_upload() {
  local db_key="$1" db_name="$2" kind="$3" plain="$4" pg_version="$5" representative_rows="$6" extension_count="$7"
  local plain_bytes extension base artifact object_key manifest manifest_key
  plain_bytes="$(wc -c < "${plain}" | tr -d ' ')"
  if [[ "${kind}" == database ]]; then extension=dump; else extension=sql; fi
  base="${db_key}_${kind}_${TS}.${extension}.age"
  artifact="${BACKUP_DIR}/${base}"
  age -r "${AGE_RECIPIENT}" -o "${artifact}.partial" "${plain}" || return 1
  chmod 600 "${artifact}.partial"
  head -n1 "${artifact}.partial" | grep -qx 'age-encryption.org/v1' || {
    log FAIL backup.encryption "invalid age header database=${db_key} kind=${kind}"
    return 1
  }
  mv "${artifact}.partial" "${artifact}"
  secure_remove "${plain}"
  object_key="${BACKUP_REMOTE_PATH%/}/${SET_ID}/${base}"
  manifest="$(write_manifest "${db_key}" "${db_name}" "${kind}" "${artifact}" "${plain_bytes}" "${pg_version}" "${object_key}" "${representative_rows}" "${extension_count}")" || return 1
  manifest_key="${object_key}.manifest.json"
  r2_upload_and_verify "${artifact}" "${object_key}" "${RUN_TMP}" || return 1
  r2_upload_and_verify "${manifest}" "${manifest_key}" "${RUN_TMP}" || return 1
  log SUCCESS backup.artifact.ok "database=${db_key} kind=${kind} object=${object_key}"
}

run_one() {
  local db_key="$1" db_name="$2" env_name="$3" url
  url="${!env_name:-}"
  local db_plain roles_plain pg_version toc table representative_rows extension_count
  [[ -n "${url}" ]] || { log FAIL backup.failed "missing ${env_name}"; return 1; }
  db_plain="${RUN_TMP}/${db_key}.dump"
  roles_plain="${RUN_TMP}/${db_key}.roles.sql"
  log INFO backup.dump.begin "database=${db_key} connection=$(redact_database_url "${url}")"
  pg_version="$(psql "${url}" -XtAc 'SHOW server_version')" || return 1
  extension_count="$(psql "${url}" -XtAc 'SELECT count(*) FROM pg_extension')" || return 1
  pg_dump "${url}" -F c -b -f "${db_plain}" || return 1
  pg_dumpall --roles-only --dbname="${url}" --file="${roles_plain}" || return 1
  [[ -s "${db_plain}" && -s "${roles_plain}" ]] || { log FAIL backup.failed "empty dump database=${db_key}"; return 1; }
  toc="$(pg_restore --list "${db_plain}")" || return 1
  [[ -n "${toc}" ]] && grep -q TABLE <<<"${toc}" || { log FAIL backup.failed "invalid custom dump database=${db_key}"; return 1; }
  if [[ "${db_key}" == identity ]]; then
    for table in users refresh_tokens otp_codes schema_migrations; do grep -q "${table}" <<<"${toc}" || { log FAIL backup.failed "missing table ${table}"; return 1; }; done
    representative_rows="$(psql "${url}" -XtAc "SELECT json_build_object('users',(SELECT count(*) FROM users),'schema_migrations',(SELECT count(*) FROM schema_migrations))")" || return 1
  else
    for table in stays_listings stays_bookings stays_payment_intents stays_ledger_entries schema_migrations; do grep -q "${table}" <<<"${toc}" || { log FAIL backup.failed "missing table ${table}"; return 1; }; done
    representative_rows="$(psql "${url}" -XtAc "SELECT json_build_object('stays_listings',(SELECT count(*) FROM stays_listings),'stays_bookings',(SELECT count(*) FROM stays_bookings),'schema_migrations',(SELECT count(*) FROM schema_migrations))")" || return 1
  fi
  encrypt_upload "${db_key}" "${db_name}" database "${db_plain}" "${pg_version}" "${representative_rows}" "${extension_count}" || return 1
  encrypt_upload "${db_key}" "${db_name}" roles "${roles_plain}" "${pg_version}" "${representative_rows}" "${extension_count}" || return 1
  log SUCCESS backup.database.ok "database=${db_key}"
}

status=0
if [[ "${DATABASE_FILTER}" == all || "${DATABASE_FILTER}" == identity ]]; then run_one identity nexa_identity IDENTITY_DATABASE_URL || status=1; fi
if [[ "${DATABASE_FILTER}" == all || "${DATABASE_FILTER}" == stays ]]; then run_one stays nexa_stays STAYS_DATABASE_URL || status=1; fi

if [[ "${status}" -eq 0 ]]; then
  find "${BACKUP_DIR}" -maxdepth 1 -type f \( -name '*.age' -o -name '*.age.manifest.json' \) -mtime "+${BACKUP_RETENTION_DAYS}" -delete
  log SUCCESS backup.completed "set=${SET_ID} duration_sec=$(( $(date +%s) - START_EPOCH ))"
  exit 0
fi
log FAIL backup.failed "set=${SET_ID} duration_sec=$(( $(date +%s) - START_EPOCH ))"
exit 1
