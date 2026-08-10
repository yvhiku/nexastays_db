#!/usr/bin/env bash
# Apply Identity + Stays SQL migrations via psql URLs (PROD-OPS-002).
# Explicit, ordered, failure-stopping. Does NOT rollback schema on failure.
# Never prints connection URLs (may contain passwords).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

IDENTITY_DATABASE_URL="${IDENTITY_DATABASE_URL:?IDENTITY_DATABASE_URL required}"
STAYS_DATABASE_URL="${STAYS_DATABASE_URL:?STAYS_DATABASE_URL required}"

redact_run() {
  # Run command; on failure print message without echoing URL env
  local label="$1"
  shift
  echo "→ $label"
  if ! "$@" >/tmp/nexa-migrate-out.txt 2>/tmp/nexa-migrate-err.txt; then
    echo "Migration failed: $label (details redacted; inspect host logs carefully)" >&2
    # Show non-URL lines only
    if [[ -f /tmp/nexa-migrate-err.txt ]]; then
      grep -vE 'postgres(ql)?://|PASSWORD|password=' /tmp/nexa-migrate-err.txt >&2 || true
    fi
    exit 1
  fi
}

migrate_dir() {
  local label="$1"
  local url="$2"
  local dir="$3"
  local applied=0
  local skipped=0

  echo "=== $label ==="
  redact_run "$label ensure schema_migrations" \
    psql "$url" -v ON_ERROR_STOP=1 -c \
    "CREATE TABLE IF NOT EXISTS schema_migrations (
       filename text PRIMARY KEY,
       applied_at timestamptz NOT NULL DEFAULT now()
     );"

  shopt -s nullglob
  for file in "$dir"/*.sql; do
    name="$(basename "$file")"
    exists="$(psql "$url" -tAc "SELECT 1 FROM schema_migrations WHERE filename = '$name' LIMIT 1;" | tr -d '[:space:]')"
    if [[ "$exists" == "1" ]]; then
      echo "Skip $name"
      skipped=$((skipped + 1))
      continue
    fi
    echo "Applying $name ..."
    if ! psql "$url" -v ON_ERROR_STOP=1 -f "$file" >/tmp/nexa-migrate-out.txt 2>/tmp/nexa-migrate-err.txt; then
      echo "FAILED applying $name — deployment must STOP. Do not auto-rollback schema." >&2
      grep -vE 'postgres(ql)?://|PASSWORD|password=' /tmp/nexa-migrate-err.txt >&2 || true
      exit 1
    fi
    psql "$url" -v ON_ERROR_STOP=1 -c \
      "INSERT INTO schema_migrations (filename) VALUES ('$name') ON CONFLICT DO NOTHING;" >/dev/null
    applied=$((applied + 1))
  done
  echo "Done $label. Applied: $applied, skipped: $skipped"
}

command -v psql >/dev/null || { echo "psql required on migrate runner" >&2; exit 1; }

migrate_dir "Identity" "$IDENTITY_DATABASE_URL" "$ROOT/identity/migrations"
migrate_dir "Stays" "$STAYS_DATABASE_URL" "$ROOT/stays/migrations"

echo "All remote migrations complete."
echo "NOTE: Never blindly reverse schema. Use expand/migrate/verify/contract for breaking changes."
