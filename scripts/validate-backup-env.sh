#!/usr/bin/env bash
# Validate production backup configuration without printing values.
set -euo pipefail

ENV_FILE="${1:-${NEXA_BACKUP_ENV_FILE:-/etc/nexa/backup.env}}"
[[ -f "${ENV_FILE}" ]] || { echo "FAIL: missing backup configuration" >&2; exit 1; }
mode="$(stat -c '%a' "${ENV_FILE}" 2>/dev/null || stat -f '%OLp' "${ENV_FILE}")"
owner="$(stat -c '%U:%G' "${ENV_FILE}" 2>/dev/null || stat -f '%Su:%Sg' "${ENV_FILE}")"
[[ "${mode}" == 600 && "${owner}" == root:root ]] || { echo "FAIL: configuration must be root:root 0600" >&2; exit 1; }
echo "OK: configuration ownership and permissions"

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a
required=(NEXA_ENV BACKUP_DIR BACKUP_RETENTION_DAYS BACKUP_LOCK_FILE IDENTITY_DATABASE_URL STAYS_DATABASE_URL BACKUP_REQUIRE_REMOTE BACKUP_REMOTE_ENABLED BACKUP_REMOTE_PROVIDER BACKUP_REMOTE_PATH R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET R2_ENDPOINT R2_REGION R2_LIFECYCLE_DAYS R2_LIFECYCLE_VERIFIED AGE_RECIPIENT AGE_PRIVATE_KEY_OFFSERVER_CONFIRMED ALERT_SMTP_URL ALERT_SMTP_USERNAME ALERT_SMTP_PASSWORD ALERT_EMAIL_FROM ALERT_EMAIL_TO ALERT_WEBHOOK_URL)
for name in "${required[@]}"; do [[ -n "${!name:-}" ]] || { echo "FAIL: missing ${name}" >&2; exit 1; }; done
echo "OK: all required fields are present"

[[ "${NEXA_ENV}" == production && "${BACKUP_REQUIRE_REMOTE}" == true && "${BACKUP_REMOTE_ENABLED}" == true && "${BACKUP_REMOTE_PROVIDER}" == r2 ]] || { echo "FAIL: production R2 policy invalid" >&2; exit 1; }
[[ "${BACKUP_RETENTION_DAYS}" == 30 && "${R2_LIFECYCLE_DAYS}" == 30 && "${R2_LIFECYCLE_VERIFIED}" == true ]] || { echo "FAIL: 30-day local and remote retention required" >&2; exit 1; }
[[ "${R2_ENDPOINT}" == https://* && "${ALERT_WEBHOOK_URL}" == https://* ]] || { echo "FAIL: R2 and webhook must use HTTPS" >&2; exit 1; }
[[ "${AGE_RECIPIENT}" == age1* && "${AGE_PRIVATE_KEY_OFFSERVER_CONFIRMED}" == true ]] || { echo "FAIL: age recovery model incomplete" >&2; exit 1; }
for url in "${IDENTITY_DATABASE_URL}" "${STAYS_DATABASE_URL}"; do
  [[ "${url}" != *CHANGE_ME* && "${url}" != *REPLACE* && "${url}" != *'_dev@'* ]] || { echo "FAIL: database URL placeholder detected" >&2; exit 1; }
done
if grep -Eq 'CHANGE_ME|REPLACE_ME|age1CHANGE' "${ENV_FILE}"; then echo "FAIL: placeholder detected" >&2; exit 1; fi
echo "OK: production policy, encryption, retention, alerts, and endpoints"
echo "=== backup environment validation passed (secret values suppressed) ==="
