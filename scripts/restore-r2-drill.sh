#!/usr/bin/env bash
# Download an encrypted R2 backup set and restore it into disposable PostgreSQL 16 containers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup-common.sh
source "${SCRIPT_DIR}/lib/backup-common.sh"

ENV_FILE="${NEXA_BACKUP_ENV_FILE:-/etc/nexa/backup.env}"
SET_ID=""
AGE_KEY_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-set) SET_ID="${2:-}"; shift 2 ;;
    --age-key-file) AGE_KEY_FILE="${2:-}"; shift 2 ;;
    *) echo "Usage: $0 --backup-set SET_ID --age-key-file /temporary/off-server/key" >&2; exit 2 ;;
  esac
done
[[ "$(id -u)" -eq 0 ]] || { echo "ERROR: run with sudo" >&2; exit 1; }
[[ -n "${SET_ID}" && -f "${AGE_KEY_FILE}" ]] || { echo "ERROR: backup set and readable age key required" >&2; exit 1; }
case "$(realpath "${AGE_KEY_FILE}")" in /etc/nexa/*|/var/backups/nexa/*) echo "ERROR: recovery key must be supplied from temporary/off-server media" >&2; exit 1 ;; esac
[[ -f "${ENV_FILE}" ]] || { echo "ERROR: backup configuration missing" >&2; exit 1; }
set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a
for cmd in age docker pg_restore python3 rclone; do need_cmd "${cmd}"; done
assert_remote_policy_configured

SAFE_ID="$(printf '%s' "${SET_ID}" | tr -cd 'A-Za-z0-9_.-' | cut -c1-48)"
[[ -n "${SAFE_ID}" ]] || { echo "ERROR: invalid backup set" >&2; exit 1; }
WORK_DIR="$(mktemp -d /var/tmp/nexa-restore-drill.XXXXXXXX)"
chmod 700 "${WORK_DIR}"
NETWORK="nexa-restore-${SAFE_ID}-$$"
ID_CONTAINER="${NETWORK}-identity"
ST_CONTAINER="${NETWORK}-stays"
ID_VOLUME="${NETWORK}-identity-data"
ST_VOLUME="${NETWORK}-stays-data"
PROD_BEFORE="$(docker inspect nexastays_db-identity-db-1 nexastays_db-stays-db-1 --format '{{.Id}}|{{range .Mounts}}{{.Name}}:{{.Destination}};{{end}}')"
ALERT_SCRIPT="${SCRIPT_DIR}/backup-alert.sh"

cleanup() {
  docker rm -f "${ID_CONTAINER}" "${ST_CONTAINER}" >/dev/null 2>&1 || true
  docker volume rm "${ID_VOLUME}" "${ST_VOLUME}" >/dev/null 2>&1 || true
  docker network rm "${NETWORK}" >/dev/null 2>&1 || true
  find "${WORK_DIR}" -type f -print0 2>/dev/null | while IFS= read -r -d '' file; do secure_remove "${file}"; done
  rmdir "${WORK_DIR}" 2>/dev/null || true
}
finish() {
  local rc=$?
  cleanup
  if [[ -x "${ALERT_SCRIPT}" ]]; then
    if [[ "${rc}" -eq 0 ]]; then
      "${ALERT_SCRIPT}" success all "${SET_ID}" restore-drill-completed || rc=1
    else
      "${ALERT_SCRIPT}" failure all "${SET_ID}" "isolated restore drill failed" || true
    fi
  fi
  exit "${rc}"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

configure_rclone_r2_env
PREFIX="${BACKUP_REMOTE_PATH%/}/${SET_ID}"
mapfile -t REMOTE_FILES < <(rclone lsf "$(r2_uri "${PREFIX}")" --files-only --log-level ERROR)
find_key() {
  local pattern="$1" matches=() name
  for name in "${REMOTE_FILES[@]}"; do [[ "${name}" == ${pattern} ]] && matches+=("${PREFIX}/${name}"); done
  [[ "${#matches[@]}" -eq 1 ]] || { log FAIL restore.remote "expected one ${pattern}, found ${#matches[@]}"; return 1; }
  printf '%s' "${matches[0]}"
}

restore_one() {
  local db_key="$1" container="$2" database="$3"
  local object manifest_key encrypted manifest plain expected_sha expected_bytes actual_sha actual_bytes
  object="$(find_key "${db_key}_database_*.dump.age")"
  manifest_key="${object}.manifest.json"
  encrypted="${WORK_DIR}/${db_key}.dump.age"
  manifest="${WORK_DIR}/${db_key}.manifest.json"
  plain="${WORK_DIR}/${db_key}.dump"
  r2_download "${manifest_key}" "${manifest}"
  r2_download "${object}" "${encrypted}"
  expected_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256_encrypted"])' "${manifest}")"
  expected_bytes="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["encrypted_bytes"])' "${manifest}")"
  actual_sha="$(sha256_file "${encrypted}")"
  actual_bytes="$(wc -c < "${encrypted}" | tr -d ' ')"
  [[ "${actual_sha}" == "${expected_sha}" && "${actual_bytes}" == "${expected_bytes}" ]] || { log FAIL restore.verify "encrypted object verification failed database=${db_key}"; return 1; }
  head -n1 "${encrypted}" | grep -qx 'age-encryption.org/v1'
  age --decrypt -i "${AGE_KEY_FILE}" -o "${plain}" "${encrypted}"
  pg_restore --list "${plain}" >/dev/null
  docker run --rm --network "${NETWORK}" -v "${plain}:/backup.dump:ro" postgres:16-alpine \
    pg_restore --exit-on-error --no-owner --no-acl -h "${container}" -U postgres -d "${database}" /backup.dump
  while IFS=$'\t' read -r table expected; do
    [[ "${table}" =~ ^[a-z_]+$ && "${expected}" =~ ^[0-9]+$ ]] || return 1
    actual="$(docker exec "${container}" psql -U postgres -d "${database}" -XtAc "SELECT count(*) FROM ${table}")"
    [[ "${actual}" == "${expected}" ]] || { log FAIL restore.data "row count mismatch database=${db_key} table=${table}"; return 1; }
  done < <(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [print(f"{k}\t{v}") for k,v in d["representative_rows"].items()]' "${manifest}")
  expected_extensions="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["extension_count"])' "${manifest}")"
  actual_extensions="$(docker exec "${container}" psql -U postgres -d "${database}" -XtAc 'SELECT count(*) FROM pg_extension')"
  [[ "${actual_extensions}" == "${expected_extensions}" ]] || { log FAIL restore.schema "extension count mismatch database=${db_key}"; return 1; }
  docker exec "${container}" psql -U postgres -d "${database}" -XtAc 'SELECT 1' | grep -qx 1
  secure_remove "${plain}"
  log SUCCESS restore.database.ok "database=${db_key} schema=true data=true queries=true"
}

validate_roles_artifact() {
  local db_key="$1" object encrypted plain manifest expected_sha
  object="$(find_key "${db_key}_roles_*.sql.age")"
  encrypted="${WORK_DIR}/${db_key}.roles.sql.age"
  plain="${WORK_DIR}/${db_key}.roles.sql"
  manifest="${WORK_DIR}/${db_key}.roles.manifest.json"
  r2_download "${object}.manifest.json" "${manifest}"
  r2_download "${object}" "${encrypted}"
  expected_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256_encrypted"])' "${manifest}")"
  [[ "$(sha256_file "${encrypted}")" == "${expected_sha}" ]]
  age --decrypt -i "${AGE_KEY_FILE}" -o "${plain}" "${encrypted}"
  grep -qE '^(CREATE|ALTER) ROLE ' "${plain}"
  secure_remove "${plain}"
  log SUCCESS restore.roles.validated "database=${db_key} applied=false"
}

docker network create --internal "${NETWORK}" >/dev/null
docker volume create "${ID_VOLUME}" >/dev/null
docker volume create "${ST_VOLUME}" >/dev/null
docker run -d --name "${ID_CONTAINER}" --network "${NETWORK}" -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=nexa_identity_restore -v "${ID_VOLUME}:/var/lib/postgresql/data" postgres:16-alpine >/dev/null
docker run -d --name "${ST_CONTAINER}" --network "${NETWORK}" -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=nexa_stays_restore -v "${ST_VOLUME}:/var/lib/postgresql/data" postgres:16-alpine >/dev/null
for container in "${ID_CONTAINER}" "${ST_CONTAINER}"; do
  for _ in $(seq 1 60); do docker exec "${container}" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done
  docker exec "${container}" pg_isready -U postgres >/dev/null
done

restore_one identity "${ID_CONTAINER}" nexa_identity_restore
restore_one stays "${ST_CONTAINER}" nexa_stays_restore
validate_roles_artifact identity
validate_roles_artifact stays

PROD_AFTER="$(docker inspect nexastays_db-identity-db-1 nexastays_db-stays-db-1 --format '{{.Id}}|{{range .Mounts}}{{.Name}}:{{.Destination}};{{end}}')"
[[ "${PROD_BEFORE}" == "${PROD_AFTER}" ]] || { log FAIL restore.production "production container or volume identity changed"; exit 1; }
log SUCCESS restore_drill.passed "set=${SET_ID} postgres=16 isolated_network=true host_ports=none production_unchanged=true"
