# shellcheck shell=sh
# Sourced by Synology DSM via spksrc; not executed as a standalone script.
# shellcheck disable=SC2034,SC2154

EASYTIER_CORE="${SYNOPKG_PKGDEST}/bin/easytier-core"
CAPHELPER="${SYNOPKG_PKGDEST}/bin/helper/caphelper"
CAPHELPER_OUT="${SYNOPKG_PKGVAR}/caphelper.out"
CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"
CONFIG_TEMPLATE="${SYNOPKG_PKGDEST}/var/config.toml"

SERVICE_COMMAND="${EASYTIER_CORE} -c ${CONFIG_FILE} --file-log-dir=${SYNOPKG_PKGVAR} --file-log-size=10"
SVC_BACKGROUND=yes
SVC_WRITE_PID=yes

service_save ()
{
    if [ "${SYNOPKG_PKG_STATUS}" != "UPGRADE" ]; then
        return 0
    fi
    if [ -f "${CONFIG_FILE}" ]; then
        $CP "${CONFIG_FILE}" "${SYNOPKG_TEMP_UPGRADE_FOLDER}/config.toml"
        touch "${SYNOPKG_TEMP_UPGRADE_FOLDER}/.has_config"
    fi
    if [ -e "${SYNOPKG_PKGVAR}/EasyTier.log" ]; then
        $CP -a "${SYNOPKG_PKGVAR}/EasyTier.log" "${SYNOPKG_TEMP_UPGRADE_FOLDER}/"
    fi
}

service_restore ()
{
    if [ ! -f "${SYNOPKG_TEMP_UPGRADE_FOLDER}/.has_config" ]; then
        return 0
    fi
    $CP "${SYNOPKG_TEMP_UPGRADE_FOLDER}/config.toml" "${CONFIG_FILE}"
    if [ -e "${SYNOPKG_TEMP_UPGRADE_FOLDER}/EasyTier.log" ]; then
        $CP -a "${SYNOPKG_TEMP_UPGRADE_FOLDER}/EasyTier.log" "${SYNOPKG_PKGVAR}/"
    fi
}

validate_preupgrade ()
{
    if [ "${SYNOPKG_PKG_STATUS}" != "UPGRADE" ]; then
        return 0
    fi
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "Missing ${CONFIG_FILE}; aborting upgrade to avoid replacing config with defaults."
        exit 1
    fi
}

service_postinst ()
{
    if [ "${SYNOPKG_PKG_STATUS}" = "INSTALL" ]; then
        if [ ! -f "${CONFIG_FILE}" ] && [ -f "${CONFIG_TEMPLATE}" ]; then
            $CP "${CONFIG_TEMPLATE}" "${CONFIG_FILE}"
        fi
        echo "EasyTier installed. Edit ${CONFIG_FILE} with your existing node identity (hostname, instance_id, listeners, peers, secrets) before starting."
        echo "A comment-only template was placed if no config existed; the package does not generate network keys or instance IDs."
        echo "File capabilities on easytier-core are applied at start via ${CAPHELPER} (see ${CAPHELPER_OUT} after first start)."
    fi
}

service_postupgrade ()
{
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "config.toml missing after upgrade restore; manual intervention required."
        exit 1
    fi
}

# True when config.toml has at least one non-comment, non-empty line (user intent to run).
easytier_config_ready ()
{
    if [ ! -f "${CONFIG_FILE}" ]; then
        return 1
    fi
    # Comment-only templates must not start easytier-core (upstream would apply default listeners/network).
    if grep -v '^[[:space:]]*#' "${CONFIG_FILE}" | grep -qv '^[[:space:]]*$'; then
        return 0
    fi
    return 1
}

easytier_require_configured ()
{
    if easytier_config_ready; then
        return 0
    fi
    echo "EasyTier is not configured. Edit ${CONFIG_FILE} with listeners, peers, and credentials, then start again."
    return 1
}

easytier_run_caphelper ()
{
    if [ ! -x "${CAPHELPER}" ]; then
        echo "Error: caphelper missing at ${CAPHELPER}; reinstall the package."
        return 1
    fi
    mkdir -p "${SYNOPKG_PKGVAR}"
    : >"${CAPHELPER_OUT}"
    if ! /usr/bin/env -i "${CAPHELPER}" >>"${CAPHELPER_OUT}" 2>&1; then
        echo "Error: caphelper failed; see ${CAPHELPER_OUT}:"
        cat "${CAPHELPER_OUT}"
        return 1
    fi
    if ! grep -q 'RESULT=ok' "${CAPHELPER_OUT}"; then
        echo "Error: caphelper did not report success; see ${CAPHELPER_OUT}:"
        cat "${CAPHELPER_OUT}"
        return 1
    fi
    return 0
}

# Tun device path (overridable in offline tests only).
EASYTIER_TUN_DEV="${EASYTIER_TUN_DEV:-/dev/net/tun}"
EASYTIER_TUN_DEV_DIR="$(dirname "${EASYTIER_TUN_DEV}")"

# Evidence that the tun driver is present (module or built-in), not merely a char node.
easytier_tun_driver_present ()
{
    if [ -e /sys/class/misc/tun ]; then
        return 0
    fi
    if [ -d /sys/module/tun ]; then
        return 0
    fi
    if grep -q '^tun ' /proc/modules 2>/dev/null; then
        return 0
    fi
    return 1
}

# Read-only: can the effective user (package account in prestart) open the tun char device?
easytier_tun_rw_by_package_user ()
{
    if [ ! -c "${EASYTIER_TUN_DEV}" ]; then
        return 1
    fi
    if [ ! -r "${EASYTIER_TUN_DEV}" ] || [ ! -w "${EASYTIER_TUN_DEV}" ]; then
        return 1
    fi
    return 0
}

# Prestart diagnostic only: does not modprobe, mknod, or chmod (package user cannot do those reliably).
easytier_ensure_tun ()
{
    if [ ! -d "${EASYTIER_TUN_DEV_DIR}" ]; then
        echo "Error: ${EASYTIER_TUN_DEV_DIR} is missing; fix the host TUN setup before starting EasyTier."
        return 1
    fi

    if [ ! -c "${EASYTIER_TUN_DEV}" ]; then
        if ! easytier_tun_driver_present; then
            echo "Error: ${EASYTIER_TUN_DEV} is missing and tun driver evidence is absent; enable TUN on the NAS, then retry."
            return 1
        fi
        echo "Error: tun driver appears present but ${EASYTIER_TUN_DEV} is missing; reboot or fix device nodes on the host (this package does not create the node as the package user)."
        return 1
    fi

    if ! easytier_tun_rw_by_package_user; then
        echo "Error: ${EASYTIER_TUN_DEV} is not readable/writable by the EasyTier package user (EACCES-style failure at start); fix host device ACL/mode or ensure caphelper applied caps on easytier-core."
        return 1
    fi

    if ! easytier_tun_driver_present; then
        echo "Warning: ${EASYTIER_TUN_DEV} is accessible but tun driver evidence is absent; start may still fail depending on caps and kernel state."
    fi
    return 0
}

service_prestart ()
{
    if ! easytier_ensure_tun; then
        exit 1
    fi
    if ! easytier_require_configured; then
        exit 1
    fi
    if ! easytier_run_caphelper; then
        exit 1
    fi
}