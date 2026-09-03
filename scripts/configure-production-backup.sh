#!/usr/bin/env bash
# Interactive, no-echo creation of /etc/nexa/backup.env. Run as root on the VPS.
set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "ERROR: run with sudo" >&2; exit 1; }
umask 077
ENV_FILE="${NEXA_BACKUP_ENV_FILE:-/etc/nexa/backup.env}"
DB_ENV_FILE="${NEXA_DB_ENV_FILE:-/opt/nexa/nexastays_db/.env.db}"
[[ -f "${DB_ENV_FILE}" ]] || { echo "ERROR: missing production DB credential source" >&2; exit 1; }

read_value() {
  local key="$1"
  awk -F= -v wanted="${key}" '$1 == wanted {print substr($0, length(wanted) + 2); exit}' "${DB_ENV_FILE}"
}
urlencode() { python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().rstrip("\n"), safe=""))'; }
prompt() {
  local label="$1" var="$2" secret="${3:-false}" value
  if [[ "${secret}" == true ]]; then read -r -s -p "${label}: " value; echo; else read -r -p "${label}: " value; fi
  [[ -n "${value}" ]] || { echo "ERROR: ${label} cannot be empty" >&2; exit 1; }
  [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || { echo "ERROR: invalid control character" >&2; exit 1; }
  printf -v "${var}" '%s' "${value}"
}

identity_password="$(read_value IDENTITY_DB_PASSWORD)"
stays_password="$(read_value STAYS_DB_PASSWORD)"
[[ -n "${identity_password}" && -n "${stays_password}" ]] || { echo "ERROR: DB passwords unavailable" >&2; exit 1; }
identity_encoded="$(printf '%s' "${identity_password}" | urlencode)"
stays_encoded="$(printf '%s' "${stays_password}" | urlencode)"
unset identity_password stays_password

echo "Enter R2 values locally. Input marked secret is not echoed."
prompt "R2 account ID" r2_account
prompt "R2 access key ID" r2_access true
prompt "R2 secret access key" r2_secret true
prompt "Dedicated R2 bucket name" r2_bucket
prompt "R2 HTTPS endpoint" r2_endpoint
prompt "R2 region (normally auto)" r2_region
[[ "${r2_endpoint}" == https://* ]] || { echo "ERROR: HTTPS R2 endpoint required" >&2; exit 1; }

prompt "age public recipient (starts age1)" age_recipient
[[ "${age_recipient}" == age1* ]] || { echo "ERROR: expected an age public recipient" >&2; exit 1; }

echo "Enter SMTP and webhook destinations."
prompt "SMTP URL (smtps://host:465 or smtp://host:587)" smtp_url
prompt "SMTP username" smtp_user
prompt "SMTP password/app password" smtp_password true
prompt "Alert email From address" email_from
prompt "Alert email To address" email_to
prompt "Webhook HTTPS URL" webhook_url true
[[ "${webhook_url}" == https://* ]] || { echo "ERROR: HTTPS webhook required" >&2; exit 1; }

read -r -p "Confirm the bucket has a Cloudflare R2 delete-after-30-days lifecycle rule (type YES): " lifecycle_confirm
[[ "${lifecycle_confirm}" == YES ]] || { echo "ERROR: lifecycle confirmation required" >&2; exit 1; }
read -r -p "Confirm the matching age private key is safely stored outside the VPS (type YES): " age_confirm
[[ "${age_confirm}" == YES ]] || { echo "ERROR: off-server recovery key confirmation required" >&2; exit 1; }

mkdir -p "$(dirname "${ENV_FILE}")" /var/backups/nexa /var/log/nexa /var/lock
chmod 700 "$(dirname "${ENV_FILE}")" /var/backups/nexa
chmod 750 /var/log/nexa
tmp="$(mktemp "${ENV_FILE}.new.XXXXXXXX")"
cleanup() { rm -f "${tmp}"; }
trap cleanup EXIT INT TERM
write_var() { printf '%s=%q\n' "$1" "$2" >> "${tmp}"; }
write_var NEXA_ENV production
write_var BACKUP_DIR /var/backups/nexa
write_var BACKUP_RETENTION_DAYS 30
write_var BACKUP_LOCK_FILE /var/lock/nexa-db-backup.lock
write_var IDENTITY_DATABASE_URL "postgresql://nexa_identity:${identity_encoded}@127.0.0.1:5433/nexa_identity"
write_var STAYS_DATABASE_URL "postgresql://nexa_stays:${stays_encoded}@127.0.0.1:5434/nexa_stays"
write_var BACKUP_REQUIRE_REMOTE true
write_var BACKUP_REMOTE_ENABLED true
write_var BACKUP_REMOTE_PROVIDER r2
write_var BACKUP_REMOTE_PATH production
write_var R2_ACCOUNT_ID "${r2_account}"
write_var R2_ACCESS_KEY_ID "${r2_access}"
write_var R2_SECRET_ACCESS_KEY "${r2_secret}"
write_var R2_BUCKET "${r2_bucket}"
write_var R2_ENDPOINT "${r2_endpoint}"
write_var R2_REGION "${r2_region}"
write_var R2_LIFECYCLE_DAYS 30
write_var R2_LIFECYCLE_VERIFIED true
write_var AGE_RECIPIENT "${age_recipient}"
write_var AGE_PRIVATE_KEY_OFFSERVER_CONFIRMED true
write_var ALERT_SMTP_URL "${smtp_url}"
write_var ALERT_SMTP_USERNAME "${smtp_user}"
write_var ALERT_SMTP_PASSWORD "${smtp_password}"
write_var ALERT_EMAIL_FROM "${email_from}"
write_var ALERT_EMAIL_TO "${email_to}"
write_var ALERT_WEBHOOK_URL "${webhook_url}"
chmod 600 "${tmp}"
chown root:root "${tmp}"
mv "${tmp}" "${ENV_FILE}"
trap - EXIT INT TERM
unset r2_secret smtp_password webhook_url identity_encoded stays_encoded
echo "Created ${ENV_FILE} as root:root mode 0600. Secret values were not printed."
