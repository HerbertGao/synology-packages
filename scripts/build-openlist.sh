#!/usr/bin/env bash
# Repeatable local build entrypoint (host or inside ghcr.io/synocommunity/spksrc).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPKSRC_DIR="${SPKSRC_DIR:-${ROOT}/.build/spksrc}"
ARCH="${ARCH:-apollolake}"
TCVERSION="${TCVERSION:-7.3}"

"${ROOT}/scripts/apply-overlay.sh" "${SPKSRC_DIR}"

if [ ! -f "${SPKSRC_DIR}/local.mk" ]; then
  make -C "${SPKSRC_DIR}" setup
fi

echo "Building openlist for ${ARCH} DSM ${TCVERSION} (not validated on real hardware in CI)"
TARGET="spk-openlist-${ARCH}-${TCVERSION}"
if make -C "${SPKSRC_DIR}" -n "${TARGET}" >/dev/null 2>&1; then
  make -C "${SPKSRC_DIR}" "${TARGET}"
else
  make -C "${SPKSRC_DIR}/spk/openlist" "arch-${ARCH}" "TCVERSION=${TCVERSION}"
fi

echo "Artifacts (if successful):"
find "${SPKSRC_DIR}/spk/openlist" -maxdepth 1 -name 'openlist_*.spk' -print