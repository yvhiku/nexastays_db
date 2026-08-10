#!/usr/bin/env bash
# Shared logging + helpers for Nexa backup scripts. Never log secrets.
set -euo pipefail

log() {
  local level="$1"; shift
  local msg="$1"; shift || true
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
