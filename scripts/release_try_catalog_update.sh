#!/usr/bin/env bash
# Download CI SPK artifacts for TAG and patch docs/packages.json (single package only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/release-common.sh
source "$ROOT/scripts/release-common.sh"
tag=${1:-}
[[ -n $tag ]] || exit 1

manifest="${ROOT}/.release/${tag}.json"
[[ -f $manifest ]] || {
  echo "release_try_catalog_update: missing $manifest" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ci_sha=$(release_manifest_ci_sha "$manifest") || {
  echo "release_try_catalog_update: manifest missing ci_sha" >&2
  exit 1
}

if ! bash "$ROOT/scripts/release_fetch_ci_artifacts.sh" "$ci_sha" "$work"; then
  exit 1
fi

node "$ROOT/scripts/update-packages-json.mjs" \
  --manifest "$manifest" \
  --spk-dir "$work" \
  --repo "${GITHUB_REPOSITORY:-HerbertGao/synology-packages}"