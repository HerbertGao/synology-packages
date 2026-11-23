#!/usr/bin/env bash
# Simulated postinst/postupgrade capability warning hooks (does not run on DSM).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/easytier-cap-warn-sim"
SVC="${ROOT}/packages/easytier/overlay/spk/EasyTier/src/service-setup.sh"

# postinst on INSTALL: no exit on missing caps; copies config template
rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/target/bin" "${WORK}/target/var"
printf '%s\n' '#!/bin/sh' >"${WORK}/target/bin/easytier-core"
chmod 755 "${WORK}/target/bin/easytier-core"
printf '# template\n' >"${WORK}/target/var/config.toml"

export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
export SYNOPKG_PKG_STATUS="INSTALL"
export CP=cp
export PATH="/usr/bin:/bin"
# shellcheck disable=SC1090,SC1091
. "${SVC}"

if ! service_postinst; then
  echo "FAIL: postinst must not fail when capabilities are missing (installer runs as package user)" >&2
  exit 1
fi
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "FAIL: postinst should copy config template on INSTALL" >&2
  exit 1
fi

# missing getcap: warn only (when locate cannot find getcap anywhere)
rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/target/bin"
printf '%s\n' '#!/bin/sh' >"${WORK}/target/bin/easytier-core"
chmod 755 "${WORK}/target/bin/easytier-core"
export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
export SYNOPKG_PKG_STATUS="UPGRADE"
export CP=cp
printf 'hostname = "keep"\n' >"${CONFIG_FILE}"
# shellcheck disable=SC1090,SC1091
. "${SVC}"
mkdir -p "${WORK}/emptybin"
export PATH="${WORK}/emptybin"
if easytier_locate_getcap >/dev/null 2>&1; then
  echo "Note: getcap found via fixed paths; skipped unavailable-getcap warn simulation"
else
  out="$(service_postupgrade 2>&1)"
  if ! echo "${out}" | grep -qi 'Warning.*getcap'; then
    echo "FAIL: postupgrade should warn when getcap is unavailable" >&2
    exit 1
  fi
fi
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# getcap reports missing caps: warn only, upgrade still succeeds
rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/target/bin" "${WORK}/sbin"
printf '%s\n' '#!/bin/sh' >"${WORK}/target/bin/easytier-core"
chmod 755 "${WORK}/target/bin/easytier-core"
cat >"${WORK}/sbin/getcap" <<'EOF'
#!/bin/sh
echo ""
exit 0
EOF
chmod +x "${WORK}/sbin/getcap"
export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
export SYNOPKG_PKG_STATUS="UPGRADE"
export CP=cp
printf 'hostname = "keep"\n' >"${CONFIG_FILE}"
export PATH="${WORK}/sbin:/usr/bin:/bin"
# shellcheck disable=SC1090,SC1091
. "${SVC}"
out="$(service_postupgrade 2>&1)"
if ! echo "${out}" | grep -qi 'Warning.*no file capabilities'; then
  echo "FAIL: postupgrade should warn when getcap shows no capabilities" >&2
  exit 1
fi

echo "OK EasyTier install hooks warn on missing caps but do not abort install/upgrade"