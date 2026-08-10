#!/usr/bin/env bash
# Nexa Postgres backup (custom format). Linux/macOS + CI companion to backup-postgres.ps1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup-common.sh
source "${SCRIPT_DIR}/lib/backup-common.sh"

DATABASE_FILTER="${1:-all}" # all|identity|stays

require_env BACKUP_DIR
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}" || true

need_cmd pg_dump
need_cmd pg_restore

TS="$(date -u +%Y-%m-%d_%H-%M-%S)"
log INFO backup.started "databases=${DATABASE_FILTER} ts=${TS}"

run_one() {
  local key="$1"
  local env_name="$2"
  local url="${!env_name:-}"
  if [[ -z "${url}" ]]; then
    log FAIL backup.failed "missing ${env_name}"
    return 1
  fi
  # redact password from logged URL
  local redacted
  redacted="$(echo "${url}" | sed -E 's#(postgres(ql)?://[^:]+:)[^@]+#\1***#')"
  local file="${key}_${TS}.dump"
  local out="${BACKUP_DIR}/${file}"
  local partial="${out}.partial"
  rm -f "${partial}"
  log INFO backup.dump.begin "database=${key} connection=${redacted} file=${file}"
  pg_dump "${url}" -F c -b -f "${partial}"
  mv "${partial}" "${out}"
  if [[ ! -s "${out}" ]]; then
    log FAIL backup.failed "empty archive ${file}"
    return 1
  fi
  local list
  list="$(pg_restore --list "${out}")"
  [[ -n "${list}" ]] || { log FAIL backup.failed "empty TOC"; return 1; }
  echo "${list}" | grep -q TABLE || { log FAIL backup.failed "no TABLE in TOC"; return 1; }
  local expected
  if [[ "${key}" == "identity" ]]; then
    expected=(users refresh_tokens otp_codes schema_migrations)
  else
    expected=(stays_listings stays_bookings stays_payment_intents stays_ledger_entries schema_migrations)
  fi
  local t
  for t in "${expected[@]}"; do
    echo "${list}" | grep -q "${t}" || { log FAIL backup.failed "missing table ${t}"; return 1; }
  done

  if [[ "${BACKUP_REMOTE_ENABLED:-false}" == "true" ]]; then
    case "${BACKUP_REMOTE_PROVIDER:-filesystem}" in
      filesystem)
        require_env BACKUP_REMOTE_PATH
        mkdir -p "${BACKUP_REMOTE_PATH}"
        cp "${out}" "${BACKUP_REMOTE_PATH}/${file}"
        log SUCCESS backup.remote.ok "provider=filesystem file=${file}"
        ;;
      s3)
        require_env S3_BUCKET
        need_cmd aws
        local prefix="${BACKUP_REMOTE_PATH:-}"
        local key_path="${file}"
        if [[ -n "${prefix}" ]]; then key_path="${prefix%/}/${file}"; fi
        local aws_args=(s3 cp "${out}" "s3://${S3_BUCKET}/${key_path}")
        if [[ -n "${S3_ENDPOINT:-}" ]]; then aws_args+=(--endpoint-url "${S3_ENDPOINT}"); fi
        AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID:-}" AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY:-}" \
          AWS_DEFAULT_REGION="${S3_REGION:-us-east-1}" aws "${aws_args[@]}"
        log SUCCESS backup.remote.ok "provider=s3 bucket=${S3_BUCKET}"
        ;;
      *)
        log FAIL backup.failed "unsupported BACKUP_REMOTE_PROVIDER"
        return 1
        ;;
    esac
  fi

  # retention: delete matching dumps older than retention, never newest, never today's (UTC day)
  local newest
  newest="$(ls -1t "${BACKUP_DIR}/${key}_"*.dump 2>/dev/null | head -n1 || true)"
  local cutoff
  cutoff="$(date -u -d "-${BACKUP_RETENTION_DAYS} days" +%Y-%m-%d 2>/dev/null || date -u -v-"${BACKUP_RETENTION_DAYS}"d +%Y-%m-%d)"
  local today
  today="$(date -u +%Y-%m-%d)"
  local f base day
  for f in "${BACKUP_DIR}/${key}_"*.dump; do
    [[ -e "${f}" ]] || continue
    base="$(basename "${f}")"
    [[ "${base}" =~ ^${key}_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.dump$ ]] || continue
    [[ "${f}" == "${newest}" ]] && continue
    day="$(echo "${base}" | sed -E "s/^${key}_([0-9]{4}-[0-9]{2}-[0-9]{2})_.*$/\1/")"
    [[ "${day}" == "${today}" ]] && continue
    if [[ "${day}" < "${cutoff}" ]]; then
      rm -f "${f}"
      log INFO backup.retention "removed=${base}"
    fi
  done
  log SUCCESS backup.database.ok "database=${key} file=${file} bytes=$(wc -c < "${out}" | tr -d ' ')"
}

ok=0
if [[ "${DATABASE_FILTER}" == "all" || "${DATABASE_FILTER}" == "identity" ]]; then
  require_env IDENTITY_DATABASE_URL
  run_one identity IDENTITY_DATABASE_URL || ok=1
fi
if [[ "${DATABASE_FILTER}" == "all" || "${DATABASE_FILTER}" == "stays" ]]; then
  require_env STAYS_DATABASE_URL
  run_one stays STAYS_DATABASE_URL || ok=1
fi

if [[ "${ok}" -eq 0 ]]; then
  log SUCCESS backup.completed "ok=true"
  exit 0
fi
log FAIL backup.failed "ok=false"
exit 1
