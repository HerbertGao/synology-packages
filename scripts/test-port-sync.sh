#!/usr/bin/env bash
# Simulated DSM port sync (does not run on real DSM — no Package Center UI refresh API).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/port-sync-sim"
SYNC="${ROOT}/packages/openlist/overlay/spk/openlist/src/openlist-dsm-port-sync.sh"
SVC="${ROOT}/packages/openlist/overlay/spk/openlist/src/service-setup.sh"

rm -rf "${WORK}"
mkdir -p "${WORK}/target/app" "${WORK}/target/scripts" "${WORK}/var" \
  "${WORK}/var-packages/openlist/conf"

cp "${SYNC}" "${WORK}/target/scripts/openlist-dsm-port-sync.sh"
cp "${ROOT}/packages/openlist/overlay/spk/openlist/src/config.json" "${WORK}/var/config.json"

# Minimal spksrc-generated DSM7 integration files (SERVICE_PORT=5244 at build time).
cat >"${WORK}/target/app/openlist.sc" <<'EOF'
[openlist]
title="openlist"
desc="OpenList"
port_forward="yes"
dst.ports="5244/tcp"
EOF

cat >"${WORK}/target/app/config" <<'EOF'
{
  ".url": {
    "com.synocommunity.packages.openlist": {
      "title": "OpenList",
      "port": "5244",
      "protocol": "http",
      "type": "url",
      "url": "/"
    }
  }
}
EOF

cp "${WORK}/target/app/openlist.sc" "${WORK}/var-packages/openlist/conf/openlist.sc"
printf '%s\n' 'package="openlist"' 'adminport="5244"' >"${WORK}/var-packages/openlist/INFO"

export SYNOPKG_PKGDEST="${WORK}/target"
export SYNOPKG_PKGVAR="${WORK}/var"
export OPENLIST_DSM_PKG_ROOT="${WORK}/var-packages"
export SYNOPKG_PKGNAME="openlist"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.json"
export OPENLIST_PORT_SYNC_SH="${WORK}/target/scripts/openlist-dsm-port-sync.sh"
export CP=cp

# shellcheck disable=SC1090,SC1091
. "${SYNC}"

assert_sc_port () {
  local file=$1 want=$2
  got=$(openlist_read_sc_port "${file}")
  if [ "${got}" != "${want}" ]; then
    echo "FAIL: ${file} port ${got} != ${want}" >&2
    exit 1
  fi
}

run_sync () {
  if ! openlist_sync_dsm_port_metadata; then
    echo "FAIL: sync returned non-zero" >&2
    exit 1
  fi
}

echo "case: default 5244"
run_sync
assert_sc_port "${WORK}/target/app/openlist.sc" "5244"
grep -q '"port": "5244"' "${WORK}/target/app/config"
grep -q 'adminport="5244"' "${WORK}/var-packages/openlist/INFO"

echo "case: config http_port 5255 does not rewrite DSM metadata"
sed -i 's/"http_port": 5244/"http_port": 5255/' "${CONFIG_FILE}"
# Drift DSM files to a non-upstream port; sync must restore 5244, not 5255.
sed -i 's/dst.ports="5244\/tcp"/dst.ports="5255\/tcp"/' "${WORK}/target/app/openlist.sc"
sed -i 's/"port": "5244"/"port": "5266"/' "${WORK}/target/app/config"
sed -i 's/adminport="5244"/adminport="5266"/' "${WORK}/var-packages/openlist/INFO"
run_sync
assert_sc_port "${WORK}/target/app/openlist.sc" "5244"
assert_sc_port "${WORK}/var-packages/openlist/conf/openlist.sc" "5244"
grep -q '"port": "5244"' "${WORK}/target/app/config"
grep -q 'adminport="5244"' "${WORK}/var-packages/openlist/INFO"
grep -q '"http_port": 5255' "${CONFIG_FILE}"

echo "case: app tree already 5244 but stale conf/INFO (post-upgrade extract)"
sed -i 's/dst.ports="5244\/tcp"/dst.ports="5255\/tcp"/' "${WORK}/var-packages/openlist/conf/openlist.sc"
sed -i 's/adminport="5244"/adminport="5255"/' "${WORK}/var-packages/openlist/INFO"
# target/app/* left at 5244 from prior case — sync must still refresh persisted metadata.
if openlist_sync_dsm_port_metadata; then
  :
else
  echo "FAIL: sync returned non-zero on stale conf/INFO" >&2
  exit 1
fi
assert_sc_port "${WORK}/target/app/openlist.sc" "5244"
assert_sc_port "${WORK}/var-packages/openlist/conf/openlist.sc" "5244"
grep -q 'adminport="5244"' "${WORK}/var-packages/openlist/INFO"

echo "case: idempotent second run"
run_sync
run_sync

echo "case: service_prestart keeps DSM at 5244 when config differs"
sed -i 's/"http_port": 5255/"http_port": 5266/' "${CONFIG_FILE}"
sed -i 's/dst.ports="5244\/tcp"/dst.ports="5266\/tcp"/' "${WORK}/target/app/openlist.sc"
# shellcheck disable=SC1090,SC1091
. "${SVC}"
service_prestart
assert_sc_port "${WORK}/target/app/openlist.sc" "5244"

echo "case: missing config still syncs to 5244"
rm -f "${CONFIG_FILE}"
run_sync
assert_sc_port "${WORK}/target/app/openlist.sc" "5244"

echo "OK port-sync simulation passed (DSM UI session may still need refresh; not tested here)"