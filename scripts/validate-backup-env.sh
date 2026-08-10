#!/usr/bin/env bash
# Validate /etc/nexa/backup.env without printing secrets (B3/B4/B6).
set -euo pipefail

ENV_FILE="${1:-${NEXA_BACKUP_ENV_FILE:-/etc/nexa/backup.env}}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "FAIL: missing $ENV_FILE" >&2
  exit 1
fi

# Permission check (Unix)
if command -v stat >/dev/null 2>&1; then
  mode="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%OLp' "$ENV_FILE" 2>/dev/null || echo '')"
  if [[ -n "$mode" ]]; then
    # Accept 600 or 400
    if [[ "$mode" != "600" && "$mode" != "400" && "$mode" != "0600" && "$mode" != "0400" ]]; then
      echo "FAIL: $ENV_FILE mode is $mode (require 600 or 400)" >&2
      exit 1
    fi
    echo "OK: env permissions restrictive ($mode)"
  fi
fi

get_val() {
  local key="$1"
  awk -F= -v k="$key" '
    $0 ~ /^[[:space:]]*#/ { next }
    index($0, k "=") == 1 {
      v = substr($0, length(k) + 2)
      gsub(/\r/, "", v)
      print v
      exit
    }
  ' "$ENV_FILE"
}

req() {
  local k="$1"
  local v
  v="$(get_val "$k")"
  if [[ -z "$v" ]]; then
    echo "FAIL: missing $k" >&2
    exit 1
  fi
  echo "OK: $k is set"
}

req NEXA_ENV
req IDENTITY_DATABASE_URL
req STAYS_DATABASE_URL
req BACKUP_DIR

NEXA_ENV="$(get_val NEXA_ENV)"
ID_URL="$(get_val IDENTITY_DATABASE_URL)"
ST_URL="$(get_val STAYS_DATABASE_URL)"

case "$NEXA_ENV" in
  dogfood|staging|production) echo "OK: NEXA_ENV=$NEXA_ENV" ;;
  *) echo "FAIL: invalid NEXA_ENV" >&2; exit 1 ;;
esac

for url in "$ID_URL" "$ST_URL"; do
  if echo "$url" | grep -qE 'CHANGE_ME|REPLACE|nexa_identity_dev|nexa_stays_dev'; then
    echo "FAIL: database URL still contains placeholder or known-dev password (value not printed)" >&2
    exit 1
  fi
done
echo "OK: database URLs reject known-dev / placeholder patterns"

if [[ "$NEXA_ENV" == "production" ]]; then
  REQUIRE="$(get_val BACKUP_REQUIRE_REMOTE)"
  ENABLED="$(get_val BACKUP_REMOTE_ENABLED)"
  if [[ "${REQUIRE}" != "true" && "${ENABLED}" != "true" ]]; then
    echo "FAIL: production requires remote backup enabled" >&2
    exit 1
  fi
  echo "OK: production remote policy flags present"
fi

echo "=== backup env validation passed ==="
