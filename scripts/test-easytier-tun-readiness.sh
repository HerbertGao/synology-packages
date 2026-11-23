#!/usr/bin/env bash
# Offline TUN readiness checks for EasyTier (does not run on DSM).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/easytier-tun-sim"
SVC="${ROOT}/packages/easytier/overlay/spk/EasyTier/src/service-setup.sh"

rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/dev/net"

export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
export EASYTIER_TUN_DEV="${WORK}/dev/net/tun"
export CP=cp

# shellcheck disable=SC1090,SC1091
. "${SVC}"

easytier_tun_driver_present() { return 1; }

if easytier_ensure_tun 2>/dev/null; then
  echo "FAIL: ensure_tun must fail when driver evidence and device are both absent" >&2
  exit 1
fi

easytier_tun_driver_present() { return 0; }

if easytier_ensure_tun 2>/dev/null; then
  echo "FAIL: ensure_tun must fail when driver is present but char device is missing" >&2
  exit 1
fi

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

if ! easytier_host_can_mknod; then
  echo "Note: host cannot mknod; skipped existing-device simulation"
  echo "OK EasyTier TUN readiness rejects missing device without mknod/modprobe fallback"
  exit 0
fi

mknod "${EASYTIER_TUN_DEV}" c 10 200

if ! easytier_ensure_tun; then
  echo "FAIL: ensure_tun should accept existing tun node when driver evidence is present" >&2
  exit 1
fi

easytier_tun_driver_present() { return 1; }

if ! easytier_ensure_tun; then
  echo "FAIL: ensure_tun should accept existing tun node even when driver probe fails" >&2
  exit 1
fi

echo "OK EasyTier TUN readiness uses DSM device presence; no package-user mknod/modprobe"