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
  invalid_actions="$(jq -r '.["ctrl-script"][]?.action // empty' "${PRIV}" | while read -r action; do
    case "${action}" in
      preinst|postinst|preuninst|postuninst|preupgrade|postupgrade|start|stop|status|prestart|prestop) ;;
      *) echo "${action}" ;;
    esac
  done)"
  if [ -n "${invalid_actions}" ]; then
    echo "FAIL: invalid ctrl-script action(s): ${invalid_actions}" >&2
    exit 1
  fi

  invalid_run_as="$(jq -r '.["ctrl-script"][]?."run-as" // empty' "${PRIV}" | while read -r ras; do
    case "${ras}" in
      root|package) ;;
      *) echo "${ras}" ;;
    esac
  done)"
  if [ -n "${invalid_run_as}" ]; then
    echo "FAIL: ctrl-script run-as must be root or package, got: ${invalid_run_as}" >&2
    exit 1
  fi

  bloated="$(jq -r '.["ctrl-script"][]? | select(.action | IN("preinst","postinst","preuninst","postuninst","preupgrade","postupgrade","prestart","prestop")) | .action' "${PRIV}")"
  if [ -n "${bloated}" ]; then
    echo "FAIL: ctrl-script must not elevate install hooks (found: ${bloated})" >&2
    exit 1
  fi

  extra="$(jq -r '.["ctrl-script"][]?.action // empty' "${PRIV}" | while read -r action; do
    case "${action}" in
      start|stop|status) ;;
      *) echo "${action}" ;;
    esac
  done)"
  if [ -n "${extra}" ]; then
    echo "FAIL: unexpected ctrl-script action(s): ${extra}" >&2
    exit 1
  fi
fi

if ! jq -e '.["ctrl-script"][] | select(.action=="start" and ."run-as"=="root")' "${PRIV}" >/dev/null 2>&1; then
  echo "FAIL: ctrl-script must declare start with run-as root (TUN interface creation)" >&2
  exit 1
fi

for action in stop status; do
  if ! jq -e --arg a "${action}" '.["ctrl-script"][] | select(.action==$a and ."run-as"=="root")' "${PRIV}" >/dev/null 2>&1; then
    echo "FAIL: ctrl-script must declare ${action} with run-as root (root-owned service process)" >&2
    exit 1
  fi
done

echo "EasyTier privilege schema checks passed"