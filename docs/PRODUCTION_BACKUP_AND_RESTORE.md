# Production Backup And Restore — Nexa Identity + Stays

**Status (repository evidence):** logical backup + isolated restore drill + VPS systemd scheduler packaging are **IMPLEMENTED**.  
**Production VPS scheduling / real cloud bucket / production RPO-RTO:** **NOT VERIFIED** until operator evidence exists.

Related audit finding: **PROD-OPS-001 — PARTIALLY CLOSED**.

Central alerting (**PROD-OPS-003**) is **not** closed by this work.

---

## Topology (VPS)

Confirmed target architecture:

```
VPS (SSH)
 └── Docker Compose
      ├── Identity PostgreSQL  (published 127.0.0.1:5433)
      ├── Stays PostgreSQL     (published 127.0.0.1:5434)
      └── application services (backend/deploy/docker-compose.release.yml)
```

Backup job runs **on the VPS host**, connecting to published localhost ports.  
It dumps both databases, validates archives, copies off-site, then applies retention.

---

## Classification legend

| Label | Meaning |
|-------|---------|
| **IMPLEMENTED** | Code/scripts exist in this repository |
| **LOCALLY VERIFIED** | Executed successfully on a developer/CI machine |
| **VERIFIED AGAINST MINIO** | S3-compatible path exercised with local MinIO |
| **VPS VERIFIED** | Scheduler/install observed on the real VPS |
| **PRODUCTION VERIFIED** | Real cloud bucket + scheduled production execution evidenced |
| **NOT IMPLEMENTED** | Explicitly absent |

---

## 1. Architecture

```
[identity-db] --pg_dump -Fc--> BACKUP_DIR/identity_YYYY-MM-DD_HH-mm-ss.dump
[stays-db]    --pg_dump -Fc--> BACKUP_DIR/stays_YYYY-MM-DD_HH-mm-ss.dump
                                      |
                                      +--> integrity: non-empty + pg_restore --list + expected tables
                                      +--> sha256 + *.dump.manifest.json
                                      |
                                      +--> REQUIRED remote when NEXA_ENV=production
                                      |      (filesystem OR S3-compatible; fail closed)
                                      +--> remote size verify
                                      |
                                      +--> retention (after success only)
```

Scripts:

| Script | Role |
|--------|------|
| `scripts/backup-postgres.ps1` / `.sh` | Dump both DBs, verify, remote, retention, lock |
| `scripts/restore-postgres.ps1` / `.sh` | Restore into target with production safeguards |
| `scripts/restore-drill.ps1` / `.sh` | Ephemeral restore containers + timed drill |
| `scripts/run-scheduled-backup.sh` | systemd entrypoint (loads `/etc/nexa/backup.env`) |
| `scripts/install-systemd-backup.sh` | Install units to `/opt/nexa/database` |
| `scripts/uninstall-systemd-backup.sh` | Remove timer/service |
| `scripts/systemd/nexa-db-backup.{service,timer}` | Nightly 02:15 UTC timer |
| `scripts/lib/*` | Shared helpers (redaction, policy, clients) |

Custom format (`-F c`) is required.

---

## 2. Scheduling (VPS / systemd)

**Primary:** systemd timer (IMPLEMENTED). **VPS VERIFIED: NO** until installed on the host.

```bash
# On VPS as root — from a checkout of this repo
./scripts/install-systemd-backup.sh /path/to/database-repo
# Edit secrets:
sudo $EDITOR /etc/nexa/backup.env   # chmod 600
# Manual verification BEFORE enabling timer:
sudo systemctl start nexa-db-backup.service
sudo journalctl -u nexa-db-backup.service -n 200 --no-pager
ls -la /var/backups/nexa/
# Then enable timer:
sudo systemctl start nexa-db-backup.timer
sudo systemctl list-timers nexa-db-backup.timer
```

Removal:

```bash
sudo ./scripts/uninstall-systemd-backup.sh
```

Lock: `flock` on `BACKUP_LOCK_FILE` (default `/var/lock/nexa-db-backup.lock`) — overlapping jobs fail fast.  
Timeout: systemd `TimeoutStartSec=3600`.

Cron example (`scripts/examples/cron-backup.example`) is **fallback only**.

---

## 3. Retention

- Env: `BACKUP_RETENTION_DAYS` (default `30`)
- Deletes matching `identity_|stays_YYYY-MM-DD_HH-mm-ss.dump` (+ `.manifest.json`)
- **Never** deletes the newest valid dump
- **Never** deletes dumps from the current UTC calendar day
- Runs **only after** successful dump (+ remote when required)
- Does **not** purge remote object storage unless a separate ops process is added

---

## 4. Storage / remote policy

