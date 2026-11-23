#!/usr/bin/env bash
# Simulated upgrade safety: missing config blocks postupgrade; valid config preserves data.
# OpenList v4.2.10 has no `migrate` CLI — schema updates run on `server` start (bootstrap.Init).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/upgrade-safety-sim"
SVC="${ROOT}/packages/openlist/overlay/spk/openlist/src/service-setup.sh"

rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/target/scripts" "${WORK}/target/app"

cp "${ROOT}/packages/openlist/overlay/spk/openlist/src/config.json" "${WORK}/var/config.json"
cp "${ROOT}/packages/openlist/overlay/spk/openlist/src/openlist-dsm-port-sync.sh" \
  "${WORK}/target/scripts/openlist-dsm-port-sync.sh"
printf 'dst.ports="5244/tcp"\n' >"${WORK}/target/app/openlist.sc"
cat >"${WORK}/target/app/config" <<'EOF'
{
  ".url": {
    "com.synocommunity.packages.openlist": {
      "port": "5244"
    }
  }
}
EOF
echo "db-before" >"${WORK}/var/data.db"

export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.json"
export OPENLIST_PORT_SYNC_SH="${WORK}/target/scripts/openlist-dsm-port-sync.sh"
export CP=cp

# shellcheck disable=SC1090,SC1091
. "${SVC}"

echo "case: postupgrade aborts when config.json missing"
rm -f "${CONFIG_FILE}"
set +e
( service_postupgrade )
_rc=$?
set -e
if [ "${_rc}" -eq 0 ]; then
  echo "FAIL: expected exit 1 when config.json missing" >&2
  exit 1
fi
if [ ! -f "${SYNOPKG_PKGVAR}/data.db" ] || ! grep -q db-before "${SYNOPKG_PKGVAR}/data.db"; then
  echo "FAIL: data.db should remain when postupgrade aborts on missing config" >&2
  exit 1
fi

echo "case: postupgrade succeeds and preserves data with valid config"
cp "${ROOT}/packages/openlist/overlay/spk/openlist/src/config.json" "${WORK}/var/config.json"
set +e
( service_postupgrade )
_rc=$?
set -e
if [ "${_rc}" -ne 0 ]; then
  echo "FAIL: service_postupgrade should succeed with valid config" >&2
  exit 1
fi
if ! grep -q db-before "${SYNOPKG_PKGVAR}/data.db"; then
  echo "FAIL: data.db not preserved after successful postupgrade" >&2
  exit 1
fi

echo "OK upgrade-safety simulation passed (no migrate CLI; server start migrates on NAS)"