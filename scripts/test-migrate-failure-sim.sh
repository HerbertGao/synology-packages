#!/usr/bin/env bash
# Simulated service_postupgrade when openlist migrate fails (no DSM, no real openlist binary).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/migrate-fail-sim"
SVC="${ROOT}/packages/openlist/overlay/spk/openlist/src/service-setup.sh"

rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/target/scripts" "${WORK}/target/app" "${WORK}/bin"

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

cat >"${WORK}/bin/openlist" <<'EOF'
#!/bin/sh
if [ "$1" = "migrate" ]; then
  echo "simulated migrate failure" >&2
  exit 1
fi
exit 0
EOF
chmod +x "${WORK}/bin/openlist"

export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.json"
export OPENLIST_PORT_SYNC_SH="${WORK}/target/scripts/openlist-dsm-port-sync.sh"
export CP=cp

# shellcheck disable=SC1090,SC1091
. "${SVC}"

set +e
( service_postupgrade )
_rc=$?
set -e

if [ "${_rc}" -eq 0 ]; then
  echo "FAIL: expected service_postupgrade to exit 1 on migrate failure" >&2
  exit 1
fi
if [ ! -f "${SYNOPKG_PKGVAR}/data.db" ] || ! grep -q db-before "${SYNOPKG_PKGVAR}/data.db"; then
  echo "FAIL: data.db not preserved after failed migrate" >&2
  exit 1
fi

echo "OK migrate-failure simulation preserves var data and exits non-zero"