| Layer | Status |
|-------|--------|
| Local `BACKUP_DIR` | IMPLEMENTED |
| Filesystem off-host | IMPLEMENTED / LOCALLY VERIFIED (drill) |
| S3-compatible (MinIO) | IMPLEMENTED / VERIFIED AGAINST MINIO (prior drill) |
| Production cloud bucket | **NOT VERIFIED** |
| Production mandatory remote | IMPLEMENTED (`NEXA_ENV=production` or `BACKUP_REQUIRE_REMOTE=true`) |

When remote is required:

- `BACKUP_REMOTE_ENABLED=true` mandatory
- Failed remote copy ⇒ overall backup job **fails** (non-zero)
- Production `S3_ENDPOINT` must be `https://` when set
- Manifest records remote key/path + verified flag

**Do not claim** local MinIO proves a real cloud bucket.

---

## 5. Encryption & credentials

| Control | Status |
|---------|--------|
| Secrets via env (`/etc/nexa/backup.env`) | REQUIRED |
| TLS to S3 in production | REQUIRED |
| At-rest SSE | Prefer provider bucket default — not reinvented |
| Client-side dump encryption | **NOT IMPLEMENTED** |
| Log redaction | IMPLEMENTED |

---

## 6. Restore

Default target: **isolated**.  
Staging: `RESTORE_CONFIRM=YES`.  
Production: `RESTORE_CONFIRM=YES` **and** `RESTORE_ALLOW_PRODUCTION=YES`.

Restore from remote filesystem path is proven by the Linux restore drill (`restored_from: remote_filesystem`).  
Restore from production cloud object: **NOT VERIFIED**.

Stays restore validates:

- expected tables
- `ex_stays_bookings_active_overlap`
- `idx_stays_ledger_settled_guest_payment_unique`

---

## 7. Restore drill

```powershell
cd database
.\scripts\restore-drill.ps1
.\scripts\restore-drill.ps1 -WithMinio
```

```bash
bash scripts/restore-drill.sh
```

Result JSON: `backups/drill/restore-drill-result.json` with  
`BACKUP_DURATION`, `RESTORE_DURATION`, `TOTAL_DURATION`, `BACKUP_SIZE`, `REMOTE_COPY_STATUS`, `RESTORE_STATUS`, `VALIDATION_STATUS`.

---

## 8–9. RPO / RTO

| Metric | TARGET | TOOLING CAPABILITY | PRODUCTION VERIFIED |
|--------|--------|--------------------|---------------------|
| **RPO** | ≤ 24h with nightly logical backups | Nightly dump tooling exists | **NOT VERIFIED** (scheduler not evidenced on VPS) |
| **RTO** | ≤ 4h ops target for both DBs | LOCAL DRILL RTO ≈ tens of seconds | **NOT VERIFIED** |

Local / MinIO drill timings are **LOCAL DRILL RTO**, not production RTO.

---

## 10. PITR

**PITR NOT IMPLEMENTED.**

Consequence: nightly `pg_dump` provides snapshot recovery only — not arbitrary point-in-time recovery.  
Minute-level RPO requires managed Postgres PITR or WAL archiving outside this repo.

---

## 11. Production verification checklist

1. Configure `/etc/nexa/backup.env` (DB URLs, S3, `NEXA_ENV=production`).
2. Install systemd units (`install-systemd-backup.sh`).
3. Execute **manual** `systemctl start nexa-db-backup.service`.
4. Verify identity + stays dumps + manifests under `/var/backups/nexa`.
5. Verify remote objects (bucket listing / size).
6. Verify retention rules (optional age simulation).
7. Start timer; observe next OnCalendar fire (`list-timers` + journal).
8. Isolated restore **from remote** dump/object.
9. Record backup duration.
10. Record restore duration.
11. Record PRODUCTION VERIFIED RPO (age of last successful scheduled backup).
12. Record PRODUCTION VERIFIED RTO (actual restore on production-class hardware).

Until steps 3–8 are evidenced: keep **PARTIALLY CLOSED**.

---

## 12. Failure handling

Non-zero exit + structured JSON logs when:

- env missing / remote policy violated
- dump fails / empty / corrupt TOC
- expected tables missing
- remote copy or remote verify fails
- flock busy (overlap)
- restore validation fails

---

## 13. Observability

Structured logs: `backup.*`, `restore.*`, `restore_drill.*`.  
Central paging remains **PROD-OPS-003**. Recommend alerting on `nexa-db-backup.service` failure via systemd → webhook/email.

---

## 14. Acceptance checklist

- [x] Identity + Stays backup
- [x] Integrity + expected tables + sha256 manifest
- [x] Retention after success
- [x] Remote fail-closed when production
- [x] systemd timer packaging + install/uninstall
- [x] Secret redaction / dumps gitignored
- [x] Isolated restore + dual confirm
- [x] PITR explicitly NOT IMPLEMENTED
- [ ] VPS scheduled execution VERIFIED
- [ ] Production cloud bucket VERIFIED
- [ ] Production RPO/RTO VERIFIED
