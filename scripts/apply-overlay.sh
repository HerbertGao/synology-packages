#!/usr/bin/env bash
# Apply packages/openlist/overlay onto a SynoCommunity/spksrc checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="${ROOT}/packages/openlist/upstream.lock.json"
OVERLAY="${ROOT}/packages/openlist/overlay"
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

echo "Applying overlay to spksrc @ ${PINNED_SHA}"
rsync -a --delete "${OVERLAY}/" "${SPKSRC_DIR}/"

echo "Overlay applied. Tree ready at ${SPKSRC_DIR}"