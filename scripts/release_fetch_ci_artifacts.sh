#!/usr/bin/env bash
# Fetch SPK artifacts from synology-packages-ci for SHA; require SPK job + files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
sha=${1:-}
dest=${2:-}
manifest=${3:-${RELEASE_MANIFEST:-}}
[[ -n $sha && -n $dest ]] || {
  echo "usage: release_fetch_ci_artifacts.sh <sha> <dest-dir> [manifest.json]" >&2
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

spk_job=${RELEASE_CI_SPK_JOB:-}
pkg=""
primary_spk=""
extra_assets=""
if [[ -n $manifest && -f $manifest ]]; then
  # shellcheck source=scripts/release-common.sh
  source "$ROOT/scripts/release-common.sh"
  pkg=$(release_manifest_field "$manifest" package)
  primary_spk=$(release_manifest_field "$manifest" primary_spk)
  extra_assets=$(release_manifest_field "$manifest" extra_assets)
  if [[ -z $spk_job ]]; then
    spk_job=$(bash "$ROOT/scripts/release-ci-sha.sh" job-name "$pkg")
  fi
fi

workflow=${RELEASE_CI_WORKFLOW:-synology-packages-ci}
max_wait=${RELEASE_CI_WAIT_SEC:-7200}
poll=${RELEASE_CI_POLL_SEC:-60}
elapsed=0
run_id=""

while :; do
  run_id=$(
    gh run list --workflow="$workflow" --commit="$sha" --limit 20 \
      --json databaseId,status,conclusion \
      -q '[.[] | select(.status=="completed" and .conclusion=="success")] | .[0].databaseId // empty'
  )
  if [[ -n $run_id ]]; then
    break
  fi
  if ((max_wait == 0)); then
    echo "release_fetch_ci_artifacts: no successful CI for $sha (no wait)" >&2
    exit 1
  fi
  if ((elapsed > max_wait)); then
    echo "release_fetch_ci_artifacts: timed out waiting for CI on $sha" >&2
    exit 1
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

if [[ -n $spk_job ]]; then
  job_conclusion=$(
    gh run view "$run_id" --json jobs \
      -q ".jobs[] | select(.name==\"${spk_job}\") | .conclusion"
  )
  if [[ $job_conclusion != success ]]; then
    echo "release_fetch_ci_artifacts: job ${spk_job} was not success on run ${run_id} (got: ${job_conclusion:-missing})" >&2
    exit 1
  fi
fi

mkdir -p "$dest"
gh run download "$run_id" --dir "$dest"

verify_spk_present() {
  local name=$1
  [[ -n $name ]] || return 0
  local found
  found=$(find "$dest" -name "$name" -print -quit)
  if [[ -z $found ]]; then
    echo "release_fetch_ci_artifacts: missing SPK file ${name} after download" >&2
    return 1
  fi
}

if [[ -n $primary_spk ]]; then
  verify_spk_present "$primary_spk"
  while IFS= read -r extra; do
    [[ -n $extra ]] || continue
    verify_spk_present "$extra"
  done <<<"$extra_assets"
fi

exit 0