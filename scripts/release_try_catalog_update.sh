#!/usr/bin/env bash
# Download CI SPK artifacts for TAG and patch docs/packages.json (single package only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tag=${1:-}
[[ -n $tag ]] || exit 1

manifest="${ROOT}/.release/${tag}.json"
[[ -f $manifest ]] || {
  echo "release_try_catalog_update: missing $manifest" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if ! bash "$ROOT/scripts/release_fetch_ci_artifacts.sh" "${RELEASE_REV:-HEAD}" "$work"; then
  exit 1
fi

node "$ROOT/scripts/update-packages-json.mjs" \
  --manifest "$manifest" \
  --spk-dir "$work" \
  --repo "${GITHUB_REPOSITORY:-HerbertGao/synology-packages}"