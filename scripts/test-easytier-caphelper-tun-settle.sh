#!/usr/bin/env bash
# Regression: caphelper must not treat an immediate post-chmod 0666 as settled (DSM devtmpfs race).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/packages/easytier/overlay/cross/caphelper/src/caphelper.c"
SVC="${ROOT}/packages/easytier/overlay/spk/EasyTier/src/service-setup.sh"

if ! grep -q 'TUN_MODE_STICK_USEC' "${SRC}"; then
  echo "FAIL: caphelper must define TUN_MODE_STICK_USEC for post-chmod persistence check" >&2
  exit 1
fi

fn_body="$(
  sed -n '/^static int ensure_tun_world_rw_settled/,/^}/p' "${SRC}"
)"

if ! echo "${fn_body}" | grep -q 'usleep(TUN_MODE_STICK_USEC)'; then
  echo "FAIL: ensure_tun_world_rw_settled must sleep after first 0666 before success" >&2
  exit 1
fi

stick_line="$(echo "${fn_body}" | grep -n 'usleep(TUN_MODE_STICK_USEC)' | head -1 | cut -d: -f1)"
ret_line="$(echo "${fn_body}" | grep -n 'return 0;' | tail -1 | cut -d: -f1)"
if [ -z "${stick_line}" ] || [ -z "${ret_line}" ] || [ "${stick_line}" -ge "${ret_line}" ]; then
  echo "FAIL: stick delay must precede successful return in ensure_tun_world_rw_settled" >&2
  exit 1
fi

mode_checks="$(echo "${fn_body}" | grep -c '0666' || true)"
if [ "${mode_checks}" -lt 2 ]; then
  echo "FAIL: settle must lstat 0666 at least twice (immediate and after stick delay)" >&2
  exit 1
fi

if ! grep -q 'easytier_tun_rw_settled_by_package_user' "${SVC}"; then
  echo "FAIL: service-setup must retry package-user rw probe after caphelper" >&2
  exit 1
fi

if ! grep -A20 'easytier_ensure_tun ()' "${SVC}" | grep -q 'easytier_tun_rw_settled_by_package_user'; then
  echo "FAIL: easytier_ensure_tun must call settled rw probe" >&2
  exit 1
fi

echo "OK EasyTier caphelper TUN mode stick settle (no first-immediate-0666 return)"