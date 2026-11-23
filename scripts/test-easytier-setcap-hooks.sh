#!/usr/bin/env bash
# Simulated postinst/postupgrade setcap hooks for EasyTier (does not run on DSM).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/easytier-setcap-sim"
SVC="${ROOT}/packages/easytier/overlay/spk/EasyTier/src/service-setup.sh"

write_mock_cap_bins ()
{
  local log="$1"
  local core_path="$2"
  mkdir -p "${WORK}/sbin"
  cat >"${WORK}/sbin/setcap" <<EOF
#!/bin/sh
echo "\$@" >>"${log}"
exit 0
EOF
  cat >"${WORK}/sbin/getcap" <<EOF
#!/bin/sh
echo "${core_path} cap_net_admin,cap_net_raw=ep"
exit 0
EOF
  chmod +x "${WORK}/sbin/setcap" "${WORK}/sbin/getcap"
  export PATH="${WORK}/sbin:/usr/bin:/bin"
}

# postinst on INSTALL: setcap + config template copy
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
setcap_log="${WORK}/setcap-postinst.log"
write_mock_cap_bins "${setcap_log}" "${WORK}/target/bin/easytier-core"
# shellcheck disable=SC1090,SC1091
. "${SVC}"
service_postinst

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "FAIL: postinst should copy config template on INSTALL" >&2
  exit 1
fi
if ! grep -q 'cap_net_admin,cap_net_raw+ep' "${setcap_log}"; then
  echo "FAIL: postinst should apply cap_net_admin,cap_net_raw+ep" >&2
  exit 1
fi

# postupgrade: setcap with existing config
rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/target/bin"
printf '%s\n' '#!/bin/sh' >"${WORK}/target/bin/easytier-core"
chmod 755 "${WORK}/target/bin/easytier-core"
printf 'hostname = "keep"\n' >"${WORK}/var/config.toml"

export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
export SYNOPKG_PKG_STATUS="UPGRADE"
export CP=cp
setcap_log="${WORK}/setcap-postupgrade.log"
write_mock_cap_bins "${setcap_log}" "${WORK}/target/bin/easytier-core"
# shellcheck disable=SC1090,SC1091
. "${SVC}"
service_postupgrade

if ! grep -q 'cap_net_admin,cap_net_raw+ep' "${setcap_log}"; then
  echo "FAIL: postupgrade should apply cap_net_admin,cap_net_raw+ep" >&2
  exit 1
fi

# getcap verification failure fails closed
rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/target/bin" "${WORK}/sbin"
printf '%s\n' '#!/bin/sh' >"${WORK}/target/bin/easytier-core"
chmod 755 "${WORK}/target/bin/easytier-core"
cat >"${WORK}/sbin/setcap" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"${WORK}/sbin/getcap" <<'EOF'
#!/bin/sh
echo "no capabilities"
exit 0
EOF
chmod +x "${WORK}/sbin/setcap" "${WORK}/sbin/getcap"
export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
export SYNOPKG_PKG_STATUS="INSTALL"
export CP=cp
export PATH="${WORK}/sbin:/usr/bin:/bin"
# shellcheck disable=SC1090,SC1091
. "${SVC}"
if ( service_postinst ) 2>/dev/null; then
  echo "FAIL: postinst must fail when getcap verification does not show cap_net_admin" >&2
  exit 1
fi

# missing setcap on PATH (and no common paths) fails closed
rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/target/bin"
printf '%s\n' '#!/bin/sh' >"${WORK}/target/bin/easytier-core"
chmod 755 "${WORK}/target/bin/easytier-core"
export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
export SYNOPKG_PKG_STATUS="INSTALL"
export CP=cp
mkdir -p "${WORK}/emptybin"
# shellcheck disable=SC1090,SC1091
. "${SVC}"
export PATH="${WORK}/emptybin"
if easytier_locate_setcap >/dev/null 2>&1; then
  echo "Note: setcap found via fixed paths; skipped unavailable-setcap simulation"
elif ( service_postinst ) 2>/dev/null; then
  echo "FAIL: postinst must fail when setcap is unavailable" >&2
  exit 1
fi
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# missing easytier-core fails closed
rm -rf "${WORK}"
mkdir -p "${WORK}/var" "${WORK}/target/bin"
export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
export SYNOPKG_PKG_STATUS="INSTALL"
export CP=cp
# shellcheck disable=SC1090,SC1091
. "${SVC}"
if ( service_postinst ) 2>/dev/null; then
  echo "FAIL: postinst must fail when easytier-core is missing" >&2
  exit 1
fi

echo "OK EasyTier setcap hooks on postinst/postupgrade; fail closed on errors"