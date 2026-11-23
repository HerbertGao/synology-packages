#!/usr/bin/env bash
# Static consistency checks between packaging metadata and default config template.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPK_MK="${ROOT}/packages/openlist/overlay/spk/openlist/Makefile"
CFG="${ROOT}/packages/openlist/overlay/spk/openlist/src/config.json"
SVC="${ROOT}/packages/openlist/overlay/spk/openlist/src/service-setup.sh"

service_port=$(grep -E '^SERVICE_PORT' "${SPK_MK}" | awk '{print $3}')
admin_port=$(grep -E '^ADMIN_PORT' "${SPK_MK}" | awk '{print $3}')
default_cfg_port=$(grep -E '"http_port"' "${CFG}" | head -1 | sed -E 's/.*"http_port"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/')

if [ "${admin_port}" != "\$(SERVICE_PORT)" ]; then
  echo "ADMIN_PORT should reference SERVICE_PORT" >&2
  exit 1
fi

for label in SERVICE_PORT CONFIG_TEMPLATE; do
  val="${service_port}"
  [ "${label}" = "CONFIG_TEMPLATE" ] && val="${default_cfg_port}"
  if [ "${val}" != "${service_port}" ]; then
    echo "Port mismatch at ${label}: ${val} != ${service_port}" >&2
    exit 1
  fi
done

echo "OK default packaging ports consistent at ${service_port}"
SYNC="${ROOT}/packages/openlist/overlay/spk/openlist/src/openlist-dsm-port-sync.sh"
if [ ! -f "${SYNC}" ]; then
  echo "Missing runtime port sync helper: ${SYNC}" >&2
  exit 1
fi
if ! grep -q 'service_prestart' "${SVC}"; then
  echo "service-setup.sh must define service_prestart for DSM port sync on restart" >&2
  exit 1
fi
echo "OK runtime sync helper present (openlist_sync_dsm_port_metadata); build-time SERVICE_PORT remains default ${service_port} per spksrc.service.mk."