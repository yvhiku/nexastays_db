#!/usr/bin/env sh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$ROOT/docker-compose.yml"

echo "Starting unified database stack (identity, stays, redis)..."
cd "$ROOT"
docker compose -f "$COMPOSE_FILE" up -d

echo ""
echo "=== Identity migrations ==="
NEXA_DATABASE_COMPOSE="$COMPOSE_FILE" "$ROOT/identity/migrate.sh"

echo ""
echo "=== Stays migrations ==="
NEXA_DATABASE_COMPOSE="$COMPOSE_FILE" "$ROOT/stays/migrate.sh"

echo ""
echo "All migrations complete."
