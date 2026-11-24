#!/usr/bin/env bash
# Offline prestart simulation: caphelper before TUN probe; failure blocks start.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/easytier-caphelper-prestart"
SVC="${ROOT}/packages/easytier/overlay/spk/EasyTier/src/service-setup.sh"

rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/target/bin/helper" "${WORK}/dev/net"
printf '%s\n' '#!/bin/sh' 'exit 1' >"${WORK}/target/bin/helper/caphelper"
chmod 755 "${WORK}/target/bin/helper/caphelper"
printf 'hostname = "n"' >"${WORK}/var/config.toml"
: >"${WORK}/var/caphelper.out"

export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
export EASYTIER_TUN_DEV="${WORK}/dev/net/tun"
export CP=cp
export PATH="/usr/bin:/bin"

# shellcheck disable=SC1090,SC1091
. "${SVC}"

if ( service_prestart ) 2>/dev/null; then
  echo "FAIL: prestart must fail when caphelper fails" >&2
  exit 1
fi

# Verify call order: caphelper runs before TUN probe (no mknod required).
ORDER_FILE="${WORK}/prestart-order.txt"
: >"${ORDER_FILE}"
easytier_run_caphelper ()
{
  echo -n 'caphelper;' >>"${ORDER_FILE}"
  mkdir -p "${SYNOPKG_PKGVAR}"
  : >"${CAPHELPER_OUT}"
  echo 'EasyTierCapHelper: STAGE=tun loaded=no created=no mode=0666' >>"${CAPHELPER_OUT}"
  echo 'EasyTierCapHelper: RESULT=ok' >>"${CAPHELPER_OUT}"
  return 0
}
easytier_ensure_tun ()
{
  echo -n 'tun;' >>"${ORDER_FILE}"
  return 0
}

if ! ( service_prestart ); then
  echo "FAIL: prestart should pass when caphelper succeeds (tun stubbed)" >&2
  exit 1
fi
if [ "$(cat "${ORDER_FILE}")" != "caphelper;tun;" ]; then
  echo "FAIL: expected prestart order caphelper;tun;, got: $(cat "${ORDER_FILE}")" >&2
  exit 1
fi
if ! grep -q 'STAGE=tun' "${SYNOPKG_PKGVAR}/caphelper.out"; then
  echo "FAIL: caphelper.out should contain STAGE=tun line" >&2
  exit 1
fi

if mknod "${WORK}/dev/net/tun" c 10 200 2>/dev/null && [ -c "${WORK}/dev/net/tun" ]; then
  chmod 666 "${WORK}/dev/net/tun"
  unset -f easytier_ensure_tun 2>/dev/null || true
  # shellcheck disable=SC1091
  . "${SVC}"
  easytier_run_caphelper ()
  {
    mkdir -p "${SYNOPKG_PKGVAR}"
    : >"${CAPHELPER_OUT}"
    echo 'EasyTierCapHelper: RESULT=ok' >>"${CAPHELPER_OUT}"
    return 0
  }
  if ! ( service_prestart ); then
    echo "FAIL: prestart with real tun rw probe should pass" >&2
    exit 1
  fi
else
  echo "SKIP: no mknod; post-caphelper rw probe not executed on this host"
fi

echo "OK EasyTier prestart: caphelper before tun; failure blocks start"