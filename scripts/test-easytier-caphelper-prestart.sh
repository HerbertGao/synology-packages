#!/usr/bin/env bash
# Offline prestart simulation: caphelper failure must block start.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/easytier-caphelper-prestart"
SVC="${ROOT}/packages/easytier/overlay/spk/EasyTier/src/service-setup.sh"

rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/target/bin/helper" "${WORK}/dev/net"
printf '%s\n' '#!/bin/sh' 'exit 1' >"${WORK}/target/bin/helper/caphelper"
chmod 755 "${WORK}/target/bin/helper/caphelper"
printf 'hostname = "n"' >"${WORK}/var/config.toml"
mknod "${WORK}/dev/net/tun" c 10 200 2>/dev/null || true
chmod 666 "${WORK}/dev/net/tun" 2>/dev/null || true

export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
export EASYTIER_TUN_DEV="${WORK}/dev/net/tun"
export CP=cp
export PATH="/usr/bin:/bin"

# shellcheck disable=SC1090,SC1091
. "${SVC}"

easytier_ensure_tun() { return 0; }

if ( service_prestart ) 2>/dev/null; then
  echo "FAIL: prestart must fail when caphelper fails" >&2
  exit 1
fi

printf '%s\n' '#!/bin/sh' 'echo EasyTierCapHelper: RESULT=ok' >"${WORK}/target/bin/helper/caphelper"
chmod 755 "${WORK}/target/bin/helper/caphelper"

if ! ( service_prestart ); then
  echo "FAIL: prestart should pass when caphelper succeeds and tun/config ok" >&2
  exit 1
fi
if [ ! -f "${SYNOPKG_PKGVAR}/caphelper.out" ]; then
  echo "FAIL: caphelper.out should be written" >&2
  exit 1
fi

echo "OK EasyTier prestart requires successful caphelper"