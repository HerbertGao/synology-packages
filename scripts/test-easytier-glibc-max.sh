#!/usr/bin/env bash
# Fail if a binary requires GLIBC_x.y with (x,y) > (2,36).
# Usage: test-easytier-glibc-max.sh <path> [<path>...]
set -euo pipefail

MAX_MAJOR=2
MAX_MINOR=36

check_one() {
  local bin="$1"
  local vers v major minor
  if [ ! -f "${bin}" ]; then
    echo "FAIL: missing binary ${bin}" >&2
    return 1
  fi
  if ! command -v readelf >/dev/null 2>&1 && ! command -v objdump >/dev/null 2>&1; then
    echo "SKIP: readelf/objdump unavailable for ${bin}"
    return 0
  fi
  if command -v readelf >/dev/null 2>&1; then
    vers="$(readelf -V "${bin}" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -u || true)"
  else
    vers="$(objdump -T "${bin}" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -u || true)"
  fi
  if [ -z "${vers}" ]; then
    echo "OK ${bin}: no dynamic GLIBC symbols (likely static)"
    return 0
  fi
  while IFS= read -r v; do
    [ -z "${v}" ] && continue
    major="${v#GLIBC_}"
    minor="${major#*.}"
    major="${major%%.*}"
    if [ "${major}" -gt "${MAX_MAJOR}" ] || { [ "${major}" -eq "${MAX_MAJOR}" ] && [ "${minor}" -gt "${MAX_MINOR}" ]; }; then
      echo "FAIL: ${bin} requires GLIBC newer than ${MAX_MAJOR}.${MAX_MINOR}: ${v}" >&2
      return 1
    fi
  done <<<"${vers}"
  echo "OK ${bin}: GLIBC within <= ${MAX_MAJOR}.${MAX_MINOR} (${vers//$'\n'/ })"
}

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <binary>..." >&2
  exit 1
fi

for b in "$@"; do
  check_one "${b}"
done