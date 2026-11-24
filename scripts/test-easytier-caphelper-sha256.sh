#!/usr/bin/env bash
# Host regression: caphelper SHA-256 must match sha256sum/hashlib (full FIPS 180-4 K table).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/packages/easytier/overlay/cross/caphelper/src/caphelper.c"
WORK="${ROOT}/.build/easytier-caphelper-sha256"
BIN="${WORK}/caphelper-sha256-selftest"
FIXTURE="${WORK}/fixture.bin"

if ! command -v gcc >/dev/null 2>&1; then
  echo "SKIP: gcc not installed; caphelper SHA-256 test omitted"
  exit 0
fi

if ! command -v sha256sum >/dev/null 2>&1; then
  echo "SKIP: sha256sum not installed; caphelper SHA-256 test omitted"
  exit 0
fi

k_count="$(sed -n '/static const uint32_t k256\[64\]/,/};/p' "${SRC}" | grep -oE '0x[0-9a-fA-F]{8}' | wc -l)"
k_count="${k_count// /}"
if [ "${k_count}" -ne 64 ]; then
  echo "FAIL: k256 initializer must list 64 FIPS 180-4 constants (found ${k_count})" >&2
  exit 1
fi

rm -rf "${WORK}"
mkdir -p "${WORK}"

gcc -Wall -Wextra -O2 -Wno-unused-function \
  -DEASYTIER_CAPHELPER_SHA256_SELFTEST=1 \
  -o "${BIN}" "${SRC}"

if ! "${BIN}"; then
  echo "FAIL: caphelper SHA-256 empty and abc NIST vectors" >&2
  exit 1
fi

# ~3 MiB deterministic payload (exercises rounds > 48 where truncated K broke hashes).
python3 -c "
import sys
n = 3 * 1024 * 1024
sys.stdout.buffer.write(bytes((i * 131 + 17) & 0xFF for i in range(n)))
" >"${FIXTURE}"

fixture_hex="$(sha256sum "${FIXTURE}" | awk '{print $1}')"
if ! printf '%s\n' "${fixture_hex}" | "${BIN}" "${FIXTURE}"; then
  echo "FAIL: caphelper SHA-256 large fixture vs sha256sum" >&2
  exit 1
fi

# Cross-check fixture with hashlib when Python is available.
if command -v python3 >/dev/null 2>&1; then
  py_hex="$(python3 -c "import hashlib; print(hashlib.sha256(open('${FIXTURE}', 'rb').read()).hexdigest())")"
  if [ "${py_hex}" != "${fixture_hex}" ]; then
    echo "FAIL: sha256sum vs hashlib on fixture" >&2
    exit 1
  fi
fi

echo "OK EasyTier caphelper SHA-256 (64-word K table, NIST empty/abc, ~3MiB fixture)"