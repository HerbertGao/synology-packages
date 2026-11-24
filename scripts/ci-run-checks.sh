#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROOT
chmod +x "${ROOT}"/scripts/*.sh
"${ROOT}/scripts/verify-upstream-digests.sh"
"${ROOT}/scripts/verify-easytier-digests.sh"
"${ROOT}/scripts/test-easytier-upgrade-preservation.sh"
"${ROOT}/scripts/test-easytier-start-guards.sh"
"${ROOT}/scripts/test-easytier-tun-readiness.sh"
"${ROOT}/scripts/test-easytier-privilege-schema.sh"
"${ROOT}/scripts/test-easytier-caphelper-host.sh"
"${ROOT}/scripts/test-easytier-caphelper-sha256.sh"
"${ROOT}/scripts/test-easytier-cap-blob.sh"
"${ROOT}/scripts/test-easytier-caphelper-prestart.sh"
"${ROOT}/scripts/check-port-consistency.sh"
"${ROOT}/scripts/test-upgrade-preservation.sh"
"${ROOT}/scripts/test-port-sync.sh"
"${ROOT}/scripts/test-migrate-failure-sim.sh"
if command -v node >/dev/null 2>&1; then
  node --test "${ROOT}/scripts/check-upstreams.test.mjs"
  node "${ROOT}/scripts/check-upstreams.mjs" --validate
fi
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S error "${ROOT}"/scripts/*.sh
  shellcheck -S error "${ROOT}"/packages/openlist/overlay/spk/openlist/src/openlist-dsm-port-sync.sh
  shellcheck -S error "${ROOT}"/packages/openlist/overlay/spk/openlist/src/service-setup.sh
  shellcheck -S error "${ROOT}"/packages/easytier/overlay/spk/EasyTier/src/service-setup.sh
fi
echo "All static checks passed"