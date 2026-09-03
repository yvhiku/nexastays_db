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
  BACKUP_REMOTE_PATH R2_ACCOUNT_ID R2_BUCKET R2_ENDPOINT R2_ACCESS_KEY_ID \
  R2_SECRET_ACCESS_KEY R2_REGION R2_LIFECYCLE_DAYS R2_LIFECYCLE_VERIFIED AGE_RECIPIENT || true

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
export BACKUP_REMOTE_PROVIDER=r2
export R2_ACCOUNT_ID=test-account
export R2_BUCKET=test-bucket
export R2_ACCESS_KEY_ID=ak
export R2_SECRET_ACCESS_KEY=sk
export R2_ENDPOINT=http://127.0.0.1:9000
export R2_REGION=auto
export R2_LIFECYCLE_DAYS=30
export R2_LIFECYCLE_VERIFIED=true
export AGE_RECIPIENT=age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqd3z0m
set +e
out="$(assert_remote_policy_configured 2>&1)"
rc=$?
set -e
if [[ "${rc}" -ne 0 ]]; then pass "production HTTP R2 endpoint rejected"; else fail "HTTP endpoint should be rejected in production"; fi

export R2_ENDPOINT=https://test-account.r2.cloudflarestorage.com
assert_remote_policy_configured
pass "production HTTPS R2 policy accepts"

export R2_LIFECYCLE_VERIFIED=false
set +e
out="$(assert_remote_policy_configured 2>&1)"
rc=$?
set -e
if [[ "${rc}" -ne 0 ]]; then pass "unverified lifecycle fails closed"; else fail "unverified lifecycle should fail"; fi
export R2_LIFECYCLE_VERIFIED=true

url='postgresql://user:s3cret@127.0.0.1:5433/db'
red="$(redact_database_url "${url}")"
if [[ "${red}" != *s3cret* && "${red}" == *'***'* ]]; then pass "URL redaction"; else fail "URL redaction"; fi

if [[ "${failed}" -eq 0 ]]; then
  echo "ALL POLICY UNIT TESTS PASSED"
  exit 0
fi
echo "FAILED=${failed}"
exit 1
