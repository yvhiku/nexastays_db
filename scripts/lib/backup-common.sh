#!/usr/bin/env bash
# Shared logging + helpers for Nexa backup scripts. Never log secrets.
set -euo pipefail

log() {
  local level="$1"; shift
  local msg="$1"; shift || true
  # Detail must never contain passwords, DATABASE_URL secrets, or AWS keys.
  printf '{"ts":"%s","level":"%s","msg":"%s","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${level}" "${msg}" "$*"
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
    log FAIL tool.missing "missing ${1}"
    exit 1
  }
}

redact_database_url() {
  echo "${1}" | sed -E 's#(postgres(ql)?://[^:]+:)[^@]+#\1***#'
}

sha256_file() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${f}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${f}" | awk '{print $1}'
  else
    log FAIL tool.missing "missing sha256sum/shasum"
    exit 1
  fi
}

# Production (NEXA_ENV=production) or explicit BACKUP_REQUIRE_REMOTE=true
# requires a successful off-site/remote copy.
remote_is_required() {
  [[ "${NEXA_ENV:-}" == "production" ]] || [[ "${BACKUP_REQUIRE_REMOTE:-}" == "true" ]]
}

assert_remote_policy_configured() {
  if ! remote_is_required; then
    return 0
  fi
  if [[ "${BACKUP_REMOTE_ENABLED:-false}" != "true" ]]; then
    log FAIL backup.policy \
      "NEXA_ENV=production (or BACKUP_REQUIRE_REMOTE=true) requires BACKUP_REMOTE_ENABLED=true"
    exit 1
  fi
  local provider="${BACKUP_REMOTE_PROVIDER:-filesystem}"
  case "${provider}" in
    filesystem)
      require_env BACKUP_REMOTE_PATH
      ;;
    s3)
      require_env S3_BUCKET
      require_env S3_ACCESS_KEY_ID
      require_env S3_SECRET_ACCESS_KEY
      if [[ "${NEXA_ENV:-}" == "production" ]]; then
        local ep="${S3_ENDPOINT:-}"
        if [[ -n "${ep}" && "${ep}" != https://* ]]; then
          log FAIL backup.policy "production S3_ENDPOINT must use https://"
          exit 1
        fi
        # AWS default endpoints are HTTPS; custom endpoint must be set https.
        if [[ -z "${ep}" ]]; then
          log INFO backup.policy "S3_ENDPOINT unset — assuming AWS HTTPS regional endpoint"
        fi
      fi
      ;;
    *)
      log FAIL backup.policy "unsupported BACKUP_REMOTE_PROVIDER=${provider}"
      exit 1
      ;;
  esac
}

write_backup_manifest() {
  local key="$1"
  local file_path="$2"
  local bytes="$3"
  local sha="$4"
  local remote_json="$5" # already JSON object or null
  local manifest="${file_path}.manifest.json"
  cat > "${manifest}" <<EOF
{"database":"${key}","file":"$(basename "${file_path}")","bytes":${bytes},"sha256":"${sha}","timestamp_utc":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","remote":${remote_json}}
EOF
  log INFO backup.manifest "database=${key} path=$(basename "${manifest}")"
}

verify_remote_filesystem() {
  local src="$1"
  local dest="$2"
  [[ -s "${dest}" ]] || { log FAIL backup.remote.verify "missing remote file"; return 1; }
  local sb db
  sb="$(wc -c < "${src}" | tr -d ' ')"
  db="$(wc -c < "${dest}" | tr -d ' ')"
  [[ "${sb}" == "${db}" ]] || {
    log FAIL backup.remote.verify "size mismatch local=${sb} remote=${db}"
    return 1
  }
}

verify_remote_s3() {
  local src="$1"
  local bucket="$2"
  local key_path="$3"
  need_cmd aws
  local args=(s3api head-object --bucket "${bucket}" --key "${key_path}")
  if [[ -n "${S3_ENDPOINT:-}" ]]; then
    args+=(--endpoint-url "${S3_ENDPOINT}")
  fi
  local out
  out="$(AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID:-}" \
    AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY:-}" \
    AWS_DEFAULT_REGION="${S3_REGION:-us-east-1}" \
    aws "${args[@]}")"
  local remote_bytes
  remote_bytes="$(echo "${out}" | sed -n 's/.*"ContentLength"[ ]*:[ ]*\([0-9]*\).*/\1/p' | head -n1)"
  local local_bytes
  local_bytes="$(wc -c < "${src}" | tr -d ' ')"
  if [[ -z "${remote_bytes}" || "${remote_bytes}" != "${local_bytes}" ]]; then
    log FAIL backup.remote.verify "s3 size mismatch local=${local_bytes} remote=${remote_bytes:-unknown}"
    return 1
  fi
}
