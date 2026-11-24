#!/usr/bin/env bash
# Open or refresh a per-package release PR (branch release/<pkg>-next).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/release-common.sh
source "$ROOT/scripts/release-common.sh"
# shellcheck source=scripts/release-ci-sha.sh
source "$ROOT/scripts/release-ci-sha.sh"

lock=$(git rev-parse --absolute-git-dir)/release-next.lock
exec 9>"$lock"
command -v flock >/dev/null 2>&1 || release_die "需要 flock"
flock 9

plan_out=$(mktemp)
notes_out=$(mktemp)
trap 'rm -f "$plan_out" "$notes_out"' EXIT

bash "$ROOT/scripts/release_plan.sh" \
  --github-output "$plan_out" \
  --notes "$notes_out"

mode="" pkg="" version="" tag="" branch=""
while IFS= read -r line; do
  key=${line%%=*}
  val=${line#*=}
  case "$key" in
  mode) mode=$val ;;
  pkg) pkg=$val ;;
  version) version=$val ;;
  tag) tag=$val ;;
  branch) branch=$val ;;
  esac
done <"$plan_out"

release_info "mode=${mode} pkg=${pkg} tag=${tag}"
if [[ $mode != prepare ]]; then
  release_info "不打开 release PR"
  exit 0
fi

[[ -n $pkg && -n $version && -n $tag && -n $branch ]] \
  || release_die "prepare 缺少 pkg/version/tag/branch"

origin_url=$(git remote get-url origin 2>/dev/null || true)
case "$origin_url" in
*synology-packages*)
  [[ ${GITHUB_ACTIONS:-} == true ]] || release_die "拒绝在 Actions 之外推送到本仓库"
  ;;
esac
[[ ${RELEASE_ALLOW_PUSH:-} == 1 ]] || release_die "缺少 RELEASE_ALLOW_PUSH=1"

rev=${RELEASE_REV:-HEAD}
base=${RELEASE_BASE:-master}
git rev-parse --verify --quiet "$rev" >/dev/null || release_die "找不到 $rev"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if [[ ${RELEASE_FETCH_TAGS:-} == 1 ]]; then
  git fetch origin "refs/heads/${branch}:refs/remotes/origin/${branch}" || true
fi

open_or_refresh_pr() {
  local title=$1
  command -v gh >/dev/null 2>&1 || release_die "未找到 gh"
  export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  [[ -n ${GH_TOKEN:-} ]] || release_die "缺少 GH_TOKEN"
  local pr
  pr=$(
    gh pr list --head "$branch" --base "$base" --state open \
      --json number -q '.[0].number // empty'
  )
  if [[ -n $pr ]]; then
    gh pr edit "$pr" --title "$title" --body-file "$notes_out"
    gh pr view "$pr" --json url -q .url
  else
    gh pr create --base "$base" --head "$branch" \
      --title "$title" --body-file "$notes_out" --draft
  fi
}

title="chore(release): publish ${pkg} ${version}"
ci_sha=$(release_resolve_ci_sha "$pkg" "$rev")
preserve_from=""

if git show-ref --verify --quiet "refs/remotes/origin/${branch}"; then
  existing_manifest=$(mktemp)
  if git show "refs/remotes/origin/${branch}:.release/${tag}.json" >"$existing_manifest" 2>/dev/null; then
    same=$(
      node - "$existing_manifest" "$pkg" "$version" "$tag" <<'NODE'
const fs = require('fs');
const [, , path, pkg, version, tag] = process.argv;
const m = JSON.parse(fs.readFileSync(path, 'utf8'));
process.stdout.write(
  m.package === pkg && m.version === version && m.tag === tag ? 'yes' : 'no',
);
NODE
    )
    if [[ $same == yes ]]; then
      old_ci=$(release_manifest_ci_sha "$existing_manifest")
      if ! release_spk_paths_changed "$old_ci" "$rev" "$pkg"; then
        git checkout -B "$branch" "origin/${branch}"
        open_or_refresh_pr "$title"
        exit 0
      fi
      git checkout -B "$branch" "origin/${branch}"
      ci_sha=$(release_resolve_ci_sha "$pkg" "$rev")
      preserve_from=$existing_manifest
    else
      git checkout -B "$branch" "$rev"
    fi
  else
    git checkout -B "$branch" "$rev"
  fi
else
  git checkout -B "$branch" "$rev"
fi

ci_head=$(git rev-parse "$rev")
manifest_args=("$pkg" "$version" "$tag" "$ci_sha")
manifest_args+=(--ci-head "$ci_head")
if [[ -n $preserve_from ]]; then
  manifest_args+=(--preserve-from "$preserve_from")
fi
node "$ROOT/scripts/write-release-manifest.mjs" "${manifest_args[@]}"

git add -- ".release/${tag}.json"

if RELEASE_CI_WAIT_SEC=0 bash "$ROOT/scripts/release_try_catalog_update.sh" "$tag"; then
  git add -- docs/packages.json
else
  release_info "CI 构件尚不可用；PR 仅含 manifest"
fi
git add -- ".release/${tag}.json"

commit_file=$(mktemp)
{
  printf '%s\n\n' "$title"
  cat "$notes_out"
} >"$commit_file"
git commit -F "$commit_file"
rm -f "$commit_file"

if git show-ref --verify --quiet "refs/remotes/origin/${branch}"; then
  git push \
    --force-with-lease="refs/heads/${branch}:refs/remotes/origin/${branch}" \
    origin "HEAD:refs/heads/${branch}"
else
  git push -u origin "HEAD:refs/heads/${branch}"
fi

open_or_refresh_pr "$title"