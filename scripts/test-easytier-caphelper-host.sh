#!/usr/bin/env bash
# Host unit checks for caphelper (Linux with gcc; optional in CI without root caps).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/packages/easytier/overlay/cross/caphelper/src/caphelper.c"
WORK="${ROOT}/.build/easytier-caphelper-test"
BIN="${WORK}/caphelper"

if ! command -v gcc >/dev/null 2>&1; then
  echo "SKIP: gcc not installed; caphelper host test omitted"
  exit 0
fi

for sym in setgroups setresgid chown_path_root_root ensure_tun_world_rw_settled TUN_MODE_STICK_USEC; do
  if ! grep -q "${sym}" "${SRC}"; then
    echo "FAIL: caphelper.c must implement ${sym} (4550 egid / TUN root:root)" >&2
    exit 1
  fi
done

rm -rf "${WORK}"
mkdir -p "${WORK}"

gcc -Wall -Wextra -O2 -static \
  -DEASYTIER_CORE_SHA256=\"0000000000000000000000000000000000000000000000000000000000000000\" \
  -o "${BIN}" "${SRC}"

# Reject extra arguments
out="$("${BIN}" x 2>&1 || true)"
if ! echo "${out}" | grep -q 'RESULT=fail WHAT=argc'; then
  echo "FAIL: expected argc rejection message, got: ${out}" >&2
  exit 1
fi

# Non-root without setuid should fail euid check
out="$("${BIN}" 2>&1 || true)"
if ! echo "${out}" | grep -q 'RESULT=fail WHAT=euid_not_root'; then
  echo "FAIL: non-root should fail euid_not_root, got: ${out}" >&2
  exit 1
fi

SELFTEST_BIN="${WORK}/caphelper-selftest"
gcc -Wall -Wextra -Wno-unused-function -O2 \
  -DEASYTIER_CAPHELPER_SELFTEST=1 \
  -o "${SELFTEST_BIN}" "${SRC}"
if ! "${SELFTEST_BIN}"; then
  echo "FAIL: caphelper /proc/self/exe stat selftest" >&2
  exit 1
fi

if [ "$(id -u)" -eq 0 ] && [ -r /lib/modules/tun.ko ]; then
  echo "Note: full caphelper TUN+ caps path needs DSM package layout; not exercised here"
else
  echo "SKIP: caphelper TUN kernel steps require root and /lib/modules/tun.ko (DSM prestart)"
fi

echo "OK EasyTier caphelper host checks (argc, non-root, proc self exe stat)"