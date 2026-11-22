#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROOT
chmod +x "${ROOT}"/scripts/*.sh
"${ROOT}/scripts/verify-upstream-digests.sh"
"${ROOT}/scripts/check-port-consistency.sh"
"${ROOT}/scripts/test-upgrade-preservation.sh"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S error "${ROOT}"/scripts/*.sh
  shellcheck -S error -e SC2034,SC2154 "${ROOT}"/packages/openlist/overlay/spk/openlist/src/service-setup.sh
fi
echo "All static checks passed"