# Nexa Stays production backup and restore

This runbook covers the Phase 3 Group 1 logical backups for Identity and Stays PostgreSQL 16. It does not authorize database privilege, application, Docker persistence, firewall, proxy, SSH, DNS, or certificate changes.

## Recovery design

```text
Identity + Stays PostgreSQL
  -> pg_dump custom archives + roles-only metadata
  -> age encryption on the VPS
  -> SHA-256 manifests
  -> dedicated Cloudflare R2 bucket
  -> download + decrypt with an off-server key
  -> isolated PostgreSQL 16 containers (no host ports)
```

Production fails closed unless R2 is HTTPS, remote upload is mandatory, and a verified 30-day R2 lifecycle rule is recorded. Each upload is checked by remote size and by downloading the encrypted object and comparing SHA-256. Plaintext staging files are removed on success and failure. Local files are encrypted only and retained for 30 days.

## One-time prerequisites

1. Enable R2 in the Cloudflare dashboard.
2. Create a dedicated private bucket for Nexa production database backups.
3. Add a bucket lifecycle rule that deletes objects after 30 days.
4. Create an Object Read & Write R2 API token restricted to that bucket. Lifecycle administration should use a separate administrator credential and that credential must not be stored on the VPS.
5. Generate an age key on an operator-controlled machine. Store the private key in an offline recovery location and retain only its `age1...` public recipient on the VPS.
6. Prepare a working SMTP account and an HTTPS webhook destination.

Never paste the R2 secret, SMTP password, webhook URL/token, database credentials, or age private key into chat, Git, application `.env` files, or shell history.

## Install and configure

Ubuntu packages required by the host scripts:

```bash
sudo apt-get update
sudo apt-get install --no-install-recommends postgresql-client-16 age rclone
```

Install the repository scripts and units, but do not enable the timer yet:

```bash
sudo bash scripts/install-systemd-backup.sh --stage production /opt/nexa/nexastays_db
sudo bash /opt/nexa/backup-tools/scripts/configure-production-backup.sh
sudo bash /opt/nexa/backup-tools/scripts/validate-backup-env.sh
```

The interactive configurator reads the two existing database passwords from `/opt/nexa/nexastays_db/.env.db`, writes `/etc/nexa/backup.env` as `root:root` mode `0600`, and does not echo secret input.

The installer makes `/opt/nexa/backup-tools` and its deployed scripts root-controlled because the backup unit executes them as root. Continue normal application/database Git work in `/opt/nexa/nexastays_db`. The legacy `/opt/nexa/database` symlink is not used.

## Required validation order

1. Test both alert channels without dumping data:

   ```bash
   sudo bash -c 'set -a; source /etc/nexa/backup.env; set +a; /opt/nexa/backup-tools/scripts/backup-alert.sh success all configuration-test test'
   sudo bash -c 'set -a; source /etc/nexa/backup.env; set +a; /opt/nexa/backup-tools/scripts/backup-alert.sh failure all configuration-test safe-failure-path-test'
   ```

2. Run one real backup and inspect redacted logs:

   ```bash
   sudo systemctl start nexa-db-backup.service
   sudo systemctl --no-pager --full status nexa-db-backup.service
   sudo journalctl -u nexa-db-backup.service -n 200 --no-pager
   ```

3. Record the backup set identifier from `backup.completed`. Supply the recovery key temporarily from operator-controlled storage, run the isolated drill, then remove the temporary VPS copy:

   ```bash
   sudo /opt/nexa/backup-tools/scripts/restore-r2-drill.sh \
     --backup-set YYYY-MM-DD_HH-MM-SS_hostname \
     --age-key-file /run/nexa-recovery/age-key.txt
   sudo rm -f /run/nexa-recovery/age-key.txt
   ```

   The drill downloads from R2, verifies encrypted checksums, decrypts, restores into disposable `postgres:16-alpine` containers on an internal Docker network with no host port mappings, compares representative row counts and extension counts, checks normal queries, verifies production container/volume identity is unchanged, and cleans up.

4. Only after backup, alerts, and restore all pass, enable the daily 02:15 UTC timer:

   ```bash
   sudo systemctl enable --now nexa-db-backup.timer
   sudo systemctl list-timers nexa-db-backup.timer
   ```

## Recovery notes

The encrypted roles-only artifacts are validated in the drill but deliberately not applied. During a disaster recovery, review role SQL before applying it to a new cluster. The logical database archives are restored with `--no-owner --no-acl`; application roles and grants must be reconciled deliberately in the later recovery procedure.

This is snapshot recovery with a target RPO of 24 hours. PostgreSQL WAL archiving/PITR is not implemented by Group 1.

## Failure and rollback

Any dump, encryption, R2 upload, remote-size/checksum verification, lifecycle-policy gate, or alert failure makes the service fail. The wrapper attempts both email and webhook notification with redacted status fields. Logs are in journald and `/var/log/nexa/nexa-db-backup.log`.

To disable scheduling without deleting backups:

```bash
sudo systemctl disable --now nexa-db-backup.timer
```

Do not delete remote backups or the off-server age private key as part of rollback.
