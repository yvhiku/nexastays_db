#!/usr/bin/env sh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONTAINER="nexa-stays-db"
PGUSER="nexa_stays"
PGDB="nexa_stays"

cd "$ROOT"
docker compose -f docker-compose.yml up -d

i=0
while [ "$i" -lt 30 ]; do
  if docker exec "$CONTAINER" pg_isready -U "$PGUSER" -d "$PGDB" >/dev/null 2>&1; then
    break
  fi
  i=$((i + 1))
  sleep 2
done

if ! docker exec "$CONTAINER" pg_isready -U "$PGUSER" -d "$PGDB" >/dev/null 2>&1; then
  echo "Postgres did not become ready in time." >&2
  exit 1
fi

applied=0
skipped=0

for file in "$ROOT"/migrations/*.sql; do
  [ -f "$file" ] || continue
  name="$(basename "$file")"
  table="$(docker exec "$CONTAINER" psql -U "$PGUSER" -d "$PGDB" -tAc \
    "SELECT to_regclass('public.schema_migrations');" 2>/dev/null || true)"
  if [ "$table" != "schema_migrations" ]; then
    exists=""
  else
    exists="$(docker exec "$CONTAINER" psql -U "$PGUSER" -d "$PGDB" -tAc \
      "SELECT 1 FROM schema_migrations WHERE filename = '$name' LIMIT 1;" 2>/dev/null || true)"
  fi
  if [ "$exists" = "1" ]; then
    echo "Skip $name (already applied)"
    skipped=$((skipped + 1))
    continue
  fi
  echo "Applying $name ..."
  docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$PGDB" < "$file"
  docker exec "$CONTAINER" psql -U "$PGUSER" -d "$PGDB" -c \
    "INSERT INTO schema_migrations (filename) VALUES ('$name') ON CONFLICT DO NOTHING;" >/dev/null
  applied=$((applied + 1))
done

echo ""
echo "Done. Applied: $applied, skipped: $skipped"
echo "Connect: postgresql://nexa_stays:nexa_stays_dev@localhost:5434/nexa_stays"
