#!/usr/bin/env bash
# Decide prepare (open release PR), publish (tag + Release + catalog), or skip.
# Synology-packages: per-package tags openlist-VERSION, easytier-VERSION.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/release-common.sh
source "$ROOT/scripts/release-common.sh"

usage() {
  cat <<'EOF'
用法: scripts/release_plan.sh [--rev REF] [--github-output FILE] [--notes FILE]

环境变量：RELEASE_EVENT、RELEASE_REF、RELEASE_EXPLICIT_VERSION、RELEASE_FETCH_TAGS。
只读 git / docs/packages.json，不推送、不打 tag。
EOF
}

ancestor_tag_for_pkg() {
  local pkg=$1 rev=$2 prefix
  prefix=$(release_tag_prefix "$pkg")
  git describe --tags --match "${prefix}-*" --abbrev=0 "$rev" 2>/dev/null || true
}

collect_releasable_subjects() {
  local range=$1 path=$2
  [[ -n $range ]] || return 0
  git log --reverse --format='%s' "$range" -- "$path" | while IFS= read -r subject; do
    [[ -n $subject ]] || continue
    if is_releasable_subject "$subject"; then
      printf '%s\n' "$subject"
    fi
  done
}

build_prepare_notes() {
  local pkg=$1 version=$2 tag=$3 prerelease=$4
  shift 4
  local -a subjects=("$@")
  local bullets="" item
  if ((${#subjects[@]} > 0)); then
    for item in "${subjects[@]}"; do
      bullets+="- ${item}"$'\n'
    done
    bullets=${bullets%$'\n'}
  else
    bullets="（自上一 tag 以来没有新的 \`feat\` / \`fix\` 提交触及该套件 overlay。）"
  fi
  local flag_note="本版本默认为 **GitHub prerelease**（非 latest/stable）。"
  if [[ $prerelease != true ]]; then
    flag_note="维护者在 manifest 中指定 **stable/latest**；合并前请确认。"
  fi
  cat <<EOF
## Release \`${tag}\`

本 PR 由 \`master\` 上尚未发布的 \`feat\` / \`fix\`（路径 \`$(package_path_glob "$pkg")\`）自动打开或更新。合并到 \`master\` 时请保留标题 \`chore(release): publish ${pkg} ${version}\`。

合并后 CI 会：

1. 复用 **synology-packages-ci** 在该提交上的 SPK 构件（或在本 workflow 内重建）
2. 创建 annotated tag \`${tag}\`（若尚不存在）
3. 上传 SPK 到 GitHub Release（${flag_note}）
4. 仅更新 \`docs/packages.json\` 中 **$(release_catalog_name "$pkg")** 条目（version / link / md5 / sha256 / size），不改动其它套件

**不会**在 NAS 上安装、不会 SSH 生产、不会改写已存在 Release 的 prerelease/stable 状态。

### 变更摘要

${bullets}

### Manifest

\`.release/${tag}.json\` 记录 tag、版本与 prerelease 默认值。维护者可编辑 PR 中该文件以覆盖 \`prerelease\` / \`make_latest\`（默认均为 prerelease 且非 latest）。

### 合并后 Pages

\`docs/packages.json\` 合入 \`master\` 后由 GitHub Pages 发布；Location 仍为 \`https://herbertgao.com/synology-packages/packages.json\`。
EOF
}

fix_set_plan() {
  PLAN_MODE=$1
  PLAN_PKG=$2
  PLAN_VERSION=$3
  PLAN_TAG=$4
  PLAN_BRANCH=$5
  PLAN_REASON=$6
  PLAN_NOTES=$7
}

decide_for_publish_commit() {
  local rev=$1 message=$2 parsed pkg version tag
  parsed=$(release_version_from_text "$message" || true)
  [[ -n $parsed ]] || return 1
  read -r version pkg <<<"$parsed"
  release_normalize_pkg "$pkg" >/dev/null || release_die "未知套件: $pkg"
  pkg=$(release_normalize_pkg "$pkg")
  tag=$(release_tag_for "$pkg" "$version")
  if tag_exists_full "$tag"; then
    fix_set_plan skip "$pkg" "$version" "$tag" "release/${pkg}-next" \
      skip:tag-exists ""
    return 0
  fi
  if [[ ${RELEASE_EVENT:-push} == workflow_dispatch ]]; then
    fix_set_plan skip "$pkg" "$version" "$tag" "release/${pkg}-next" \
      skip:dispatch-no-publish ""
    return 0
  fi
  fix_set_plan publish "$pkg" "$version" "$tag" "release/${pkg}-next" \
    publish:release-commit ""
  return 0
}

decide_prepare_for_pkg() {
  local rev=$1 pkg=$2 explicit_version=$3
  local makefile_ver catalog_ver cmp tag ancestor range
  local -a subjects=()

  makefile_ver=$(bash "$ROOT/scripts/package-spk-version.sh" "$pkg")
  catalog_ver=$(read_catalog_version "$(release_catalog_name "$pkg")")
  cmp=$(release_cmp_spk_version "$makefile_ver" "$catalog_ver") \
    || release_die "无法比较 Makefile $makefile_ver 与目录 $catalog_ver"
  if [[ $cmp != 1 ]]; then
    fix_set_plan skip "$pkg" "$makefile_ver" "" "release/${pkg}-next" \
      skip:catalog-up-to-date ""
    return 0
  fi

  tag=$(release_tag_for "$pkg" "$makefile_ver")
  if tag_exists_full "$tag"; then
    fix_set_plan skip "$pkg" "$makefile_ver" "$tag" "release/${pkg}-next" \
      skip:tag-exists ""
    return 0
  fi

  ancestor=$(ancestor_tag_for_pkg "$pkg" "$rev")
  if [[ -n $ancestor ]]; then
    range="${ancestor}..${rev}"
    while IFS= read -r line; do
      [[ -n $line ]] || continue
      subjects+=("$line")
    done < <(collect_releasable_subjects "$range" "$(package_path_glob "$pkg")")
  fi

  if [[ -z $explicit_version && ${#subjects[@]} -eq 0 ]]; then
    fix_set_plan skip "$pkg" "$makefile_ver" "$tag" "release/${pkg}-next" \
      skip:no-releasable ""
    return 0
  fi

  local version=$makefile_ver
  if [[ -n $explicit_version ]]; then
    version=$explicit_version
    tag=$(release_tag_for "$pkg" "$version")
  fi

  PLAN_NOTES=$(build_prepare_notes "$pkg" "$version" "$tag" true "${subjects[@]}")
  fix_set_plan prepare "$pkg" "$version" "$tag" "release/${pkg}-next" \
    prepare:releasable "$PLAN_NOTES"
}

decide_release_plan() {
  local rev=$1 ref=$2 event=$3 explicit=$4
  local message parsed

  if [[ $ref == refs/tags/* ]]; then
    local tag=${ref#refs/tags/}
    case "$tag" in
    openlist-* | easytier-*)
      fix_set_plan publish "" "" "$tag" "" publish:tag-push ""
      return 0
      ;;
    esac
    fix_set_plan skip "" "" "" "" skip:foreign-tag ""
    return 0
  fi

  message=$(git log -1 --format='%B' "$rev")
  if decide_for_publish_commit "$rev" "$message"; then
    return 0
  fi

  if [[ $event == workflow_dispatch && -n $explicit ]]; then
    local pkg ver
    read -r pkg ver <<<"$explicit" || true
    if [[ $explicit == */* ]]; then
      pkg=${explicit%%/*}
      ver=${explicit#*/}
    fi
    release_normalize_pkg "$pkg" >/dev/null || release_die "显式版本需为 openlist/VERS 或 easytier/VERS"
    pkg=$(release_normalize_pkg "$pkg")
    decide_prepare_for_pkg "$rev" "$pkg" "$ver"
    return 0
  fi

  # Default: evaluate openlist then easytier; first package needing prepare wins.
  # If multiple need release, maintainer merges one PR at a time.
  local pkg
  for pkg in openlist easytier; do
    decide_prepare_for_pkg "$rev" "$pkg" ""
    if [[ $PLAN_MODE == prepare ]]; then
      return 0
    fi
  done
  fix_set_plan skip "" "" "" release/next skip:no-package-pending ""
}

write_plan() {
  local dest=$1
  local content
  content=$(
    printf 'mode=%s\npkg=%s\nversion=%s\ntag=%s\nbranch=%s\nreason=%s\n' \
      "${PLAN_MODE:-skip}" "${PLAN_PKG:-}" "${PLAN_VERSION:-}" \
      "${PLAN_TAG:-}" "${PLAN_BRANCH:-}" "${PLAN_REASON:-skip:none}"
  )
  if [[ -n $dest ]]; then
    printf '%s\n' "$content" >>"$dest"
  else
    printf '%s\n' "$content"
  fi
}

main() {
  set -euo pipefail
  local rev="${RELEASE_REV:-HEAD}"
  local output="" notes_path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --rev)
      rev=$2
      shift 2
      ;;
    --github-output)
      output=$2
      shift 2
      ;;
    --notes)
      notes_path=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      release_die "未知参数: $1" 2
      ;;
    esac
  done

  local event=${RELEASE_EVENT:-push}
  local ref=${RELEASE_REF:-refs/heads/master}

  if [[ ${RELEASE_FETCH_TAGS:-} == 1 ]]; then
    git fetch --tags --force origin
  fi

  decide_release_plan "$rev" "$ref" "$event" "${RELEASE_EXPLICIT_VERSION:-}"
  write_plan "$output"
  if [[ -n $notes_path && -n ${PLAN_NOTES:-} ]]; then
    printf '%s\n' "$PLAN_NOTES" >"$notes_path"
  fi
  release_info "${PLAN_MODE:-skip} pkg=${PLAN_PKG:-} ${PLAN_VERSION:-} ${PLAN_REASON:-}"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi