# Database

SQL migrations live here — one folder per product database.

```
database/
├── docker-compose.yml     # Unified dev stack: identity-db, stays-db, redis
├── migrate.ps1            # Run all migrations (recommended)
├── identity/migrations/   # Nexa Identity (SSO) — PostgreSQL nexa_identity :5433
└── stays/migrations/      # Nexa Stays — PostgreSQL nexa_stays :5434
```

## Dev setup (recommended)

Use the **unified Docker Compose stack** in this folder. It runs:

| Service      | Port | Database / role        |
|--------------|------|------------------------|
| `identity-db`| 5433 | `nexa_identity`        |
| `stays-db`   | 5434 | `nexa_stays`           |
| `redis`      | 6379 | Cache / sessions       |

```powershell
cd database
.\migrate.ps1
```

This starts the stack (if needed) and applies identity then stays migrations in order. New SQL files go in `identity/migrations/` or `stays/migrations/` — re-run `migrate.ps1` to apply them.

### Per-database migrations

Individual scripts also target the unified stack by default:

```powershell
cd database\identity
.\migrate.ps1

cd database\stays
.\migrate.ps1
```

On macOS/Linux:

```sh
cd database && ./migrate.sh
```

Override the compose file with `-ComposeFile` (PowerShell) or `NEXA_DATABASE_COMPOSE` (shell).

### Connection strings

- Identity: `postgresql://nexa_identity:nexa_identity_dev@localhost:5433/nexa_identity`
- Stays: `postgresql://nexa_stays:nexa_stays_dev@localhost:5434/nexa_stays`

Backend defaults match these ports (`backend/identity/.env`, `backend/stays/.env`).

## Adding a migration

1. Add `NNN_description.sql` under `identity/migrations/` or `stays/migrations/`.
2. Run `database/migrate.ps1` (or the per-db script).
3. Migrations are tracked in `schema_migrations` — already-applied files are skipped.

Migrations were extracted from `nexa_backend/` for the split architecture. Pay/Go tables are **not** included.

Full ecosystem overview: [`../docs/ECOSYSTEM_ARCHITECTURE.md`](../docs/ECOSYSTEM_ARCHITECTURE.md).
