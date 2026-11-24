#!/usr/bin/env bash
# Shared helpers for release automation (sourced, not executed).

release_die() {
  printf 'release: %s\n' "$1" >&2
  exit "${2:-1}"
}

release_info() {
  printf 'release: %s\n' "$*" >&2
}

# Normalize package slug: openlist | easytier
release_normalize_pkg() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
  openlist) printf 'openlist\n' ;;
  easytier) printf 'easytier\n' ;;
  *)
    return 1
    ;;
  esac
}

# Catalog JSON "package" field (case-sensitive for DSM).
release_catalog_name() {
  case "$1" in
  openlist) printf 'openlist\n' ;;
  easytier) printf 'EasyTier\n' ;;
  *) return 1 ;;
  esac
}

release_tag_prefix() {
  case "$1" in
  openlist | easytier) printf '%s\n' "$1" ;;
  *) return 1 ;;
  esac
}

# Print tag, e.g. openlist-4.2.10-3
release_tag_for() {
  local pkg=$1 ver=$2
  printf '%s-%s\n' "$(release_tag_prefix "$pkg")" "$ver"
}

# Compare X.Y.Z-R: prints -1, 0, or 1.
release_cmp_spk_version() {
  local a=$1 b=$2
  [[ $a == *-* && $b == *-* ]] || return 2
  local a_vers=${a%-*} a_rev=${a##*-}
  local b_vers=${b%-*} b_rev=${b##*-}
  [[ $a_rev =~ ^[0-9]+$ && $b_rev =~ ^[0-9]+$ ]] || return 2
  if [[ $a_vers == "$b_vers" ]]; then
    if [ "$((10#$a_rev))" -lt "$((10#$b_rev))" ]; then
      echo -1
    elif [ "$((10#$a_rev))" -gt "$((10#$b_rev))" ]; then
      echo 1
    else
      echo 0
    fi
    return 0
  fi
  if printf '%s\n' "$a_vers" "$b_vers" | sort -V | head -1 | grep -qxF "$a_vers"; then
    echo -1
  else
    echo 1
  fi
}

is_releasable_subject() {
  [[ $1 =~ ^(feat|fix)(\([A-Za-z0-9._/-]+\))?(!)?:[[:space:]].+ ]]
}

package_path_glob() {
  case "$1" in
  openlist) printf 'packages/openlist/\n' ;;
  easytier) printf 'packages/easytier/\n' ;;
  *) return 1 ;;
  esac
}

# Parse chore(release): publish openlist 4.2.10-4
release_version_from_text() {
  printf '%s\n' "$1" | sed -nE \
    's/^chore\(release\): publish (openlist|easytier) ([0-9]+(\.[0-9]+)*-[0-9]+)( \(#[0-9]+\))?[[:space:]]*$/\2 \1/p' |
    awk 'NR == 1 { print }'
}

tag_exists_full() {
  git show-ref --verify --quiet "refs/tags/$1"
}

read_catalog_version() {
  local catalog_pkg=$1
  node - "$catalog_pkg" <<'NODE'
const fs = require('fs');
const catalogPkg = process.argv[1];
const doc = JSON.parse(fs.readFileSync('docs/packages.json', 'utf8'));
const row = doc.packages.find((p) => p.package === catalogPkg);
if (!row) process.exit(2);
process.stdout.write(row.version);
NODE
}