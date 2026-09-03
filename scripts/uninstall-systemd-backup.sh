#!/usr/bin/env bash
# Remove Nexa DB backup systemd unit+timer. Does not delete backups or /etc/nexa/backup.env.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

systemctl stop nexa-db-backup.timer 2>/dev/null || true
systemctl stop nexa-db-backup.service 2>/dev/null || true
systemctl disable nexa-db-backup.timer 2>/dev/null || true
rm -f /etc/systemd/system/nexa-db-backup.timer
rm -f /etc/systemd/system/nexa-db-backup.service
systemctl daemon-reload
systemctl reset-failed nexa-db-backup.service 2>/dev/null || true

echo "Removed systemd timer/service."
echo "Left in place (safe by default): /etc/nexa/backup.env, /var/backups/nexa, /opt/nexa/backup-tools"
echo "Delete those manually if retiring the host."
