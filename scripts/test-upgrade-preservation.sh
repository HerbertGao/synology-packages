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
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.json"

cp "${ROOT}/packages/openlist/overlay/spk/openlist/src/config.json" "${SYNOPKG_PKGVAR}/config.json"
sed -i 's/"http_port": 5244/"http_port": 5255/' "${SYNOPKG_PKGVAR}/config.json"
echo "probe" > "${SYNOPKG_PKGVAR}/data.db"

export CP=cp
export OPENLIST_PORT_SYNC_SH="${ROOT}/packages/openlist/overlay/spk/openlist/src/openlist-dsm-port-sync.sh"
# shellcheck disable=SC1090,SC1091
. "${ROOT}/packages/openlist/overlay/spk/openlist/src/openlist-dsm-port-sync.sh"
# shellcheck disable=SC1090,SC1091
. "${SVC}"

service_save
rm -f "${SYNOPKG_PKGVAR}/config.json"
service_restore
mkdir -p "${SYNOPKG_PKGDEST}/app" "${SYNOPKG_PKGDEST}/scripts"
cp "${OPENLIST_PORT_SYNC_SH}" "${SYNOPKG_PKGDEST}/scripts/openlist-dsm-port-sync.sh"
# New SPK extract: app integration at upstream 5244; persisted tree still stale.
printf 'dst.ports="5244/tcp"\n' >"${SYNOPKG_PKGDEST}/app/openlist.sc"
cat >"${SYNOPKG_PKGDEST}/app/config" <<'EOF'
{
  ".url": {
    "com.synocommunity.packages.openlist": {
      "port": "5244",
      "protocol": "http"
    }
  }
}
EOF
export OPENLIST_DSM_PKG_ROOT="${WORK}/var-packages"
mkdir -p "${WORK}/var-packages/openlist/conf"
printf 'dst.ports="5255/tcp"\n' >"${WORK}/var-packages/openlist/conf/openlist.sc"
printf '%s\n' 'package="openlist"' 'adminport="5255"' >"${WORK}/var-packages/openlist/INFO"
openlist_sync_dsm_port_metadata
_got_port=$(openlist_read_sc_port "${SYNOPKG_PKGDEST}/app/openlist.sc")
if [ "${_got_port}" != "5244" ]; then
  echo "FAIL: DSM metadata port ${_got_port} != upstream 5244 after upgrade restore" >&2
  exit 1
fi
_got_conf=$(openlist_read_sc_port "${WORK}/var-packages/openlist/conf/openlist.sc")
if [ "${_got_conf}" != "5244" ]; then
  echo "FAIL: conf openlist.sc port ${_got_conf} != 5244" >&2
  exit 1
fi
if ! grep -q 'adminport="5244"' "${WORK}/var-packages/openlist/INFO"; then
  echo "FAIL: INFO adminport not reset to 5244" >&2
  exit 1
fi

if ! grep -q '5255' "${SYNOPKG_PKGVAR}/config.json"; then
  echo "FAIL: custom http_port in config.json not preserved" >&2
  exit 1
fi
if [ ! -f "${SYNOPKG_PKGVAR}/data.db" ]; then
  echo "FAIL: data.db not preserved" >&2
  exit 1
fi

echo "OK simulated upgrade preserved config and data.db; DSM integration reset to 5244"