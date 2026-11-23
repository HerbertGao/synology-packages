# shellcheck shell=sh
# Sourced by Synology DSM via spksrc; not executed as a standalone script.
# shellcheck disable=SC2034,SC2154

EASYTIER_CORE="${SYNOPKG_PKGDEST}/bin/easytier-core"
EASYTIER_CORE_CAPS="cap_net_admin,cap_net_raw+ep"
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

easytier_locate_setcap ()
{
    if command -v setcap >/dev/null 2>&1; then
        command -v setcap
        return 0
    fi
    for candidate in /sbin/setcap /usr/sbin/setcap /bin/setcap; do
        if [ -x "${candidate}" ]; then
            echo "${candidate}"
            return 0
        fi
    done
    return 1
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

easytier_apply_core_capabilities ()
{
    if [ ! -f "${EASYTIER_CORE}" ]; then
        echo "Error: easytier-core not found at ${EASYTIER_CORE}; cannot apply file capabilities."
        exit 1
    fi

    setcap_bin="$(easytier_locate_setcap)" || {
        echo "Error: setcap not found; cannot grant TUN capabilities to easytier-core."
        exit 1
    }

    if ! "${setcap_bin}" "${EASYTIER_CORE_CAPS}" "${EASYTIER_CORE}"; then
        echo "Error: setcap failed for ${EASYTIER_CORE} (${EASYTIER_CORE_CAPS})."
        exit 1
    fi

    getcap_bin="$(easytier_locate_getcap)" || {
        echo "Error: getcap not found; cannot verify capabilities on easytier-core."
        exit 1
    }

    if ! "${getcap_bin}" "${EASYTIER_CORE}" | grep -q 'cap_net_admin'; then
        echo "Error: getcap verification failed; cap_net_admin not present on ${EASYTIER_CORE}."
        exit 1
    fi
    if ! "${getcap_bin}" "${EASYTIER_CORE}" | grep -q 'cap_net_raw'; then
        echo "Error: getcap verification failed; cap_net_raw not present on ${EASYTIER_CORE}."
        exit 1
    fi
}

service_postinst ()
{
    easytier_apply_core_capabilities
    if [ "${SYNOPKG_PKG_STATUS}" = "INSTALL" ]; then
        if [ ! -f "${CONFIG_FILE}" ] && [ -f "${CONFIG_TEMPLATE}" ]; then
            $CP "${CONFIG_TEMPLATE}" "${CONFIG_FILE}"
        fi
    fi
}

service_postupgrade ()
{
    easytier_apply_core_capabilities
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

easytier_ensure_tun ()
{
  had_tun_dev=0
  if [ -c "${EASYTIER_TUN_DEV}" ]; then
    had_tun_dev=1
  fi

  if [ ! -d "${EASYTIER_TUN_DEV_DIR}" ]; then
    mkdir -p "${EASYTIER_TUN_DEV_DIR}"
  fi

  if [ "${had_tun_dev}" -eq 1 ] && easytier_tun_driver_present; then
    return 0
  fi

  if [ -x /sbin/modprobe ]; then
    /sbin/modprobe tun 2>/dev/null || true
  fi

  if easytier_tun_driver_present; then
    if [ ! -c "${EASYTIER_TUN_DEV}" ]; then
      if command -v mknod >/dev/null 2>&1; then
        mknod "${EASYTIER_TUN_DEV}" c 10 200
        chown root:root "${EASYTIER_TUN_DEV}"
        chmod 600 "${EASYTIER_TUN_DEV}"
      fi
    fi
    if [ -c "${EASYTIER_TUN_DEV}" ]; then
      return 0
    fi
  fi

  if [ "${had_tun_dev}" -eq 1 ]; then
    return 0
  fi

  echo "Error: tun driver is not available; a standalone mknod is not sufficient."
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
}