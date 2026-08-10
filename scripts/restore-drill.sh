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

# wait
for p in 5433 5434 55433 55434; do
  for i in $(seq 1 60); do
    if (echo >/dev/tcp/127.0.0.1/${p}) >/dev/null 2>&1; then break; fi
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

START=$(date +%s)
bash "${ROOT}/scripts/backup-postgres.sh" all
ID_DUMP="$(ls -1t "${BACKUP_DIR}"/identity_*.dump | head -n1)"
ST_DUMP="$(ls -1t "${BACKUP_DIR}"/stays_*.dump | head -n1)"

TARGET_DATABASE_URL="postgresql://nexa_identity:nexa_identity_restore@127.0.0.1:55433/nexa_identity_restore" \
  bash "${ROOT}/scripts/restore-postgres.sh" identity "${ID_DUMP}" isolated
TARGET_DATABASE_URL="postgresql://nexa_stays:nexa_stays_restore@127.0.0.1:55434/nexa_stays_restore" \
  bash "${ROOT}/scripts/restore-postgres.sh" stays "${ST_DUMP}" isolated

END=$(date +%s)
cat > "${BACKUP_DIR}/restore-drill-result.json" <<EOF
{"ok":true,"total_duration_sec":$((END-START)),"identity_backup":"$(basename "${ID_DUMP}")","stays_backup":"$(basename "${ST_DUMP}")"}
EOF
log SUCCESS restore_drill.passed "seconds=$((END-START))"
