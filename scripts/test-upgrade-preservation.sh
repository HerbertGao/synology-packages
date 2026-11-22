#!/usr/bin/env bash
# Simulated upgrade hooks (does not run on DSM).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/upgrade-sim"
SVC="${ROOT}/packages/openlist/overlay/spk/openlist/src/service-setup.sh"

rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/upgrade-temp"

export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export SYNOPKG_TEMP_UPGRADE_FOLDER="${WORK}/upgrade-temp"
export SYNOPKG_PKG_STATUS="UPGRADE"
export OPENLIST="${SYNOPKG_PKGDEST}/bin/openlist --data ${SYNOPKG_PKGVAR}"

cp "${ROOT}/packages/openlist/overlay/spk/openlist/src/config.json" "${SYNOPKG_PKGVAR}/config.json"
sed -i 's/"http_port": 5244/"http_port": 5255/' "${SYNOPKG_PKGVAR}/config.json"
echo "probe" > "${SYNOPKG_PKGVAR}/data.db"

export CP=cp
# shellcheck disable=SC1090
. "${SVC}"

service_save
rm -f "${SYNOPKG_PKGVAR}/config.json"
service_restore

if ! grep -q '5255' "${SYNOPKG_PKGVAR}/config.json"; then
  echo "FAIL: custom http_port not preserved" >&2
  exit 1
fi
if [ ! -f "${SYNOPKG_PKGVAR}/data.db" ]; then
  echo "FAIL: data.db not preserved" >&2
  exit 1
fi

echo "OK simulated upgrade preserved config and data.db"