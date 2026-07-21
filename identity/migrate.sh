#!/usr/bin/env sh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
SERVICE="identity-db"
PGUSER="nexa_identity"
PGDB="nexa_identity"

if [ -n "${NEXA_DATABASE_COMPOSE:-}" ]; then
  COMPOSE_FILE="$NEXA_DATABASE_COMPOSE"
elif [ -f "$ROOT/../docker-compose.yml" ]; then
  COMPOSE_FILE="$ROOT/../docker-compose.yml"
else
  COMPOSE_FILE="$ROOT/docker-compose.yml"
fi

COMPOSE_DIR="$(cd "$(dirname "$COMPOSE_FILE")" && pwd)"

cd "$COMPOSE_DIR"
docker compose -f "$COMPOSE_FILE" up -d "$SERVICE"

i=0
while [ "$i" -lt 30 ]; do
  if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" pg_isready -U "$PGUSER" -d "$PGDB" >/dev/null 2>&1; then
    break
  fi
  i=$((i + 1))
  sleep 2
done

if ! docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" pg_isready -U "$PGUSER" -d "$PGDB" >/dev/null 2>&1; then
  echo "Postgres did not become ready in time." >&2
  exit 1
fi

applied=0
skipped=0

for file in "$ROOT"/migrations/*.sql; do
  [ -f "$file" ] || continue
  name="$(basename "$file")"
  table="$(docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" psql -U "$PGUSER" -d "$PGDB" -tAc \
    "SELECT to_regclass('public.schema_migrations');" 2>/dev/null || true)"
  if [ "$table" != "schema_migrations" ]; then
    exists=""
  else
    exists="$(docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" psql -U "$PGUSER" -d "$PGDB" -tAc \
      "SELECT 1 FROM schema_migrations WHERE filename = '$name' LIMIT 1;" 2>/dev/null || true)"
  fi
  if [ "$exists" = "1" ]; then
    echo "Skip $name (already applied)"
    skipped=$((skipped + 1))
    continue
  fi
  echo "Applying $name ..."
  docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$PGDB" < "$file"
  docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" psql -U "$PGUSER" -d "$PGDB" -c \
    "INSERT INTO schema_migrations (filename) VALUES ('$name') ON CONFLICT DO NOTHING;" >/dev/null
  applied=$((applied + 1))
done

echo ""
echo "Done. Applied: $applied, skipped: $skipped"
echo "Connect: postgresql://nexa_identity:nexa_identity_dev@localhost:5433/nexa_identity"
