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

pkg=$(release_manifest_field "$manifest" package)
export RELEASE_CI_SPK_JOB
RELEASE_CI_SPK_JOB=$(bash "$ROOT/scripts/release-ci-sha.sh" job-name "$pkg")

fetched_sha=$(bash "$ROOT/scripts/release_fetch_manifest_artifacts.sh" \
  "$manifest" "$work") || exit 1

recorded_sha=$(release_manifest_ci_sha "$manifest")
if [[ $fetched_sha != "$recorded_sha" ]]; then
  release_manifest_set_artifact_sha "$manifest" "$fetched_sha"
fi

node "$ROOT/scripts/update-packages-json.mjs" \
  --manifest "$manifest" \
  --spk-dir "$work" \
  --repo "${GITHUB_REPOSITORY:-HerbertGao/synology-packages}"