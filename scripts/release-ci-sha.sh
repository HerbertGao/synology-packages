#!/usr/bin/env bash
# Resolve CI commits and path-filter paths for SPK artifacts (matches ci.yml filters).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/release-common.sh
source "$ROOT/scripts/release-common.sh"

# Paths that enable the package SPK job in synology-packages-ci (see .github/workflows/ci.yml).
release_pkg_spk_paths() {
  local pkg=$1
  case "$pkg" in
  openlist)
    printf '%s\n' \
      packages/openlist \
      scripts/build-openlist.sh \
      scripts/apply-overlay.sh \
      scripts/patch-spksrc-local-publisher.sh \
      .github/workflows/ci.yml
    ;;
  easytier)
    printf '%s\n' \
      packages/easytier \
      scripts/build-easytier.sh \
      scripts/report-easytier-spk-artifacts.sh \
      scripts/test-easytier-glibc-max.sh \
      scripts/apply-overlay.sh \
      scripts/patch-spksrc-local-publisher.sh \
      .github/workflows/ci.yml
    ;;
  *)
    release_die "unknown package: $pkg"
    ;;
  esac
}

release_spk_job_name() {
  case "$1" in
  openlist) printf 'spk-build\n' ;;
  easytier) printf 'easytier-spk-build\n' ;;
  *) return 1 ;;
  esac
}

# Latest ancestor of $rev (inclusive) that touches SPK path-filter paths.
release_resolve_ci_sha() {
  local pkg=$1 rev=$2
  local -a paths=()
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    paths+=("$line")
  done < <(release_pkg_spk_paths "$pkg")

  local sha
  sha=$(git log -1 --format=%H "$rev" -- "${paths[@]}" 2>/dev/null || true)
  [[ -n $sha ]] || release_die "无法在 ${rev} 的历史中找到触及 ${pkg} SPK 路径的提交"
  printf '%s\n' "$sha"
}

# True (exit 0) if any SPK-filter path differs between from_sha and to_sha.
release_spk_paths_changed() {
  local from_sha=$1 to_sha=$2 pkg=$3
  local -a paths=()
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    paths+=("$line")
  done < <(release_pkg_spk_paths "$pkg")
  [[ -n $(git diff --name-only "${from_sha}..${to_sha}" -- "${paths[@]}") ]]
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  case ${1:-} in
  resolve)
    release_resolve_ci_sha "$2" "${3:-HEAD}"
    ;;
  job-name)
    release_spk_job_name "$2"
    ;;
  *)
    echo "usage: release-ci-sha.sh resolve <pkg> [rev] | job-name <pkg>" >&2
    exit 2
    ;;
  esac
fi