#!/usr/bin/env bash
# Repeatable local build entrypoint (host or inside ghcr.io/synocommunity/spksrc).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPKSRC_DIR="${SPKSRC_DIR:-${ROOT}/.build/spksrc}"
TCVERSION="${TCVERSION:-7.3}"

# One arch: ARCH=apollolake. Several: EASYTIER_BUILD_ARCHES="apollolake kvmx64"
if [ -n "${EASYTIER_BUILD_ARCHES:-}" ]; then
  # shellcheck disable=SC2206
  ARCH_LIST=(${EASYTIER_BUILD_ARCHES})
elif [ -n "${ARCH:-}" ]; then
  ARCH_LIST=("${ARCH}")
else
  ARCH_LIST=(apollolake)
fi

"${ROOT}/scripts/apply-overlay.sh" easytier "${SPKSRC_DIR}"

export CARGO_HOME="${SPKSRC_DIR}/distrib/cargo"
export RUSTUP_HOME="${SPKSRC_DIR}/distrib/rustup"
mkdir -p "${CARGO_HOME}" "${RUSTUP_HOME}"
export PATH="${CARGO_HOME}/bin:${PATH}"

if [ ! -f "${SPKSRC_DIR}/local.mk" ]; then
  make -C "${SPKSRC_DIR}" setup
fi
"${ROOT}/scripts/patch-spksrc-local-publisher.sh" "${SPKSRC_DIR}/local.mk"

for ARCH in "${ARCH_LIST[@]}"; do
  echo "Building EasyTier for ${ARCH} DSM ${TCVERSION} (not validated on real hardware in CI)"
  TARGET="spk-EasyTier-${ARCH}-${TCVERSION}"
  if make -C "${SPKSRC_DIR}" -n "${TARGET}" >/dev/null 2>&1; then
    make -C "${SPKSRC_DIR}" "${TARGET}"
  else
    make -C "${SPKSRC_DIR}/spk/EasyTier" "arch-${ARCH}" "TCVERSION=${TCVERSION}"
  fi
done

echo "Artifacts (if successful):"
find "${SPKSRC_DIR}/packages" -maxdepth 1 -name 'EasyTier_*.spk' -print 2>/dev/null
find "${SPKSRC_DIR}/spk/EasyTier" -maxdepth 1 -name '*.spk' -print 2>/dev/null