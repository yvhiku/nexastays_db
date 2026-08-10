#!/usr/bin/env bash
# Ensure external Postgres volumes exist on a blank VPS (B5). Idempotent. Non-destructive.
# Does NOT run docker compose down, does NOT delete volumes.
set -euo pipefail

IDENTITY_VOL="${NEXA_IDENTITY_PG_VOLUME:-identity_identity_pg_data}"
STAYS_VOL="${NEXA_STAYS_PG_VOLUME:-stays_stays_pg_data}"

if ! command -v docker >/dev/null 2>&1; then
  echo "FAIL: docker not found" >&2
  exit 1
fi

ensure_vol() {
  local name="$1"
  if docker volume inspect "$name" >/dev/null 2>&1; then
    echo "OK: volume exists: $name"
  else
    docker volume create "$name" >/dev/null
    echo "OK: volume created: $name"
  fi
}

ensure_vol "$IDENTITY_VOL"
ensure_vol "$STAYS_VOL"
echo "=== ensure-vps-volumes complete (no deletes) ==="
