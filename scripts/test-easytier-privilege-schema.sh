#!/usr/bin/env bash
# Validate EasyTier conf/privilege against DSM 7.x documented schema (offline).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRIV="${ROOT}/packages/easytier/overlay/spk/EasyTier/src/conf/privilege"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; privilege schema test omitted"
  exit 0
fi

if ! jq -e . "${PRIV}" >/dev/null; then
  echo "FAIL: privilege is not valid JSON: ${PRIV}" >&2
  exit 1
fi

unknown="$(jq -r 'paths | select(length==1) | .[0]' "${PRIV}" | while read -r key; do
  case "${key}" in
    defaults|username|groupname|ctrl-script|executable|tool|join-groupname|join-pkg-groupnames) ;;
    *) echo "${key}" ;;
  esac
done)"
if [ -n "${unknown}" ]; then
  echo "FAIL: privilege contains unknown top-level keys:" >&2
  echo "${unknown}" >&2
  exit 1
fi

run_as="$(jq -r '.defaults."run-as" // empty' "${PRIV}")"
if [ "${run_as}" != "package" ]; then
  echo "FAIL: defaults.run-as must be \"package\", got \"${run_as}\"" >&2
  exit 1
fi

username="$(jq -r '.username // empty' "${PRIV}")"
groupname="$(jq -r '.groupname // empty' "${PRIV}")"
if [ "${username}" != "EasyTier" ] || [ "${groupname}" != "EasyTier" ]; then
  echo "FAIL: username and groupname must both be EasyTier (got user=${username} group=${groupname})" >&2
  exit 1
fi

if jq -e '.["ctrl-script"]' "${PRIV}" >/dev/null 2>&1; then
  echo "FAIL: privilege must not contain ctrl-script (DSM 7.3 rejected start-as-root elevation)" >&2
  exit 1
fi

if jq -e '.executable' "${PRIV}" >/dev/null 2>&1; then
  echo "FAIL: privilege must not contain executable (DSM 7.3 rejected alongside invalid ctrl-script)" >&2
  exit 1
fi

if ! jq -e '.tool | length >= 1' "${PRIV}" >/dev/null 2>&1; then
  echo "FAIL: privilege must declare tool[] for easytier-core file capabilities" >&2
  exit 1
fi

if ! jq -e '.tool[] | select(.relpath=="bin/easytier-core")' "${PRIV}" >/dev/null 2>&1; then
  echo "FAIL: tool must include relpath bin/easytier-core" >&2
  exit 1
fi

tool_user="$(jq -r '.tool[] | select(.relpath=="bin/easytier-core") | .user' "${PRIV}")"
tool_group="$(jq -r '.tool[] | select(.relpath=="bin/easytier-core") | .group' "${PRIV}")"
if [ "${tool_user}" != "package" ] || [ "${tool_group}" != "package" ]; then
  echo "FAIL: tool user/group for easytier-core must be the literal \"package\" (got user=${tool_user} group=${tool_group})" >&2
  exit 1
fi

tool_caps="$(jq -r '.tool[] | select(.relpath=="bin/easytier-core") | .capabilities // empty' "${PRIV}")"
if [ -z "${tool_caps}" ]; then
  echo "FAIL: tool entry for easytier-core must declare capabilities" >&2
  exit 1
fi
if [ "${tool_caps}" != "cap_net_admin,cap_net_raw" ]; then
  echo "FAIL: tool capabilities must be cap_net_admin,cap_net_raw (no +-=eip), got \"${tool_caps}\"" >&2
  exit 1
fi
if echo "${tool_caps}" | grep -qE '[+=]'; then
  echo "FAIL: tool capabilities must not use setcap suffix symbols (+ or =); use comma-separated cap names only" >&2
  exit 1
fi

tool_perm="$(jq -r '.tool[] | select(.relpath=="bin/easytier-core") | .permission // empty' "${PRIV}")"
if ! echo "${tool_perm}" | grep -qE '^[0-7]{4}$'; then
  echo "FAIL: tool permission must be a 4-digit octal value, got \"${tool_perm}\"" >&2
  exit 1
fi

echo "EasyTier privilege schema checks passed"