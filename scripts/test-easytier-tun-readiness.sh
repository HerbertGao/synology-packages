#!/usr/bin/env bash
# Offline TUN readiness checks for EasyTier (does not run on DSM).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/easytier-tun-sim"
SVC="${ROOT}/packages/easytier/overlay/spk/EasyTier/src/service-setup.sh"

rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/dev/net"
: >"${WORK}/var/caphelper.out"

export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
export EASYTIER_TUN_DEV="${WORK}/dev/net/tun"
export CP=cp

# shellcheck disable=SC1090,SC1091
. "${SVC}"

easytier_host_can_mknod ()
{
  _probe="${WORK}/mknod-probe"
  rm -f "${_probe}"
  if ! command -v mknod >/dev/null 2>&1; then
    return 1
  fi
  mknod "${_probe}" c 10 200 2>/dev/null || return 1
  if [ -c "${_probe}" ]; then
    rm -f "${_probe}"
    return 0
  fi
  rm -f "${_probe}"
  return 1
}

easytier_tun_driver_present() { return 1; }

if easytier_ensure_tun 2>/dev/null; then
  echo "FAIL: ensure_tun must fail when device and driver evidence are absent" >&2
  exit 1
fi

easytier_tun_driver_present() { return 0; }

if easytier_ensure_tun 2>/dev/null; then
  echo "FAIL: ensure_tun must fail when driver is present but char device is missing" >&2
  exit 1
fi

if ! easytier_host_can_mknod; then
  echo "Note: host cannot mknod; skipped rw-probe simulations"
  echo "OK EasyTier TUN readiness rejects missing device (caphelper prepares TUN on DSM; prestart is rw-only)"
  exit 0
fi

# --- Device exists but not readable/writable (EACCES) ---
mknod "${EASYTIER_TUN_DEV}" c 10 200
chmod 000 "${EASYTIER_TUN_DEV}"
if easytier_ensure_tun 2>/dev/null; then
  echo "FAIL: ensure_tun must reject inaccessible tun node (mode 000)" >&2
  exit 1
fi
if easytier_tun_rw_by_package_user; then
  echo "FAIL: rw probe must reject mode 000" >&2
  exit 1
fi

# --- Device accessible (diagnostic pass; does not imply TUN creation works) ---
chmod 666 "${EASYTIER_TUN_DEV}"
if ! easytier_tun_rw_by_package_user; then
  echo "FAIL: rw probe must accept readable/writable char device" >&2
  exit 1
fi
if ! easytier_ensure_tun; then
  echo "FAIL: ensure_tun must pass when node exists and is rw" >&2
  exit 1
fi

# --- Wrong node type ---
rm -f "${EASYTIER_TUN_DEV}"
printf 'not-a-char-dev' >"${EASYTIER_TUN_DEV}"
if easytier_ensure_tun 2>/dev/null; then
  echo "FAIL: ensure_tun must reject non-char path" >&2
  exit 1
fi

echo "OK EasyTier TUN post-caphelper: char device + package-user rw probe only"