# Database

SQL migrations live here — one folder per product database.

```
database/
├── docker-compose.yml     # PostgreSQL for identity + stays (dev)
├── identity/migrations/   # Nexa Identity (SSO) — PostgreSQL nexa_identity :5433
└── stays/migrations/      # Nexa Stays — PostgreSQL nexa_stays :5434
```

### Stays database (Docker DB + local backend)

```powershell
cd database\stays
.\migrate.ps1
```

See [`stays/README.md`](stays/README.md).

### All databases (Identity + Stays)

```powershell
# Example (psql) — Identity
Get-ChildItem database\identity\migrations\*.sql | Sort-Object Name | ForEach-Object {
  psql -h localhost -p 5433 -U nexa_identity -d nexa_identity -f $_.FullName
}

# Example (psql) — Stays
Get-ChildItem database\stays\migrations\*.sql | Sort-Object Name | ForEach-Object {
  psql -h localhost -p 5434 -U nexa_stays -d nexa_stays -f $_.FullName
}
```

Migrations were extracted from `nexa_backend/` for the split architecture. Pay/Go tables are **not** included.

Full ecosystem overview: [`../docs/ECOSYSTEM_ARCHITECTURE.md`](../docs/ECOSYSTEM_ARCHITECTURE.md).
