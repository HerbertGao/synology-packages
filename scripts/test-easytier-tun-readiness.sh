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

easytier_host_sudo_noninteractive ()
{
  if ! command -v sudo >/dev/null 2>&1; then
    return 1
  fi
  sudo -n true 2>/dev/null
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
  # --- Direct rw probe (same checks the package user sees at start) ---
  rm -f "${EASYTIER_TUN_DEV}"
  mknod "${EASYTIER_TUN_DEV}" c 10 200
  chmod 666 "${EASYTIER_TUN_DEV}"

  if ! easytier_tun_rw_by_package_user; then
    echo "FAIL: mode 0666 char device must be accepted by easytier_tun_rw_by_package_user" >&2
    exit 1
  fi

  chmod 000 "${EASYTIER_TUN_DEV}"
  if easytier_tun_rw_by_package_user; then
    echo "FAIL: mode 0000 must be rejected (no read/write for effective user)" >&2
    exit 1
  fi

  chmod 666 "${EASYTIER_TUN_DEV}"
  if ! easytier_tun_rw_by_package_user; then
    echo "FAIL: restoring 0666 must be accepted again" >&2
    exit 1
  fi

  # --- ensure_tun: driver present creates accessible node ---
  rm -f "${EASYTIER_TUN_DEV}"
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
  if ! easytier_tun_rw_by_package_user; then
    echo "FAIL: ensure_tun-created node must pass rw probe" >&2
    exit 1
  fi

  # --- ensure_tun: existing node without driver evidence ---
  rm -f "${EASYTIER_TUN_DEV}"
  mknod "${EASYTIER_TUN_DEV}" c 10 200
  chmod 000 "${EASYTIER_TUN_DEV}"

  easytier_tun_driver_present() { return 1; }

  if easytier_ensure_tun 2>/dev/null; then
    echo "FAIL: inaccessible pre-existing node must be rejected" >&2
    exit 1
  fi

  chmod 666 "${EASYTIER_TUN_DEV}"
  if ! easytier_ensure_tun; then
    echo "FAIL: accessible pre-existing node should be accepted when driver probe fails" >&2
    exit 1
  fi

  # --- Privileged: root:root 0600 simulates DSM node package user cannot open ---
  if easytier_host_sudo_noninteractive; then
    rm -f "${EASYTIER_TUN_DEV}"
    sudo -n mknod "${EASYTIER_TUN_DEV}" c 10 200
    sudo -n chown root:root "${EASYTIER_TUN_DEV}"
    sudo -n chmod 600 "${EASYTIER_TUN_DEV}"

    if easytier_tun_rw_by_package_user; then
      echo "FAIL: root:root 0600 must be rejected for non-root effective user" >&2
      exit 1
    fi
    if easytier_ensure_tun 2>/dev/null; then
      echo "FAIL: ensure_tun must reject root-only 0600 device" >&2
      exit 1
    fi

    sudo -n chmod 666 "${EASYTIER_TUN_DEV}"
    if ! easytier_tun_rw_by_package_user; then
      echo "FAIL: root-owned 0666 must be usable by non-root effective user" >&2
      exit 1
    fi
    if ! easytier_ensure_tun; then
      echo "FAIL: ensure_tun must accept root-owned 0666 device" >&2
      exit 1
    fi
    sudo -n rm -f "${EASYTIER_TUN_DEV}"
    echo "Note: exercised privileged root:root 0600 vs 0666 integration via sudo"
  else
    echo "Note: sudo not available non-interactively; skipped root:root 0600 integration (covered mode 0000 vs 0666 as unprivileged owner)"
  fi
else
  echo "Note: host cannot mknod; skipped driver-present, rw-probe, and pre-existing node simulations"
fi

echo "OK EasyTier TUN readiness rejects mknod-only; rw probe rejects missing rights and accepts available rights"