#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/release-common.sh
source "$ROOT/scripts/release-common.sh"
# shellcheck source=scripts/release-ci-sha.sh
source "$ROOT/scripts/release-ci-sha.sh"

test_cmp() {
  local got
  got=$(release_cmp_spk_version "$1" "$2") || return 1
  [[ $got == "$3" ]] || {
    echo "cmp $1 vs $2 expected $3 got $got" >&2
    return 1
  }
}

test_cmp "4.2.10-3" "4.2.10-3" 0
test_cmp "4.2.10-4" "4.2.10-3" 1
test_cmp "4.2.10-3" "4.2.10-4" -1
test_cmp "2.7.0-10" "2.7.0-9" 1

msg='chore(release): publish easytier 2.7.0-11'
parsed=$(release_version_from_text "$msg")
[[ $parsed == "2.7.0-11 easytier" ]] || {
  echo "parse failed: $parsed" >&2
  exit 1
}

catalog_pkg_version() {
  node - "$1" <<'NODE'
const fs = require('fs');
const name = process.argv[2];
const row = JSON.parse(fs.readFileSync('docs/packages.json', 'utf8')).packages
  .find((p) => p.package === name);
if (!row) process.exit(2);
process.stdout.write(row.version);
NODE
}

openlist_expected=$(catalog_pkg_version openlist)
openlist_ver=$(read_catalog_version openlist)
[[ $openlist_ver == "$openlist_expected" ]] || {
  echo "read_catalog_version openlist: expected ${openlist_expected} got ${openlist_ver}" >&2
  exit 1
}
easytier_expected=$(catalog_pkg_version EasyTier)
easytier_ver=$(read_catalog_version EasyTier)
[[ $easytier_ver == "$easytier_expected" ]] || {
  echo "read_catalog_version EasyTier: expected ${easytier_expected} got ${easytier_ver}" >&2
  exit 1
}

fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT
node "$ROOT/scripts/write-release-manifest.mjs" \
  easytier 2.7.0-11 easytier-2.7.0-11 cafebabe "$fixture_root" \
  --ci-head feedface
manifest="${fixture_root}/.release/easytier-2.7.0-11.json"
[[ -f $manifest ]] || {
  echo "manifest not written" >&2
  exit 1
}
node - "$manifest" <<'NODE'
const fs = require('fs');
const m = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const required = {
  package: 'easytier',
  catalog_package: 'EasyTier',
  version: '2.7.0-11',
  tag: 'easytier-2.7.0-11',
  ci_sha: 'cafebabe',
  ci_head: 'feedface',
  prerelease: true,
  make_latest: false,
};
for (const [k, v] of Object.entries(required)) {
  if (m[k] !== v) {
    console.error(`manifest ${k}: expected ${v}, got ${m[k]}`);
    process.exit(1);
  }
}
NODE

sha=$(release_manifest_ci_sha "$manifest")
[[ $sha == "cafebabe" ]] || {
  echo "release_manifest_ci_sha: expected cafebabe got ${sha}" >&2
  exit 1
}

mapfile -t candidates < <(release_manifest_artifact_candidates "$manifest")
[[ ${#candidates[@]} -eq 2 ]] || {
  echo "expected 2 artifact candidates got ${#candidates[@]}" >&2
  exit 1
}
[[ ${candidates[0]} == cafebabe && ${candidates[1]} == feedface ]] || {
  echo "unexpected candidates: ${candidates[*]}" >&2
  exit 1
}

pkg_field=$(release_manifest_field "$manifest" package)
[[ $pkg_field == easytier ]] || {
  echo "release_manifest_field package: expected easytier got ${pkg_field}" >&2
  exit 1
}
primary_field=$(release_manifest_field "$manifest" primary_spk)
[[ $primary_field == "EasyTier_apollolake-7.3_2.7.0-11.spk" ]] || {
  echo "release_manifest_field primary_spk unexpected: ${primary_field}" >&2
  exit 1
}

node "$ROOT/scripts/write-release-manifest.mjs" \
  easytier 2.7.0-11 easytier-2.7.0-11 deadbeef "$fixture_root" \
  --preserve-from "$manifest" --ci-head newhead
prerelease=$(
  node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).prerelease)" \
    "${fixture_root}/.release/easytier-2.7.0-11.json"
)
[[ $prerelease == true ]] || {
  echo "preserve prerelease expected true got $prerelease" >&2
  exit 1
}
head_after=$(
  node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).ci_head)" \
    "${fixture_root}/.release/easytier-2.7.0-11.json"
)
[[ $head_after == newhead ]] || {
  echo "expected ci_head newhead got ${head_after}" >&2
  exit 1
}

resolved_ci=$(bash "$ROOT/scripts/release-ci-sha.sh" resolve easytier HEAD)
[[ -n $resolved_ci ]] || {
  echo "release_resolve_ci_sha returned empty" >&2
  exit 1
}
git merge-base --is-ancestor "$resolved_ci" HEAD

plan_test_rev=$(
  git log -1 --format=%H --grep='^chore(release): publish ' --invert-grep
)
[[ -n $plan_test_rev ]] || {
  echo "no commit without release-publish subject for dispatch tests" >&2
  exit 1
}

run_dispatch_plan() {
  local explicit=$1
  local plan_out
  plan_out=$(mktemp)
  set +e
  RELEASE_REV="$plan_test_rev" RELEASE_EVENT=workflow_dispatch \
    RELEASE_EXPLICIT_VERSION="$explicit" \
    bash "$ROOT/scripts/release_plan.sh" --github-output "$plan_out" 2>/dev/null
  local rc=$?
  set -e
  if [[ -f $plan_out ]]; then
    cat "$plan_out"
  fi
  rm -f "$plan_out"
  return "$rc"
}

openlist_make=$(bash "$ROOT/scripts/package-spk-version.sh" openlist)
if run_dispatch_plan "openlist/0.0.0-0" >/dev/null; then
  echo "expected failure for explicit version != Makefile" >&2
  exit 1
fi

openlist_catalog=$(read_catalog_version openlist)
openlist_cmp=$(release_cmp_spk_version "$openlist_make" "$openlist_catalog")
openlist_tag=$(release_tag_for openlist "$openlist_make")
if [[ $openlist_cmp != 1 ]]; then
  if run_dispatch_plan "openlist/${openlist_make}" >/dev/null 2>&1; then
    echo "expected dispatch failure when Makefile not ahead of catalog" >&2
    exit 1
  fi
elif tag_exists_full "$openlist_tag"; then
  if run_dispatch_plan "openlist/${openlist_make}" >/dev/null 2>&1; then
    echo "expected dispatch failure when tag exists" >&2
    exit 1
  fi
else
  plan_lines=$(run_dispatch_plan "openlist/${openlist_make}") || {
    echo "dispatch prepare failed unexpectedly" >&2
    exit 1
  }
  echo "$plan_lines" | grep -q '^mode=prepare' || {
    echo "expected mode=prepare when Makefile ahead and tag missing" >&2
    echo "$plan_lines" >&2
    exit 1
  }
fi

echo "release_plan_test: ok"