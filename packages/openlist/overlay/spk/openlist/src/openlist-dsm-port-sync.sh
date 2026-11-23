# shellcheck shell=sh
# Functions sourced from service-setup.sh on DSM. Sync runtime http_port into DSM integration files.
# Build-time defaults come from spksrc SERVICE_PORT (mk/spksrc.service.mk); DSM has no API to
# re-read package Makefile at runtime (Synology developer guide: port-config protocol-file + app/config).

OPENLIST_DSM_APP_ID="com.synocommunity.packages.openlist"
OPENLIST_PKG_NAME_DEFAULT="openlist"

openlist_pkg_name ()
{
    if [ -n "${SYNOPKG_PKGNAME:-}" ]; then
        echo "${SYNOPKG_PKGNAME}"
        return
    fi
    echo "${OPENLIST_PKG_NAME_DEFAULT}"
}

openlist_read_http_port_from_config ()
{
    _cfg="${1:-${CONFIG_FILE:-}}"
    if [ ! -f "${_cfg}" ]; then
        return 1
    fi
  # Portable on DSM (python3 ships with the OS); avoids requiring jq in the package image.
    python3 - "${_cfg}" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
port = data.get("scheme", {}).get("http_port")
if port is None:
    sys.exit(1)
if isinstance(port, bool) or not isinstance(port, int):
    sys.exit(1)
if port < 1 or port > 65535:
    sys.exit(1)
print(port)
PY
}

openlist_validate_http_port ()
{
    _port="$1"
    case "${_port}" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac
    if [ "${_port}" -lt 1 ] || [ "${_port}" -gt 65535 ]; then
        return 1
    fi
    return 0
}

openlist_sc_dst_ports_line ()
{
    echo "dst.ports=\"$1/tcp\""
}

openlist_read_sc_port ()
{
    _file="$1"
    if [ ! -f "${_file}" ]; then
        return 1
    fi
    sed -n 's/^dst\.ports="\([0-9]*\)\/tcp".*/\1/p' "${_file}" | head -1
}

openlist_sync_app_config_port ()
{
    _app_config="$1"
    _port="$2"
    if [ ! -f "${_app_config}" ]; then
        return 1
    fi
    python3 - "${_app_config}" "${_port}" "${OPENLIST_DSM_APP_ID}" <<'PY'
import json, sys
path, port_s, app_id = sys.argv[1:4]
port = int(port_s)
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
url = data.setdefault(".url", {})
if not url:
    sys.exit(1)
updated = False
for key, entry in list(url.items()):
    if not isinstance(entry, dict):
        continue
    if key == app_id or "port" in entry:
        if entry.get("port") != str(port):
            entry["port"] = str(port)
            updated = True
if not updated and app_id in url and isinstance(url[app_id], dict):
    if url[app_id].get("port") == str(port):
        sys.exit(0)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
}

openlist_sync_info_adminport ()
{
    _info="$1"
    _port="$2"
    if [ ! -f "${_info}" ]; then
        return 0
    fi
    if grep -q '^adminport=' "${_info}"; then
        sed -i "s/^adminport=.*/adminport=\"${_port}\"/" "${_info}"
    else
        printf 'adminport="%s"\n' "${_port}" >> "${_info}"
    fi
}

openlist_sync_sc_file ()
{
    _file="$1"
    _port="$2"
    if [ ! -f "${_file}" ]; then
        return 1
    fi
    _line=$(openlist_sc_dst_ports_line "${_port}")
    if grep -q '^dst\.ports=' "${_file}"; then
        sed -i "s|^dst\.ports=.*|${_line}|" "${_file}"
    else
        printf '%s\n' "${_line}" >> "${_file}"
    fi
}

# Idempotent: skip when installed files already match config.json http_port.
openlist_sync_dsm_port_metadata ()
{
    if [ -z "${SYNOPKG_PKGDEST:-}" ]; then
        echo "SYNOPKG_PKGDEST unset; skipping DSM port sync." >&2
        return 1
    fi
    _pkg=$(openlist_pkg_name)
    _port=$(openlist_read_http_port_from_config) || {
        echo "Cannot read scheme.http_port from ${CONFIG_FILE:-config.json}; skipping DSM port sync." >&2
        return 1
    }
    if ! openlist_validate_http_port "${_port}"; then
        echo "Invalid http_port '${_port}' in ${CONFIG_FILE}; skipping DSM port sync." >&2
        return 1
    fi

    _pkgroot="${OPENLIST_DSM_PKG_ROOT:-/var/packages}"
    _app_config="${SYNOPKG_PKGDEST}/app/config"
    _app_sc="${SYNOPKG_PKGDEST}/app/${_pkg}.sc"
    _conf_sc="${_pkgroot}/${_pkg}/conf/${_pkg}.sc"
    _info="${_pkgroot}/${_pkg}/INFO"

    _need_sync=0
    if [ -f "${_app_sc}" ]; then
        _cur=$(openlist_read_sc_port "${_app_sc}")
        if [ "${_cur}" != "${_port}" ]; then
            _need_sync=1
        fi
    else
        _need_sync=1
    fi

    if [ "${_need_sync}" -eq 0 ] && [ -f "${_app_config}" ]; then
        if ! grep -q "\"port\"[[:space:]]*:[[:space:]]*\"${_port}\"" "${_app_config}"; then
            _need_sync=1
        fi
    fi

    if [ "${_need_sync}" -eq 0 ]; then
        return 0
    fi

    for _sc in "${_app_sc}" "${_conf_sc}"; do
        openlist_sync_sc_file "${_sc}" "${_port}" || true
    done
    openlist_sync_app_config_port "${_app_config}" "${_port}" || {
        echo "Failed to update ${_app_config}" >&2
        return 1
    }
    openlist_sync_info_adminport "${_info}" "${_port}"

    echo "Synchronized DSM UI/firewall metadata to HTTP port ${_port} (from ${CONFIG_FILE})."
    return 0
}