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
  echo "FAIL: overlay uses caphelper tool; do not combine with ctrl-script" >&2
  exit 1
fi

if jq -e '.executable' "${PRIV}" >/dev/null 2>&1; then
  echo "FAIL: overlay declares caphelper via tool[], not executable[]" >&2
  exit 1
fi

tool_count="$(jq -r '.tool | length' "${PRIV}")"
if [ "${tool_count}" != "1" ]; then
  echo "FAIL: privilege must declare exactly one tool[] entry (caphelper), got ${tool_count}" >&2
  exit 1
fi

if ! jq -e '.tool[] | select(.relpath=="bin/helper/caphelper")' "${PRIV}" >/dev/null 2>&1; then
  echo "FAIL: tool must be bin/helper/caphelper only" >&2
  exit 1
fi

if jq -e '.tool[] | select(has("capabilities"))' "${PRIV}" >/dev/null 2>&1; then
  echo "FAIL: privilege must not declare tool.capabilities (unsigned SPK install rejected with 319)" >&2
  exit 1
fi

tool_user="$(jq -r '.tool[] | select(.relpath=="bin/helper/caphelper") | .user' "${PRIV}")"
tool_group="$(jq -r '.tool[] | select(.relpath=="bin/helper/caphelper") | .group' "${PRIV}")"
tool_perm="$(jq -r '.tool[] | select(.relpath=="bin/helper/caphelper") | .permission // empty' "${PRIV}")"

if [ "${tool_user}" != "root" ] || [ "${tool_group}" != "package" ]; then
  echo "FAIL: caphelper tool must be user root group package (got user=${tool_user} group=${tool_group})" >&2
  exit 1
fi

if [ "${tool_perm}" != "4550" ]; then
  echo "FAIL: caphelper tool permission must be 4550, got \"${tool_perm}\"" >&2
  exit 1
fi

if jq -e '.tool[] | select(.relpath=="bin/easytier-core")' "${PRIV}" >/dev/null 2>&1; then
  echo "FAIL: easytier-core must not be a privilege tool (caps applied by caphelper at start)" >&2
  exit 1
fi

echo "EasyTier privilege schema checks passed"