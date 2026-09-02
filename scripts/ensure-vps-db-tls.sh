#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
compose="$root/docker-compose.yml"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
  -subj "/CN=nexa-postgres" \
  -keyout "$tmp/server.key" -out "$tmp/server.crt" >/dev/null 2>&1
chmod 600 "$tmp/server.key"
chmod 644 "$tmp/server.crt"

cd "$root"
docker compose -f "$compose" up -d identity-db stays-db

for service in identity-db stays-db; do
  container="$(docker compose -f "$compose" ps -q "$service")"
  [[ -n "$container" ]] || { echo "Missing container for $service" >&2; exit 1; }
  docker cp "$tmp/server.key" "$container:/var/lib/postgresql/data/server.key"
  docker cp "$tmp/server.crt" "$container:/var/lib/postgresql/data/server.crt"
  docker exec -u root "$container" chown postgres:postgres \
    /var/lib/postgresql/data/server.key /var/lib/postgresql/data/server.crt
  docker exec -u root "$container" chmod 600 /var/lib/postgresql/data/server.key
  docker exec -u root "$container" chmod 644 /var/lib/postgresql/data/server.crt
  echo "TLS material installed for $service"
done

echo "PostgreSQL TLS material is present in both persistent data volumes."
