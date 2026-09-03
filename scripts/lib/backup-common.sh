#!/usr/bin/env bash
# Shared helpers for Nexa production backup tooling. Never log secrets.
set -euo pipefail

json_escape() {
  printf '%s' "$1" | sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\n/\\n/g;s/\r/\\r/g'
}

log() {
  local level="$1" msg="$2"
  shift 2 || true
  printf '{"ts":"%s","level":"%s","msg":"%s","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(json_escape "${level}")" \
    "$(json_escape "${msg}")" \
    "$(json_escape "$*")"
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    log FAIL env.missing "missing ${name}"
    exit 1
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log FAIL tool.missing "missing $1"
    exit 1
  }
}

redact_database_url() {
  printf '%s\n' "$1" | sed -E 's#(postgres(ql)?://[^:]+:)[^@]+#\1***#'
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
  else
    log FAIL tool.missing "missing sha256sum/shasum"
    exit 1
  fi
}

secure_remove() {
  local file="$1"
  [[ -e "${file}" ]] || return 0
  if command -v shred >/dev/null 2>&1; then
    shred -u -z "${file}" 2>/dev/null || rm -f -- "${file}"
  else
    rm -f -- "${file}"
  fi
}

remote_is_required() {
  [[ "${NEXA_ENV:-}" == production ]] || [[ "${BACKUP_REQUIRE_REMOTE:-}" == true ]]
}

assert_remote_policy_configured() {
  remote_is_required || return 0
  [[ "${BACKUP_REMOTE_ENABLED:-false}" == true ]] || {
    log FAIL backup.policy "production requires BACKUP_REMOTE_ENABLED=true"
    exit 1
  }
  [[ "${BACKUP_REMOTE_PROVIDER:-}" == r2 ]] || {
    log FAIL backup.policy "production provider must be r2"
    exit 1
  }
  require_env R2_ACCOUNT_ID
  require_env R2_ACCESS_KEY_ID
  require_env R2_SECRET_ACCESS_KEY
  require_env R2_BUCKET
  require_env R2_ENDPOINT
  require_env AGE_RECIPIENT
  [[ "${R2_ENDPOINT}" == https://* ]] || {
    log FAIL backup.policy "R2 endpoint must use HTTPS"
    exit 1
  }
  [[ "${R2_LIFECYCLE_DAYS:-}" == 30 && "${R2_LIFECYCLE_VERIFIED:-false}" == true ]] || {
    log FAIL backup.policy "verified 30-day R2 lifecycle is required"
    exit 1
  }
}

configure_rclone_r2_env() {
  export RCLONE_CONFIG_NEXAR2_TYPE=s3
  export RCLONE_CONFIG_NEXAR2_PROVIDER=Cloudflare
  export RCLONE_CONFIG_NEXAR2_ENV_AUTH=false
  export RCLONE_CONFIG_NEXAR2_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
  export RCLONE_CONFIG_NEXAR2_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
  export RCLONE_CONFIG_NEXAR2_ENDPOINT="${R2_ENDPOINT}"
  export RCLONE_CONFIG_NEXAR2_REGION="${R2_REGION:-auto}"
  export RCLONE_CONFIG_NEXAR2_NO_CHECK_BUCKET=true
}

r2_uri() {
  local key="$1"
  printf 'nexar2:%s/%s' "${R2_BUCKET}" "${key}"
}

r2_upload() {
  local source="$1" key="$2"
  configure_rclone_r2_env
  rclone copyto "${source}" "$(r2_uri "${key}")" \
    --checkers 2 --transfers 1 --retries 3 --low-level-retries 5 --log-level ERROR
}

r2_download() {
  local key="$1" target="$2"
  configure_rclone_r2_env
  rclone copyto "$(r2_uri "${key}")" "${target}" \
    --checkers 2 --transfers 1 --retries 3 --low-level-retries 5 --log-level ERROR
}

r2_remote_size() {
  local key="$1"
  configure_rclone_r2_env
  rclone lsl "$(r2_uri "${key}")" --log-level ERROR | awk 'NR == 1 {print $1}'
}

r2_upload_and_verify() {
  local source="$1" key="$2" verify_dir="$3"
  local local_size local_sha remote_size verify_file
  local_size="$(wc -c < "${source}" | tr -d ' ')"
  local_sha="$(sha256_file "${source}")"
  r2_upload "${source}" "${key}" || return 1
  remote_size="$(r2_remote_size "${key}")" || return 1
  [[ "${remote_size}" == "${local_size}" ]] || {
    log FAIL backup.remote.verify "object=${key} size mismatch"
    return 1
  }
  verify_file="${verify_dir}/remote.$(basename "${source}")"
  r2_download "${key}" "${verify_file}" || return 1
  [[ "$(sha256_file "${verify_file}")" == "${local_sha}" ]] || {
    secure_remove "${verify_file}"
    log FAIL backup.remote.verify "object=${key} checksum mismatch"
    return 1
  }
  secure_remove "${verify_file}"
  log SUCCESS backup.remote.ok "object=${key} bytes=${local_size} checksum=verified"
}
