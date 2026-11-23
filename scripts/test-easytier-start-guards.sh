#!/usr/bin/env bash
# Simulated start guards for EasyTier (does not run on DSM).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.build/easytier-start-sim"
SVC="${ROOT}/packages/easytier/overlay/spk/EasyTier/src/service-setup.sh"
TEMPLATE="${ROOT}/packages/easytier/overlay/spk/EasyTier/src/config.toml"

rm -rf "${WORK}"
mkdir -p "${WORK}/var"

export SYNOPKG_PKGVAR="${WORK}/var"
export SYNOPKG_PKGDEST="${WORK}/target"
export CP=cp
export CONFIG_FILE="${SYNOPKG_PKGVAR}/config.toml"

# shellcheck disable=SC1090,SC1091
. "${SVC}"

# Comment-only template must not be considered ready.
cp "${TEMPLATE}" "${CONFIG_FILE}"
if easytier_config_ready; then
  echo "FAIL: comment-only template must not be ready to start" >&2
  exit 1
fi
if easytier_require_configured; then
  echo "FAIL: require_configured should reject comment-only template" >&2
  exit 1
fi

# User configuration must be accepted.
cat >"${CONFIG_FILE}" <<'EOF'
hostname = "example-node"
EOF
if ! easytier_config_ready; then
  echo "FAIL: user config.toml should be ready to start" >&2
  exit 1
fi
if ! easytier_require_configured; then
  echo "FAIL: require_configured should accept user config" >&2
  exit 1
fi

echo "OK EasyTier start guards accept configured config and reject comment-only template"