#!/usr/bin/env bash
# Repeatable local build entrypoint (host or inside ghcr.io/synocommunity/spksrc).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPKSRC_DIR="${SPKSRC_DIR:-${ROOT}/.build/spksrc}"
ARCH="${ARCH:-apollolake}"
TCVERSION="${TCVERSION:-7.3}"

"${ROOT}/scripts/apply-overlay.sh" openlist "${SPKSRC_DIR}"

export CARGO_HOME="${SPKSRC_DIR}/distrib/cargo"
export RUSTUP_HOME="${SPKSRC_DIR}/distrib/rustup"
mkdir -p "${CARGO_HOME}" "${RUSTUP_HOME}"
export PATH="${CARGO_HOME}/bin:${PATH}"

if [ ! -f "${SPKSRC_DIR}/local.mk" ]; then
  make -C "${SPKSRC_DIR}" setup
fi
"${ROOT}/scripts/patch-spksrc-local-publisher.sh" "${SPKSRC_DIR}/local.mk"

echo "Building openlist for ${ARCH} DSM ${TCVERSION} (not validated on real hardware in CI)"
TARGET="spk-openlist-${ARCH}-${TCVERSION}"
if make -C "${SPKSRC_DIR}" -n "${TARGET}" >/dev/null 2>&1; then
  make -C "${SPKSRC_DIR}" "${TARGET}"
else
  make -C "${SPKSRC_DIR}/spk/openlist" "arch-${ARCH}" "TCVERSION=${TCVERSION}"
fi

echo "Artifacts (if successful):"
find "${SPKSRC_DIR}/packages" -maxdepth 1 -name 'openlist_*.spk' -print 2>/dev/null
find "${SPKSRC_DIR}/spk/openlist" -maxdepth 1 -name '*.spk' -print 2>/dev/null