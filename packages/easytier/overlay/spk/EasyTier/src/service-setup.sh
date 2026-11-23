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

easytier_ensure_tun ()
{
    if [ -c /dev/net/tun ]; then
        return 0
    fi
    if [ ! -d /dev/net ]; then
        mkdir -p /dev/net
    fi
    if command -v mknod >/dev/null 2>&1; then
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 666 /dev/net/tun 2>/dev/null || true
    fi
    if [ ! -c /dev/net/tun ] && [ -x /sbin/modprobe ]; then
        /sbin/modprobe tun 2>/dev/null || true
    fi
    if [ ! -c /dev/net/tun ]; then
        echo "Warning: /dev/net/tun is not available; EasyTier may fail until TUN is enabled on the host."
        return 1
    fi
    return 0
}

service_prestart ()
{
    easytier_ensure_tun || true
}