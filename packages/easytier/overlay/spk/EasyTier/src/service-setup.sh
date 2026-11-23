# shellcheck shell=sh
# Sourced by Synology DSM via spksrc; not executed as a standalone script.
# shellcheck disable=SC2034,SC2154

EASYTIER_CORE="${SYNOPKG_PKGDEST}/bin/easytier-core"
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

easytier_locate_getcap ()
{
    if command -v getcap >/dev/null 2>&1; then
        command -v getcap
        return 0
    fi
    for candidate in /sbin/getcap /usr/sbin/getcap /bin/getcap; do
        if [ -x "${candidate}" ]; then
            echo "${candidate}"
            return 0
        fi
    done
    return 1
}

# DSM applies file capabilities from conf/privilege tool at install time (not via postinst setcap).
easytier_warn_if_core_capabilities_missing ()
{
    if [ ! -f "${EASYTIER_CORE}" ]; then
        echo "Warning: easytier-core not found at ${EASYTIER_CORE}; privilege tool capabilities may not apply until the binary is present."
        return 0
    fi

    getcap_bin="$(easytier_locate_getcap)" || {
        echo "Warning: getcap not available; cannot verify file capabilities on easytier-core (declared in privilege tool)."
        return 0
    }

    cap_out="$("${getcap_bin}" "${EASYTIER_CORE}" 2>/dev/null)" || cap_out=""
    if [ -z "${cap_out}" ]; then
        echo "Warning: no file capabilities reported on easytier-core; TUN may fail until DSM applies privilege tool caps (some sideloaded installs may require manual setcap after upgrade)."
        return 0
    fi
    if ! echo "${cap_out}" | grep -q 'cap_net_admin'; then
        echo "Warning: cap_net_admin not present on easytier-core per getcap; TUN creation may fail (check privilege tool or apply caps manually)."
    fi
    if ! echo "${cap_out}" | grep -q 'cap_net_raw'; then
        echo "Warning: cap_net_raw not present on easytier-core per getcap; TUN creation may fail (check privilege tool or apply caps manually)."
    fi
}

service_postinst ()
{
    easytier_warn_if_core_capabilities_missing
    if [ "${SYNOPKG_PKG_STATUS}" = "INSTALL" ]; then
        if [ ! -f "${CONFIG_FILE}" ] && [ -f "${CONFIG_TEMPLATE}" ]; then
            $CP "${CONFIG_TEMPLATE}" "${CONFIG_FILE}"
        fi
        echo "EasyTier installed. Edit ${CONFIG_FILE} with your existing node identity (hostname, instance_id, listeners, peers, secrets) before starting."
        echo "A comment-only template was placed if no config existed; the package does not generate network keys or instance IDs."
    fi
}

service_postupgrade ()
{
    easytier_warn_if_core_capabilities_missing
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

# Readiness for package-user prestart: rely on DSM-provided /dev/net/tun, not mknod/modprobe (require root).
easytier_ensure_tun ()
{
    if [ ! -d "${EASYTIER_TUN_DEV_DIR}" ]; then
        echo "Error: ${EASYTIER_TUN_DEV_DIR} is missing; enable the TUN driver on this NAS before starting EasyTier."
        return 1
    fi

    if [ -c "${EASYTIER_TUN_DEV}" ]; then
        if easytier_tun_driver_present; then
            return 0
        fi
        echo "Warning: ${EASYTIER_TUN_DEV} exists but tun driver evidence is absent; continuing (caps on easytier-core may still work)."
        return 0
    fi

    if ! easytier_tun_driver_present; then
        echo "Error: tun driver is not available and ${EASYTIER_TUN_DEV} is missing; enable TUN on the NAS (kernel module or DSM setting), then retry."
        return 1
    fi

    echo "Error: tun driver appears loaded but ${EASYTIER_TUN_DEV} is missing; reboot or fix device nodes on the host (this package does not create /dev/net/tun as the package user)."
    return 1
}

service_prestart ()
{
    if ! easytier_ensure_tun; then
        exit 1
    fi
    if ! easytier_require_configured; then
        exit 1
    fi
    easytier_warn_if_core_capabilities_missing
}