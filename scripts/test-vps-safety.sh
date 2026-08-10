#!/usr/bin/env bash
# B2/B3/B4/B5/B6 local safety tests for database deploy helpers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# B2: installer source must NOT use rsync --delete on a real command line
if grep -nE '^[[:space:]]*rsync[[:space:]].*--delete' "$ROOT/scripts/install-systemd-backup.sh"; then
  echo "FAIL: install-systemd-backup.sh still contains rsync --delete" >&2
  fail=$((fail + 1))
else
  echo "PASS: no rsync --delete command in install-systemd-backup.sh"
fi

# B3: --stage required
if bash "$ROOT/scripts/install-systemd-backup.sh" >/dev/null 2>&1; then
  echo "FAIL: install without --stage should fail" >&2
  fail=$((fail + 1))
else
  echo "PASS: install without --stage fails"
fi

# Simulate B2 rsync without --delete preserves dest-only dumps
SRC="$TMP/src" DEST="$TMP/dest"
mkdir -p "$SRC/scripts" "$DEST/scripts" "$DEST/backups"
echo 'tool' >"$SRC/scripts/backup-postgres.sh"
echo 'dump' >"$DEST/backups/keep.dump"
echo 'extra' >"$DEST/scripts/host-only-note.txt"
rsync -a "$SRC/scripts/" "$DEST/scripts/"
if [[ -f "$DEST/backups/keep.dump" && -f "$DEST/scripts/host-only-note.txt" ]]; then
  echo "PASS: rsync without --delete preserves dest-only files"
else
  echo "FAIL: dest-only files not preserved in simulation" >&2
  fail=$((fail + 1))
fi

# B3 templates exist and production differs from dogfood
for s in dogfood staging production; do
  f="$ROOT/scripts/env/backup.${s}.env.example"
  if [[ -f "$f" ]]; then echo "PASS: template $s"; else echo "FAIL: missing $f" >&2; fail=$((fail + 1)); fi
done
if grep -q 'BACKUP_REQUIRE_REMOTE=true' "$ROOT/scripts/env/backup.production.env.example" && \
   grep -q 'BACKUP_REQUIRE_REMOTE=false' "$ROOT/scripts/env/backup.dogfood.env.example"; then
  echo "PASS: production vs dogfood remote policy templates"
else
  echo "FAIL: stage templates policy mismatch" >&2
  fail=$((fail + 1))
fi

# B4: --enable-timer string present as opt-in; default message documents NOT enabled
if grep -q 'ENABLE_TIMER' "$ROOT/scripts/install-systemd-backup.sh" && \
   grep -q 'NOT enabled' "$ROOT/scripts/install-systemd-backup.sh"; then
  echo "PASS: timer enable is opt-in"
else
  echo "FAIL: timer opt-in messaging missing" >&2
  fail=$((fail + 1))
fi

# B5: ensure script exists and documents non-delete
if grep -q 'volume create' "$ROOT/scripts/ensure-vps-volumes.sh" && \
   grep -qiE 'non-destructive|does not delete|no deletes' "$ROOT/scripts/ensure-vps-volumes.sh"; then
  echo "PASS: ensure-vps-volumes non-destructive"
else
  echo "FAIL: ensure-vps-volumes guards missing" >&2
  fail=$((fail + 1))
fi

if grep -q 'external: true' "$ROOT/docker-compose.yml" && \
   grep -q 'ensure-vps-volumes' "$ROOT/docker-compose.yml"; then
  echo "PASS: compose documents ensure-vps-volumes"
else
  echo "FAIL: compose missing volume bootstrap note" >&2
  fail=$((fail + 1))
fi

# B6 assert-vps-db-env
cat >"$TMP/.env.db" <<'EOF'
IDENTITY_DB_PASSWORD=nexa_identity_dev
STAYS_DB_PASSWORD=nexa_stays_dev
EOF
chmod 600 "$TMP/.env.db"
if NEXA_ENV=dogfood bash "$ROOT/scripts/assert-vps-db-env.sh" "$TMP/.env.db"; then
  echo "FAIL: assert should reject *_dev" >&2
  fail=$((fail + 1))
else
  echo "PASS: assert rejects *_dev for dogfood"
fi

cat >"$TMP/.env.db" <<'EOF'
IDENTITY_DB_PASSWORD=identity-db-pass-NOT-dev-99
STAYS_DB_PASSWORD=stays-db-pass-NOT-dev-99
EOF
chmod 600 "$TMP/.env.db"
if NEXA_ENV=dogfood bash "$ROOT/scripts/assert-vps-db-env.sh" "$TMP/.env.db"; then
  echo "PASS: assert accepts strong passwords"
else
  echo "FAIL: assert rejected strong passwords" >&2
  fail=$((fail + 1))
fi

# validate-backup-env placeholders
cp "$ROOT/scripts/env/backup.dogfood.env.example" "$TMP/backup.env"
chmod 600 "$TMP/backup.env"
if bash "$ROOT/scripts/validate-backup-env.sh" "$TMP/backup.env"; then
  echo "FAIL: validate should reject CHANGE_ME" >&2
  fail=$((fail + 1))
else
  echo "PASS: validate-backup-env rejects placeholders"
fi

echo "=== database VPS safety tests: fail=$fail ==="
[[ "$fail" -eq 0 ]]
