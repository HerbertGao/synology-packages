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

echo "EasyTier privilege schema checks passed"