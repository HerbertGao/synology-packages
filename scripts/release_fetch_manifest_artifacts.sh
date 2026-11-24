#!/usr/bin/env bash
# Try manifest ci_sha then ci_head (when set) for SPK artifacts; print the sha that worked.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/release-common.sh
source "$ROOT/scripts/release-common.sh"

manifest=${1:-}
dest=${2:-}
[[ -n $manifest && -f $manifest && -n $dest ]] || {
  echo "usage: release_fetch_manifest_artifacts.sh <manifest.json> <dest-dir>" >&2
  exit 2
}

mapfile -t candidates < <(release_manifest_artifact_candidates "$manifest")
((${#candidates[@]} > 0)) || {
  echo "release_fetch_manifest_artifacts: no ci_sha candidates" >&2
  exit 1
}

max_wait=${RELEASE_CI_WAIT_SEC:-7200}
poll=${RELEASE_CI_POLL_SEC:-60}
elapsed=0

try_sha() {
  local sha=$1
  RELEASE_CI_WAIT_SEC=0 bash "$ROOT/scripts/release_fetch_ci_artifacts.sh" \
    "$sha" "$dest" "$manifest"
}

any_in_flight() {
  local sha pending
  for sha in "${candidates[@]}"; do
    pending=$(
      gh run list --workflow="${RELEASE_CI_WORKFLOW:-synology-packages-ci}" \
        --commit="$sha" --limit 5 \
        --json status -q '[.[] | select(.status!="completed")] | length' 2>/dev/null || echo 0
    )
    if [[ $pending != 0 ]]; then
      return 0
    fi
  done
  return 1
}

while :; do
  for sha in "${candidates[@]}"; do
    if try_sha "$sha"; then
      printf '%s\n' "$sha"
      exit 0
    fi
  done
  if ((max_wait == 0)); then
    echo "release_fetch_manifest_artifacts: no SPK artifacts for candidates" >&2
    exit 1
  fi
  if ((elapsed > max_wait)); then
    echo "release_fetch_manifest_artifacts: timed out" >&2
    exit 1
  fi
  if ! any_in_flight; then
    echo "release_fetch_manifest_artifacts: no successful CI and nothing in flight" >&2
    exit 1
  fi
  sleep "$poll"
  elapsed=$((elapsed + poll))
done