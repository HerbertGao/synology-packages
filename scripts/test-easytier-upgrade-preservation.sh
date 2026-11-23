#!/usr/bin/env bash
# Simulated upgrade hooks for EasyTier (does not run on DSM).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/easytier-upgrade-sim"
SVC="${ROOT}/packages/easytier/overlay/spk/EasyTier/src/service-setup.sh"

rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/upgrade-temp" "${WORK}/target/var"

export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export SYNOPKG_TEMP_UPGRADE_FOLDER="${WORK}/upgrade-temp"
export SYNOPKG_PKG_STATUS="UPGRADE"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"

cat >"${CONFIG_FILE}" <<'EOF'
# user content preserved across upgrade
hostname = "example-node"
EOF
echo "marker" >"${SYNOPKG_PKGVAR}/EasyTier.log"

export CP=cp
# shellcheck disable=SC1090,SC1091
. "${SVC}"

service_save
printf '# replacement default\n' >"${WORK}/target/var/config.toml"
rm -f "${CONFIG_FILE}"
service_restore

if ! grep -q 'example-node' "${CONFIG_FILE}"; then
  echo "FAIL: config.toml not preserved on upgrade" >&2
  exit 1
fi
if ! grep -q 'replacement default' "${WORK}/target/var/config.toml"; then
  echo "FAIL: packaged template should remain unchanged in target/var" >&2
  exit 1
fi
if [ ! -f "${SYNOPKG_PKGVAR}/EasyTier.log" ]; then
  echo "FAIL: EasyTier.log not preserved" >&2
  exit 1
fi

if ! easytier_config_ready; then
  echo "FAIL: restored user config.toml should be ready to start" >&2
  exit 1
fi

echo "OK simulated EasyTier upgrade preserved config.toml and remains start-ready"