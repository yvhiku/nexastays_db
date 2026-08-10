#!/usr/bin/env bash
# Install Nexa DB backup systemd unit+timer on a VPS (SSH + Docker Compose topology).
# Target layout: /opt/nexa/database ← this repository (or a sync of scripts+docs).
#
# Usage (on VPS as root):
#   ./scripts/install-systemd-backup.sh [/path/to/database-repo]
#
# Does NOT claim production verification — prints verification checklist.
set -euo pipefail

SRC="${1:-}"
if [[ -z "${SRC}" ]]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
SRC="$(cd "${SRC}" && pwd)"
DEST="${NEXA_DATABASE_ROOT:-/opt/nexa/database}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

if [[ ! -f "${SRC}/scripts/backup-postgres.sh" ]]; then
  echo "ERROR: ${SRC}/scripts/backup-postgres.sh not found" >&2
  exit 1
fi

echo "Installing backup tooling: ${SRC} -> ${DEST}"
mkdir -p /opt/nexa /etc/nexa /var/backups/nexa /var/log/nexa /var/lock
chmod 700 /var/backups/nexa /etc/nexa
chmod 750 /var/log/nexa || true

rsync -a --delete \
  --exclude '.git' \
  --exclude 'backups' \
  --exclude '.env.backup' \
  "${SRC}/" "${DEST}/"

chmod 755 "${DEST}/scripts/"*.sh
chmod 644 "${DEST}/scripts/systemd/"*

if [[ ! -f /etc/nexa/backup.env ]]; then
  if [[ -f "${DEST}/.env.backup.example" ]]; then
    cp "${DEST}/.env.backup.example" /etc/nexa/backup.env
  else
    touch /etc/nexa/backup.env
  fi
  chmod 600 /etc/nexa/backup.env
  cat >> /etc/nexa/backup.env <<'EOF'

# --- VPS production defaults (edit secrets before enabling timer) ---
NEXA_ENV=production
BACKUP_DIR=/var/backups/nexa
BACKUP_RETENTION_DAYS=30
BACKUP_REQUIRE_REMOTE=true
BACKUP_REMOTE_ENABLED=true
BACKUP_REMOTE_PROVIDER=s3
# IDENTITY_DATABASE_URL=postgresql://...@127.0.0.1:5433/nexa_identity
# STAYS_DATABASE_URL=postgresql://...@127.0.0.1:5434/nexa_stays
# S3_ENDPOINT=https://...
# S3_BUCKET=nexa-db-backups
# S3_REGION=auto
# S3_ACCESS_KEY_ID=
# S3_SECRET_ACCESS_KEY=
# BACKUP_REMOTE_PATH=production/
EOF
  echo "Created /etc/nexa/backup.env — EDIT SECRETS before starting the timer."
else
  echo "Keeping existing /etc/nexa/backup.env"
fi

install -m 644 "${DEST}/scripts/systemd/nexa-db-backup.service" /etc/systemd/system/nexa-db-backup.service
install -m 644 "${DEST}/scripts/systemd/nexa-db-backup.timer" /etc/systemd/system/nexa-db-backup.timer

systemctl daemon-reload
systemctl enable nexa-db-backup.timer
# Do NOT start until env is configured — operator runs verification manually first.
echo
echo "Installed. Next steps (PRODUCTION VERIFICATION — not done by this script):"
echo "  1. Edit /etc/nexa/backup.env (DB URLs + S3 + NEXA_ENV=production)"
echo "  2. Manual: systemctl start nexa-db-backup.service && journalctl -u nexa-db-backup.service -n 100 --no-pager"
echo "  3. Verify dumps in /var/backups/nexa and remote bucket objects"
echo "  4. Start timer: systemctl start nexa-db-backup.timer"
echo "  5. Check: systemctl list-timers nexa-db-backup.timer"
echo "  6. Isolated restore-from-remote drill (see docs/PRODUCTION_BACKUP_AND_RESTORE.md)"
echo
echo "Status: IMPLEMENTED / LOCALLY installable — VPS VERIFIED: NO (requires operator evidence)"
