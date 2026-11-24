#!/usr/bin/env bash
# Create tag + GitHub Release (prerelease by default) and verify catalog fields.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/release-common.sh
source "$ROOT/scripts/release-common.sh"

plan_out=$(mktemp)
trap 'rm -f "$plan_out"' EXIT
bash "$ROOT/scripts/release_plan.sh" --github-output "$plan_out"

mode="" pkg="" version="" tag=""
while IFS= read -r line; do
  key=${line%%=*}
  val=${line#*=}
  case "$key" in
  mode) mode=$val ;;
  pkg) pkg=$val ;;
  version) version=$val ;;
  tag) tag=$val ;;
  esac
done <"$plan_out"

if [[ $mode != publish ]]; then
  release_info "publish 跳过 (mode=$mode)"
  exit 0
fi

[[ -n $tag ]] || release_die "publish 缺少 tag"

if [[ -z $pkg || -z $version ]]; then
  case "$tag" in
  openlist-*)
    pkg=openlist
    version=${tag#openlist-}
    ;;
  easytier-*)
    pkg=easytier
    version=${tag#easytier-}
    ;;
  *)
    release_die "无法从 tag 解析套件: $tag"
    ;;
  esac
fi

manifest="${ROOT}/.release/${tag}.json"
[[ -f $manifest ]] || release_die "缺少 manifest: $manifest"

[[ ${RELEASE_ALLOW_PUSH:-} == 1 ]] || release_die "缺少 RELEASE_ALLOW_PUSH=1"

work=$(mktemp -d)
trap 'rm -f "$plan_out"; rm -rf "$work"' EXIT

artifact_sha=$(release_manifest_ci_sha "$manifest") \
  || release_die "manifest 缺少 ci_sha"
RELEASE_MANIFEST=$manifest
bash "$ROOT/scripts/release_fetch_ci_artifacts.sh" "$artifact_sha" "$work" "$manifest"

tag_sha=${RELEASE_REV:-HEAD}

prerelease=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).prerelease!==false?'true':'false')" "$manifest")
make_latest=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1]));console.log(m.make_latest===true?'true':'false')" "$manifest")

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if ! tag_exists_full "$tag"; then
  git tag -a "$tag" -m "Release ${tag}" "$tag_sha"
  git push origin "refs/tags/${tag}"
else
  release_info "tag ${tag} 已存在，跳过创建"
fi

command -v gh >/dev/null 2>&1 || release_die "需要 gh"
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

primary_spk=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).primary_spk)" "$manifest")
extra_assets=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1]));console.log((m.extra_assets||[]).join('\n'))" "$manifest")

shopt -s nullglob
assets=()
for name in "$primary_spk" $extra_assets; do
  [[ -n $name ]] || continue
  found=$(find "$work" -name "$name" -print -quit)
  [[ -n $found ]] || release_die "找不到构件 $name"
  assets+=("$found")
done

if gh release view "$tag" >/dev/null 2>&1; then
  release_info "Release $tag 已存在，仅上传缺失资产（不改为 latest / stable）"
  gh release upload "$tag" "${assets[@]}" --clobber
else
  args=(
    gh release create "$tag" "${assets[@]}" --title "$tag"
    --latest=false
  )
  if [[ $prerelease == true ]]; then
    args+=(--prerelease)
  fi
  args+=(--notes "Automated SPK release for $(release_catalog_name "$pkg") ${version}. Catalog JSON is on master.")
  "${args[@]}"
fi

if [[ $make_latest == true ]]; then
  release_info "manifest 请求 make_latest=true，但默认禁止；请维护者手动标记 latest"
fi

release_info "publish 完成: $tag (prerelease=$prerelease)"