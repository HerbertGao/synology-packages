# shellcheck shell=sh
# Sourced by Synology DSM via spksrc; not executed as a standalone script.
# shellcheck disable=SC2034,SC2154 -- SERVICE_COMMAND/SVC_* are consumed by spksrc start-stop-status after merge.

_openlist_port_sync="${SYNOPKG_PKGDEST}/scripts/openlist-dsm-port-sync.sh"
if [ ! -f "${_openlist_port_sync}" ] && [ -n "${OPENLIST_PORT_SYNC_SH}" ]; then
    _openlist_port_sync="${OPENLIST_PORT_SYNC_SH}"
fi
if [ -f "${_openlist_port_sync}" ]; then
    # shellcheck source=/dev/null
    . "${_openlist_port_sync}"
fi

OPENLIST="${SYNOPKG_PKGDEST}/bin/openlist --data ${SYNOPKG_PKGVAR}"
CONFIG_FILE="${SYNOPKG_PKGVAR}/config.json"
DEFAULT_HTTP_PORT="5244"

SERVICE_COMMAND="${OPENLIST} server"
SVC_BACKGROUND=yes
SVC_WRITE_PID=yes

openlist_runtime_http_port ()
{
    _p
    _p=$(openlist_read_http_port_from_config 2>/dev/null) || echo "${DEFAULT_HTTP_PORT}"
    echo "${_p}"
}

service_save ()
{
    if [ "${SYNOPKG_PKG_STATUS}" != "UPGRADE" ]; then
        return 0
    fi
    if [ -f "${CONFIG_FILE}" ]; then
        $CP "${CONFIG_FILE}" "${SYNOPKG_TEMP_UPGRADE_FOLDER}/config.json"
        touch "${SYNOPKG_TEMP_UPGRADE_FOLDER}/.has_config"
    fi
    for item in data.db data.db-shm data.db-wal bleve log temp; do
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
    $CP "${SYNOPKG_TEMP_UPGRADE_FOLDER}/config.json" "${CONFIG_FILE}"
    for item in data.db data.db-shm data.db-wal bleve log temp; do
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
        echo "Missing ${CONFIG_FILE}; aborting upgrade to avoid data loss."
        exit 1
    fi
}

service_postinst ()
{
    if [ "${SYNOPKG_PKG_STATUS}" == "INSTALL" ]; then
        JWT_SECRET=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)

        SITE_URL=$(echo -n "${wizard_site_url}" | sed 's|/$||')

        sed -e "s|%site_url%|${SITE_URL}|g" \
            -e "s|%jwt_secret%|${JWT_SECRET}|g" \
            -e "s|%data%|${SYNOPKG_PKGVAR}|g" \
            -i "${CONFIG_FILE}"

        if [ -n "${wizard_admin_password}" ]; then
            ${OPENLIST} admin set "${wizard_admin_password}"
        fi
    fi
    openlist_sync_dsm_port_metadata || true
}

service_postupgrade ()
{
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "config.json missing after upgrade restore; manual intervention required."
        exit 1
    fi
    if ! openlist_sync_dsm_port_metadata; then
        echo "DSM port metadata sync failed; upgrade continues (OpenList config unchanged)."
    fi
    if ! ${OPENLIST} migrate 2>/tmp/openlist-migrate.log; then
        echo "OpenList migrate failed; see /tmp/openlist-migrate.log"
        echo "Package left installed; data under ${SYNOPKG_PKGVAR} preserved."
        exit 1
    fi
    openlist_sync_dsm_port_metadata || true
}

service_poststart ()
{
    openlist_sync_dsm_port_metadata || true
}