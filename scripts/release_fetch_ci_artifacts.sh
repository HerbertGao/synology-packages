#!/usr/bin/env bash
# Fetch SPK artifacts from the latest successful synology-packages-ci run for SHA.
set -euo pipefail

sha=${1:-}
dest=${2:-}
[[ -n $sha && -n $dest ]] || {
  echo "usage: release_fetch_ci_artifacts.sh <sha> <dest-dir>" >&2
  exit 2
}

command -v gh >/dev/null 2>&1 || {
  echo "gh required" >&2
  exit 1
}
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
[[ -n ${GH_TOKEN:-} ]] || {
  echo "GH_TOKEN required" >&2
  exit 1
}

workflow=${RELEASE_CI_WORKFLOW:-synology-packages-ci}
max_wait=${RELEASE_CI_WAIT_SEC:-7200}
poll=${RELEASE_CI_POLL_SEC:-60}
elapsed=0
run_id=""

while ((elapsed <= max_wait)); do
  run_id=$(
    gh run list --workflow="$workflow" --commit="$sha" --limit 20 \
      --json databaseId,status,conclusion \
      -q '[.[] | select(.status=="completed" and .conclusion=="success")] | .[0].databaseId // empty'
  )
  if [[ -n $run_id ]]; then
    break
  fi
  pending=$(
    gh run list --workflow="$workflow" --commit="$sha" --limit 5 \
      --json status -q '[.[] | select(.status!="completed")] | length'
  )
  if [[ $pending == 0 ]]; then
    echo "release_fetch_ci_artifacts: no in-flight CI for $sha" >&2
    exit 1
  fi
  sleep "$poll"
  elapsed=$((elapsed + poll))
done

[[ -n $run_id ]] || {
  echo "release_fetch_ci_artifacts: timed out waiting for CI on $sha" >&2
  exit 1
}

mkdir -p "$dest"
gh run download "$run_id" --dir "$dest"
exit 0