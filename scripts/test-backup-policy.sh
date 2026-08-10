#!/usr/bin/env bash
# Unit tests for production remote policy helpers (no live DB).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/backup-common.sh
source "${ROOT}/scripts/lib/backup-common.sh"

failed=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=$((failed + 1)); }

# Clean env
unset NEXA_ENV BACKUP_REQUIRE_REMOTE BACKUP_REMOTE_ENABLED BACKUP_REMOTE_PROVIDER \
  BACKUP_REMOTE_PATH S3_BUCKET S3_ENDPOINT S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY || true

if remote_is_required; then fail "remote not required by default"; else pass "remote not required by default"; fi

export NEXA_ENV=production
if remote_is_required; then pass "production requires remote"; else fail "production requires remote"; fi

unset NEXA_ENV
export BACKUP_REQUIRE_REMOTE=true
if remote_is_required; then pass "BACKUP_REQUIRE_REMOTE requires remote"; else fail "flag requires remote"; fi

export NEXA_ENV=production
export BACKUP_REMOTE_ENABLED=false
set +e
out="$(assert_remote_policy_configured 2>&1)"
rc=$?
set -e
if [[ "${rc}" -ne 0 ]]; then pass "production without remote fails closed"; else fail "production without remote should fail"; fi

export BACKUP_REMOTE_ENABLED=true
export BACKUP_REMOTE_PROVIDER=s3
export S3_BUCKET=test-bucket
export S3_ACCESS_KEY_ID=ak
export S3_SECRET_ACCESS_KEY=sk
export S3_ENDPOINT=http://127.0.0.1:9000
set +e
out="$(assert_remote_policy_configured 2>&1)"
rc=$?
set -e
if [[ "${rc}" -ne 0 ]]; then pass "production http S3 endpoint rejected"; else fail "http endpoint should be rejected in production"; fi

export S3_ENDPOINT=https://s3.example.com
assert_remote_policy_configured
pass "production https S3 policy accepts"

url='postgresql://user:s3cret@127.0.0.1:5433/db'
red="$(redact_database_url "${url}")"
if [[ "${red}" != *s3cret* && "${red}" == *'***'* ]]; then pass "URL redaction"; else fail "URL redaction"; fi

if [[ "${failed}" -eq 0 ]]; then
  echo "ALL POLICY UNIT TESTS PASSED"
  exit 0
fi
echo "FAILED=${failed}"
exit 1
