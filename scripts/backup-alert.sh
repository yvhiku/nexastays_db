#!/usr/bin/env bash
# Send a redacted backup status notification to both configured channels.
set -euo pipefail

STATUS="${1:?success|failure}"
DATABASE="${2:-all}"
ARTIFACT="${3:-backup-set}"
REASON="${4:-completed}"
case "${STATUS}" in success|failure) ;; *) exit 2 ;; esac

for name in ALERT_SMTP_URL ALERT_SMTP_USERNAME ALERT_SMTP_PASSWORD ALERT_EMAIL_FROM ALERT_EMAIL_TO ALERT_WEBHOOK_URL; do
  [[ -n "${!name:-}" ]] || { printf 'backup alert configuration missing: %s\n' "${name}" >&2; exit 1; }
done

clean() { printf '%s' "$1" | tr '\r\n' '  ' | cut -c1-300; }
STATUS="$(clean "${STATUS}")"
DATABASE="$(clean "${DATABASE}")"
ARTIFACT="$(clean "${ARTIFACT}")"
REASON="$(clean "${REASON}")"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HOST="$(hostname -s)"

TMP_DIR="$(mktemp -d /tmp/nexa-alert.XXXXXXXX)"
chmod 700 "${TMP_DIR}"
cleanup() { rm -f "${TMP_DIR}"/*; rmdir "${TMP_DIR}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

MAIL_FILE="${TMP_DIR}/mail.txt"
printf 'From: %s\r\nTo: %s\r\nSubject: Nexa backup %s (%s)\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nStatus: %s\r\nTimestamp: %s\r\nHost: %s\r\nDatabase: %s\r\nArtifact: %s\r\nReason: %s\r\n' \
  "${ALERT_EMAIL_FROM}" "${ALERT_EMAIL_TO}" "${STATUS}" "${HOST}" \
  "${STATUS}" "${TIMESTAMP}" "${HOST}" "${DATABASE}" "${ARTIFACT}" "${REASON}" > "${MAIL_FILE}"
chmod 600 "${MAIL_FILE}"

curl_quote() { printf '%s' "$1" | sed 's/\\/\\\\/g;s/"/\\"/g'; }
SMTP_CONFIG="${TMP_DIR}/smtp.conf"
{
  printf 'url = "%s"\n' "$(curl_quote "${ALERT_SMTP_URL}")"
  printf 'user = "%s:%s"\n' "$(curl_quote "${ALERT_SMTP_USERNAME}")" "$(curl_quote "${ALERT_SMTP_PASSWORD}")"
  printf 'mail-from = "%s"\n' "$(curl_quote "${ALERT_EMAIL_FROM}")"
  printf 'mail-rcpt = "%s"\n' "$(curl_quote "${ALERT_EMAIL_TO}")"
  printf 'upload-file = "%s"\n' "${MAIL_FILE}"
  printf 'ssl-reqd\nsilent\nshow-error\nfail\n'
} > "${SMTP_CONFIG}"
chmod 600 "${SMTP_CONFIG}"
curl --config "${SMTP_CONFIG}"

WEBHOOK_BODY="${TMP_DIR}/webhook.json"
printf '{"service":"nexa-db-backup","status":"%s","timestamp":"%s","host":"%s","database":"%s","artifact":"%s","reason":"%s"}\n' \
  "${STATUS}" "${TIMESTAMP}" "$(clean "${HOST}")" "${DATABASE}" "${ARTIFACT}" "${REASON}" > "${WEBHOOK_BODY}"
chmod 600 "${WEBHOOK_BODY}"
WEBHOOK_CONFIG="${TMP_DIR}/webhook.conf"
{
  printf 'url = "%s"\n' "$(curl_quote "${ALERT_WEBHOOK_URL}")"
  printf 'request = "POST"\nheader = "Content-Type: application/json"\n'
  printf 'data-binary = "@%s"\n' "${WEBHOOK_BODY}"
  printf 'silent\nshow-error\nfail\nmax-time = 20\n'
} > "${WEBHOOK_CONFIG}"
chmod 600 "${WEBHOOK_CONFIG}"
curl --config "${WEBHOOK_CONFIG}"

printf '{"ts":"%s","level":"SUCCESS","msg":"backup.alerts.sent","detail":"email=true webhook=true status=%s"}\n' "${TIMESTAMP}" "${STATUS}"
