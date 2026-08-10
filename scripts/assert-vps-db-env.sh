#!/usr/bin/env bash
# Fail closed for dogfood/staging/production DB compose credentials (B6).
# Never prints password values.
set -euo pipefail

ENV_FILE="${1:-.env.db}"
STAGE="${NEXA_ENV:-${2:-}}"

if [[ -z "$STAGE" ]]; then
  echo "FAIL: set NEXA_ENV or pass stage as arg 2 (dogfood|staging|production)" >&2
  exit 1
fi

case "$STAGE" in
  development|dev|local)
    echo "OK: development stage allows compose defaults"
    exit 0
    ;;
  dogfood|staging|production) ;;
  *)
    echo "FAIL: unsupported stage '$STAGE'" >&2
    exit 1
    ;;
esac

if [[ ! -f "$ENV_FILE" ]]; then
  echo "FAIL: missing $ENV_FILE for $STAGE (copy docker-compose.vps.env.example)" >&2
  exit 1
fi

# Restrictive perms when possible
if command -v stat >/dev/null 2>&1; then
  mode="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%OLp' "$ENV_FILE" 2>/dev/null || echo '')"
  if [[ -n "$mode" && "$mode" != "600" && "$mode" != "400" && "$mode" != "0600" && "$mode" != "0400" ]]; then
    echo "FAIL: $ENV_FILE mode $mode (require 600/400)" >&2
    exit 1
  fi
fi

get_val() {
  local key="$1"
  awk -F= -v k="$key" '
    $0 ~ /^[[:space:]]*#/ { next }
    index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }
  ' "$ENV_FILE"
}

ID_PW="$(get_val IDENTITY_DB_PASSWORD)"
ST_PW="$(get_val STAYS_DB_PASSWORD)"

if [[ -z "$ID_PW" || -z "$ST_PW" ]]; then
  echo "FAIL: IDENTITY_DB_PASSWORD and STAYS_DB_PASSWORD required" >&2
  exit 1
fi

weak() {
  local v="$1"
  [[ "$v" == "nexa_identity_dev" || "$v" == "nexa_stays_dev" ]] && return 0
  [[ "$v" == *CHANGE_ME* || "$v" == *REPLACE* ]] && return 0
  [[ "${#v}" -lt 12 ]] && return 0
  return 1
}

if weak "$ID_PW" || weak "$ST_PW"; then
  echo "FAIL: weak/default DB password rejected for $STAGE (value not printed)" >&2
  exit 1
fi

if [[ "$ID_PW" == "$ST_PW" ]]; then
  echo "FAIL: Identity and Stays DB passwords must differ" >&2
  exit 1
fi

echo "OK: $STAGE DB compose credentials reject known-dev defaults"
echo "=== assert-vps-db-env passed ==="
