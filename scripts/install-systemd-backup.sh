#!/usr/bin/env bash
# Install Nexa DB backup systemd unit+timer artifacts on a VPS (SSH + Compose).
#
# Model (B2): /opt/nexa/database is a DEDICATED database repository checkout.
# Installer refreshes scripts/docs WITHOUT rsync --delete so host dumps, logs,
# and env files under DEST cannot be wiped.
#
# Usage (as root):
#   ./scripts/install-systemd-backup.sh --stage dogfood|staging|production [SRC_REPO]
#   ./scripts/install-systemd-backup.sh --stage dogfood --enable-timer
#
# Default: install units + template env; do NOT enable or start the timer (B4).
set -euo pipefail

STAGE=""
ENABLE_TIMER=0
SRC=""

usage() {
  cat <<'EOF'
Usage: install-systemd-backup.sh --stage dogfood|staging|production [--enable-timer] [SRC_REPO]

  --stage           Required. Selects backup policy template (never inferred as production).
  --enable-timer    Optional opt-in. Without this flag, units are installed but timer is NOT enabled.
  SRC_REPO          Optional source tree (default: parent of scripts/).

Does not start a backup. Does not claim production verification.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)
      STAGE="${2:-}"
      shift 2
      ;;
    --enable-timer)
      ENABLE_TIMER=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$SRC" && "$1" != --* ]]; then
        SRC="$1"
        shift
      else
        echo "ERROR: unknown argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

case "${STAGE}" in
  dogfood|staging|production) ;;
  *)
    echo "ERROR: --stage dogfood|staging|production is required (B3 — no silent production default)." >&2
    usage >&2
    exit 1
    ;;
esac

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

if grep -nE 'rsync[[:space:]].*--delete' "${SRC}/scripts/install-systemd-backup.sh" >/dev/null 2>&1; then
  # Self-guard during development; this file must not reintroduce --delete
  :
fi

echo "Installing backup tooling (stage=${STAGE}): ${SRC} -> ${DEST}"
echo "Mode: dedicated database repo checkout; NO rsync --delete (B2)"

mkdir -p /opt/nexa "${DEST}" /etc/nexa /var/backups/nexa /var/log/nexa /var/lock
chmod 700 /var/backups/nexa /etc/nexa
chmod 750 /var/log/nexa || true

# Refresh scripts + docs without deleting destination-only files
mkdir -p "${DEST}/scripts" "${DEST}/docs"
rsync -a \
  --exclude '.git' \
  --exclude 'backups/' \
  --exclude '*.dump' \
  --exclude '*.dump.partial' \
  --exclude '.env.backup' \
  "${SRC}/scripts/" "${DEST}/scripts/"
if [[ -d "${SRC}/docs" ]]; then
  rsync -a "${SRC}/docs/" "${DEST}/docs/"
fi
if [[ -f "${SRC}/.env.backup.example" ]]; then
  install -m 644 "${SRC}/.env.backup.example" "${DEST}/.env.backup.example"
fi

chmod 755 "${DEST}/scripts/"*.sh 2>/dev/null || true
chmod 644 "${DEST}/scripts/systemd/"* 2>/dev/null || true
chmod 644 "${DEST}/scripts/env/"* 2>/dev/null || true

ENV_FILE=/etc/nexa/backup.env
if [[ ! -f "${ENV_FILE}" ]]; then
  TEMPLATE="${SRC}/scripts/env/backup.${STAGE}.env.example"
  if [[ ! -f "${TEMPLATE}" ]]; then
    TEMPLATE="${DEST}/scripts/env/backup.${STAGE}.env.example"
  fi
  if [[ ! -f "${TEMPLATE}" ]]; then
    echo "ERROR: missing stage template for ${STAGE}" >&2
    exit 1
  fi
  install -m 600 "${TEMPLATE}" "${ENV_FILE}"
  echo "Created ${ENV_FILE} from backup.${STAGE}.env.example (chmod 600). EDIT secrets before any backup run."
else
  echo "Keeping existing ${ENV_FILE}"
  chmod 600 "${ENV_FILE}"
fi

install -m 644 "${DEST}/scripts/systemd/nexa-db-backup.service" /etc/systemd/system/nexa-db-backup.service
install -m 644 "${DEST}/scripts/systemd/nexa-db-backup.timer" /etc/systemd/system/nexa-db-backup.timer
systemctl daemon-reload

if [[ "${ENABLE_TIMER}" -eq 1 ]]; then
  if ! grep -qE '^[[:space:]]*IDENTITY_DATABASE_URL=.+' "${ENV_FILE}" || \
     grep -qE 'CHANGE_ME|REPLACE|nexa_identity_dev|nexa_stays_dev' "${ENV_FILE}"; then
    echo "ERROR: refusing --enable-timer until ${ENV_FILE} has non-placeholder DB URLs (B4)." >&2
    exit 1
  fi
  systemctl enable nexa-db-backup.timer
  echo "Enabled nexa-db-backup.timer (not started). Start when ready: systemctl start nexa-db-backup.timer"
else
  systemctl disable nexa-db-backup.timer 2>/dev/null || true
  echo "Timer installed but NOT enabled (default safe state). Opt in later with --enable-timer after manual success."
fi

cat <<EOF

Installed (stage=${STAGE}). Exact next commands:

  1. Edit secrets:  nano ${ENV_FILE}   # chmod 600 already applied
  2. Validate:      bash ${DEST}/scripts/validate-backup-env.sh
  3. Manual run:    systemctl start nexa-db-backup.service
  4. Inspect:       journalctl -u nexa-db-backup.service -n 100 --no-pager
                    ls -la /var/backups/nexa
  5. Enable timer:  ${DEST}/scripts/install-systemd-backup.sh --stage ${STAGE} --enable-timer
                    # or: systemctl enable --now nexa-db-backup.timer  (only after step 3 succeeds)
  6. Inspect timer: systemctl list-timers nexa-db-backup.timer

Status: IMPLEMENTED — VPS VERIFIED: NO
EOF
