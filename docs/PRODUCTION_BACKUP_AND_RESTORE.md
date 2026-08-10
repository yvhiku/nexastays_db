# Production Backup And Restore — Nexa Identity + Stays

**Status (repository evidence):** logical backup + isolated restore drill are **IMPLEMENTED**.  
**Production scheduling, managed PITR, and cloud off-site delivery:** see classification below — do not treat this document as proof that a hosted production cluster is already backed up.

Related audit finding: **PROD-OPS-001**.

Central alerting (**PROD-OPS-003**) is **not** closed by this work.

---

## 1. Architecture

```
[identity-db] --pg_dump -Fc--> BACKUP_DIR/identity_YYYY-MM-DD_HH-mm-ss.dump
[stays-db]    --pg_dump -Fc--> BACKUP_DIR/stays_YYYY-MM-DD_HH-mm-ss.dump
                                      |
                                      +--> integrity: pg_restore --list + expected tables
                                      |
                                      +--> optional remote: filesystem OR S3-compatible
                                      |
                                      +--> retention cleanup (local only unless separately configured)
```

Scripts (Windows-first + Linux/CI):

| Script | Role |
|--------|------|
| `scripts/backup-postgres.ps1` / `.sh` | Dump both DBs, verify archive, retention, optional remote |
| `scripts/restore-postgres.ps1` / `.sh` | Restore into target with production safeguards |
| `scripts/restore-drill.ps1` / `.sh` | Ephemeral restore containers + timed drill |
| `scripts/lib/NexaBackup.Common.ps1` | Shared helpers (redaction, retention, clients) |
| `docker-compose.backup.yml` | Isolated restore Postgres (+ optional MinIO) |

Custom format (`-F c`) is required. Plain SQL dumps are not the primary format.

---

## 2. Backup frequency

| Environment | Frequency | Status |
|-------------|-----------|--------|
| Local / CI drill | On-demand via scripts | **VERIFIED** (when drill is run) |
| Production host | Nightly recommended (`scripts/examples/cron-backup.example`) | **CONFIGURED EXAMPLE — scheduling NOT VERIFIED** until installed on a host |
| Kubernetes | Example CronJob YAML | **NOT VERIFIED** |

---

## 3. Retention

- Env: `BACKUP_RETENTION_DAYS` (default `30`)
- Deletes only files matching `identity_|stays_YYYY-MM-DD_HH-mm-ss.dump`
- **Never** deletes the newest valid dump
- **Never** deletes dumps from the current UTC calendar day
- Does **not** remotely purge object storage unless a separate ops process is added

---

## 4. Storage

| Layer | Location | Notes |
|-------|----------|-------|
| Primary local | `BACKUP_DIR` **outside** app web roots | Permissions tightened best-effort (`chmod 700` / Windows ACL) |
| Off-host filesystem | `BACKUP_REMOTE_PROVIDER=filesystem` | Copy after integrity check |
| S3-compatible | MinIO / AWS / R2 via AWS CLI (or dockerized CLI) | Credentials via env only |

Docker named volumes (`identity_pg_data`, `stays_pg_data`) are **not** backups.

---

## 5. Encryption

| Control | Status |
|---------|--------|
| Secrets via env / secret manager | **REQUIRED** |
| Encrypted transport to S3/MinIO (TLS) | **REQUIRED** in production (`https://` endpoint) |
| At-rest object encryption | Prefer provider SSE (S3 SSE / bucket default) — **document for production**; not reinvented in-script |
| Client-side dump encryption | **NOT IMPLEMENTED** (avoid ad-hoc key management). Prefer encrypted volume / SSE |
| Restrictive backup filesystem ACLs | Best-effort in scripts |

Backups contain PII and financial ledger metadata — treat like production data.

---

## 6. Credentials

See `.env.backup.example`. Never commit `.env.backup` or dump files (gitignored).

Scripts redact passwords from logs (`***`). Do not pass `DATABASE_URL` to public HTTP APIs.

---

## 7. Restore procedure

1. Identify latest valid `*.dump` (local or remote).
2. Start **isolated** restore targets (`docker compose -f docker-compose.backup.yml up -d identity-restore-db stays-restore-db`) **or** a dedicated restore instance.
3. Run:

