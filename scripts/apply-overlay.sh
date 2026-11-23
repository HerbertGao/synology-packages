#!/usr/bin/env bash
# Apply packages/<name>/overlay onto a SynoCommunity/spksrc checkout.
# Usage: apply-overlay.sh [openlist|easytier] [SPKSRC_DIR]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="${1:-openlist}"
shift || true
LOCK="${ROOT}/packages/${PACKAGE}/upstream.lock.json"
OVERLAY="${ROOT}/packages/${PACKAGE}/overlay"
SPKSRC_DIR="${1:-${ROOT}/.build/spksrc}"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

PINNED_SHA="$(python3 -c "import json; print(json.load(open('${LOCK}'))['spksrc']['commit'])")"

if [ ! -d "${SPKSRC_DIR}/.git" ]; then
  mkdir -p "$(dirname "${SPKSRC_DIR}")"
  git clone --depth 1 https://github.com/SynoCommunity/spksrc.git "${SPKSRC_DIR}"
  git -C "${SPKSRC_DIR}" fetch --depth 1 origin "${PINNED_SHA}"
  git -C "${SPKSRC_DIR}" checkout "${PINNED_SHA}"
else
  git -C "${SPKSRC_DIR}" fetch --depth 1 origin "${PINNED_SHA}"
  git -C "${SPKSRC_DIR}" checkout "${PINNED_SHA}"
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is required" >&2
  exit 1
fi

echo "Applying overlay to spksrc @ ${PINNED_SHA}"
# Never rsync --delete at spksrc root: overlay only contains cross/ and spk/ recipe deltas.
rsync -a "${OVERLAY}/cross/" "${SPKSRC_DIR}/cross/"
rsync -a "${OVERLAY}/spk/" "${SPKSRC_DIR}/spk/"

echo "Overlay applied. Tree ready at ${SPKSRC_DIR}"