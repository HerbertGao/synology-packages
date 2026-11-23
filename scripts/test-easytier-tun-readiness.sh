#!/usr/bin/env bash
# Offline TUN readiness checks for EasyTier (does not run on DSM).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/easytier-tun-sim"
SVC="${ROOT}/packages/easytier/overlay/spk/EasyTier/src/service-setup.sh"

rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/dev/net"

export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
export EASYTIER_TUN_DEV="${WORK}/dev/net/tun"
export CP=cp

cat >"${WORK}/bin/modprobe" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "${WORK}/bin/modprobe"
export PATH="${WORK}/bin:${PATH}"

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
  echo "FAIL: ensure_tun must fail when driver evidence is absent and no pre-existing node" >&2
  exit 1
fi
if [ -e "${EASYTIER_TUN_DEV}" ]; then
  echo "FAIL: ensure_tun must not create a standalone node without driver evidence" >&2
  exit 1
fi

if easytier_host_can_mknod; then
  easytier_tun_driver_present() { return 0; }

  if ! easytier_ensure_tun; then
    echo "FAIL: ensure_tun should succeed when driver is present and mknod is allowed" >&2
    exit 1
  fi
  if [ ! -c "${EASYTIER_TUN_DEV}" ]; then
    echo "FAIL: ensure_tun should create the tun char device when driver is present" >&2
    exit 1
  fi
  tun_mode="$(stat -c '%a' "${EASYTIER_TUN_DEV}" 2>/dev/null || echo "")"
  if [ "${tun_mode}" != "666" ]; then
    echo "FAIL: mknod fallback should create tun with mode 0666, got ${tun_mode}" >&2
    exit 1
  fi

  rm -f "${EASYTIER_TUN_DEV}"
  mknod "${EASYTIER_TUN_DEV}" c 10 200
  chmod 600 "${EASYTIER_TUN_DEV}" 2>/dev/null || true

  easytier_tun_driver_present() { return 1; }

  if easytier_ensure_tun; then
    echo "FAIL: root-only tun node (0600) should be rejected for package user" >&2
    exit 1
  fi

  chmod 666 "${EASYTIER_TUN_DEV}" 2>/dev/null || true
  if ! easytier_ensure_tun; then
    echo "FAIL: world-readable tun node should be accepted when modprobe/driver probe fails" >&2
    exit 1
  fi
else
  echo "Note: host cannot mknod; skipped driver-present and pre-existing tun simulations"
fi

echo "OK EasyTier TUN readiness rejects mknod-only; driver or pre-existing node required"