```powershell
.\scripts\restore-postgres.ps1 `
  -DumpFile .\backups\drill\identity_....dump `
  -DatabaseKey identity `
  -Target isolated `
  -TargetDatabaseUrl 'postgresql://nexa_identity:nexa_identity_restore@127.0.0.1:55433/nexa_identity_restore'
```

4. For staging: `RESTORE_CONFIRM=YES` and `-Target staging`.
5. For production: `RESTORE_CONFIRM=YES` **and** `RESTORE_ALLOW_PRODUCTION=YES`, with explicit authorization recorded in the incident ticket.

Default target is **isolated**. Production is rejected without double confirmation.

---

## 8. Restore drill

```powershell
cd database
.\scripts\restore-drill.ps1              # filesystem off-host
.\scripts\restore-drill.ps1 -WithMinio   # MinIO S3-compatible off-host
```

Result JSON: `backups/drill/restore-drill-result.json` (timings + sizes).

---

## 9–10. RPO / RTO

| Metric | Target | Verified (this repo) |
|--------|--------|----------------------|
| **RPO** | ≤ 24h for nightly logical backups | **VERIFIED RPO = last successful drill/backup age only in environments where scheduling runs**. Local drill proves tooling RPO ≈ seconds between dump and restore for that snapshot — **not** production lag. |
| **RTO** | Target ≤ 4h for logical restore of both DBs (ops judgment) | **VERIFIED** local drill (2026-08-10, Docker tooling): total ≈ **24.1s** (`total_duration_ms` 24055) with MinIO off-host; restore phase ≈ **16.1s**; filesystem-only drill total ≈ **23.9s**. Production RTO depends on host/network and is **NOT VERIFIED** here. |

**PITR:** **NOT IMPLEMENTED** in this repository. Nightly/`pg_dump` is **not** point-in-time recovery. Production managed PostgreSQL (or WAL archiving) is required before claiming minute-level RPO.

---

## 11. Failure handling

Scripts exit non-zero and emit JSON/log lines when:

- env missing
- DB unreachable / bad credentials (dump fails)
- client tools missing (Docker fallback attempted)
- empty/corrupt archive
- remote copy fails
- restore validation fails

Retention never wipes the newest dump on failure of a new backup (new dump is only published after integrity checks).

---

## 12. Incident procedure (disaster)

1. Freeze writes if corruption/ransom risk.
2. Identify latest valid backup (local + remote).
3. Restore into isolated environment first; validate schema/constraints.
4. Validate application connectivity against restore targets.
5. Production restore only with dual confirmation env flags + authorization.
6. Record incident, actual RTO/RPO, and owner.

**Restore owner (role):** Platform/SRE on-call (assign named human outside this repo).

---

## 13. Operational checklist

### Daily
- [ ] Last backup succeeded (log / job status)
- [ ] Remote copy succeeded if enabled
- [ ] Latest dumps present for identity + stays

### Weekly
- [ ] Backup age < retention expectation
- [ ] Remote listing / filesystem path inspected
- [ ] Disk usage for `BACKUP_DIR`

### Monthly
- [ ] Run `restore-drill` (both databases)
- [ ] Record duration into ticket
- [ ] Credential rotation if policy requires

---

## 14. Observability

Scripts emit structured JSON logs (`backup.started`, `backup.completed`, `backup.failed`, `restore.*`, `restore_drill.*`).

**Central alerting remains PROD-OPS-003** — not closed here. Wire job failure alerts externally.

---

## 15. Verification checklist (P0 acceptance)

- [x] Identity backup command
- [x] Stays backup command
- [x] Archive integrity (`pg_restore --list` + expected tables)
- [x] Retention rules
- [x] Off-host path (filesystem; MinIO optional)
- [x] Env-based credentials
- [x] Secret redaction in logs
- [x] Isolated restore default
- [x] Production restore dual confirm
- [x] Restore verification queries / Stays constraints
- [x] Dumps gitignored
- [x] CI workflow for drill
- [x] Runbook (this document)
- [x] RPO/RTO target vs verified
- [x] PITR explicitly NOT IMPLEMENTED
- [x] Scheduling example only / NOT VERIFIED in production
