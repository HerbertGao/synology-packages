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
    for item in EasyTier.log EasyTier.pid; do
        if [ -e "${SYNOPKG_PKGVAR}/${item}" ]; then
            $CP -a "${SYNOPKG_PKGVAR}/${item}" "${SYNOPKG_TEMP_UPGRADE_FOLDER}/"
        fi
    done
}

service_restore ()
{
    if [ ! -f "${SYNOPKG_TEMP_UPGRADE_FOLDER}/.has_config" ]; then
        return 0
    fi
    $CP "${SYNOPKG_TEMP_UPGRADE_FOLDER}/config.toml" "${CONFIG_FILE}"
    for item in EasyTier.log EasyTier.pid; do
        if [ -e "${SYNOPKG_TEMP_UPGRADE_FOLDER}/${item}" ]; then
            $CP -a "${SYNOPKG_TEMP_UPGRADE_FOLDER}/${item}" "${SYNOPKG_PKGVAR}/"
        fi
    done
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

easytier_ensure_tun ()
{
    if [ ! -d /dev/net ]; then
        mkdir -p /dev/net
    fi
    if [ -x /sbin/modprobe ]; then
        /sbin/modprobe tun
    fi
    if [ ! -c /dev/net/tun ]; then
        if command -v mknod >/dev/null 2>&1; then
            mknod /dev/net/tun c 10 200
            chown root:root /dev/net/tun
            chmod 600 /dev/net/tun
        fi
    fi
    if [ ! -c /dev/net/tun ]; then
        echo "Error: /dev/net/tun is unavailable after loading the tun module."
        return 1
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
}