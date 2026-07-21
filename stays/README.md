# Nexa Stays database

PostgreSQL in Docker only — the NestJS backend runs **locally** on your machine.

## Quick start

```powershell
# From repo root — all databases (recommended)
cd database
.\migrate.ps1

# Or stays only
cd database\stays
.\migrate.ps1
```

Scripts use the unified stack at `database/docker-compose.yml` (`stays-db` on port **5434**). They will:

1. Start Postgres in Docker (if not already running)
2. Apply all SQL files in `migrations/` in filename order
3. Track applied migrations in `schema_migrations`

## Connection

| Setting  | Value            |
|----------|------------------|
| Host     | `localhost`      |
| Port     | `5434`           |
| User     | `nexa_stays`     |
| Password | `nexa_stays_dev` |
| Database | `nexa_stays`     |

Use the same values in `backend/stays/.env`.

## Commands

```powershell
# Start unified stack (identity + stays + redis)
docker compose -f database/docker-compose.yml up -d

# Apply all migrations
cd database
.\migrate.ps1

# Apply stays migrations only
cd database\stays
.\migrate.ps1

# Reset DB and re-run all migrations (removes all unified-stack volumes)
.\migrate.ps1 -Reset

# Stop stack
docker compose -f database/docker-compose.yml down

# Stop and delete data
docker compose -f database/docker-compose.yml down -v
```

## Run backend locally

```powershell
copy backend\stays\.env.example backend\stays\.env
cd backend\stays
npm install
npm run start:dev
```

Set `DB_SYNCHRONIZE=false` in `.env` when using SQL migrations (recommended).

## Migrations

| File | Purpose |
|------|---------|
| `000_bootstrap.sql` | Extensions + `schema_migrations` tracker |
| `001_stays_core_tables.sql` | Core stays schema (no FK to Identity) |
| `002_stays_tables.sql` | No-op (legacy duplicate) |
| `003`–`009` | Production fields, host onboarding, reviews |
| `010_push_device_tokens.sql` | FCM push tokens |

User IDs are **opaque UUIDs** from Identity JWT (`sub`) — no `users` table in this database.
