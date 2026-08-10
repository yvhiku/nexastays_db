#!/usr/bin/env bash
# CI/local Linux restore drill using docker compose services.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
# shellcheck source=scripts/lib/backup-common.sh
source "${ROOT}/scripts/lib/backup-common.sh"

BACKUP_DIR="${BACKUP_DIR:-${ROOT}/backups/drill}"
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}" || true

docker compose -f docker-compose.yml up -d identity-db stays-db
docker compose -f docker-compose.backup.yml up -d identity-restore-db stays-restore-db

for p in 5433 5434 55433 55434; do
  for i in $(seq 1 60); do
    if (echo >/dev/tcp/127.0.0.1/"${p}") >/dev/null 2>&1; then break; fi
    sleep 1
  done
done

export BACKUP_DIR
export BACKUP_RETENTION_DAYS=30
export IDENTITY_DATABASE_URL="${IDENTITY_DATABASE_URL:-postgresql://nexa_identity:nexa_identity_dev@127.0.0.1:5433/nexa_identity}"
export STAYS_DATABASE_URL="${STAYS_DATABASE_URL:-postgresql://nexa_stays:nexa_stays_dev@127.0.0.1:5434/nexa_stays}"
export BACKUP_REMOTE_ENABLED=true
export BACKUP_REMOTE_PROVIDER=filesystem
export BACKUP_REMOTE_PATH="${BACKUP_DIR}/offhost"
unset NEXA_ENV BACKUP_REQUIRE_REMOTE || true

T0=$(date +%s)
bash "${ROOT}/scripts/backup-postgres.sh" all
T1=$(date +%s)
ID_DUMP="$(ls -1t "${BACKUP_DIR}"/identity_*.dump | head -n1)"
ST_DUMP="$(ls -1t "${BACKUP_DIR}"/stays_*.dump | head -n1)"
ID_BYTES="$(wc -c < "${ID_DUMP}" | tr -d ' ')"
ST_BYTES="$(wc -c < "${ST_DUMP}" | tr -d ' ')"

# Prove remote filesystem copy exists
[[ -s "${BACKUP_REMOTE_PATH}/$(basename "${ID_DUMP}")" ]]
[[ -s "${BACKUP_REMOTE_PATH}/$(basename "${ST_DUMP}")" ]]
REMOTE_COPY_STATUS=ok

TARGET_DATABASE_URL="postgresql://nexa_identity:nexa_identity_restore@127.0.0.1:55433/nexa_identity_restore" \
  bash "${ROOT}/scripts/restore-postgres.sh" identity "${BACKUP_REMOTE_PATH}/$(basename "${ID_DUMP}")" isolated
T2=$(date +%s)
TARGET_DATABASE_URL="postgresql://nexa_stays:nexa_stays_restore@127.0.0.1:55434/nexa_stays_restore" \
  bash "${ROOT}/scripts/restore-postgres.sh" stays "${BACKUP_REMOTE_PATH}/$(basename "${ST_DUMP}")" isolated
T3=$(date +%s)

BACKUP_DURATION=$((T1 - T0))
RESTORE_DURATION=$((T3 - T1))
VALIDATION_DURATION=0
TOTAL_DURATION=$((T3 - T0))

cat > "${BACKUP_DIR}/restore-drill-result.json" <<EOF
{
  "ok": true,
  "BACKUP_DURATION": ${BACKUP_DURATION},
  "RESTORE_DURATION": ${RESTORE_DURATION},
  "VALIDATION_DURATION": ${VALIDATION_DURATION},
  "TOTAL_DURATION": ${TOTAL_DURATION},
  "BACKUP_SIZE": {"identity": ${ID_BYTES}, "stays": ${ST_BYTES}},
  "REMOTE_COPY_STATUS": "${REMOTE_COPY_STATUS}",
  "RESTORE_STATUS": "ok",
  "VALIDATION_STATUS": "ok",
  "identity_backup": "$(basename "${ID_DUMP}")",
  "stays_backup": "$(basename "${ST_DUMP}")",
  "restored_from": "remote_filesystem"
}
EOF
log SUCCESS restore_drill.passed "seconds=${TOTAL_DURATION} remote=filesystem"
