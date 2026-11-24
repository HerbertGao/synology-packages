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
  easytier 2.7.0-11 easytier-2.7.0-11 cafebabe "$fixture_root"
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
  --preserve-from "$manifest"
prerelease=$(
  node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).prerelease)" \
    "${fixture_root}/.release/easytier-2.7.0-11.json"
)
[[ $prerelease == true ]] || {
  echo "preserve prerelease expected true got $prerelease" >&2
  exit 1
}

resolved_ci=$(bash "$ROOT/scripts/release-ci-sha.sh" resolve easytier HEAD)
[[ -n $resolved_ci ]] || {
  echo "release_resolve_ci_sha returned empty" >&2
  exit 1
}
git merge-base --is-ancestor "$resolved_ci" HEAD

openlist_make=$(bash "$ROOT/scripts/package-spk-version.sh" openlist)
if RELEASE_EVENT=workflow_dispatch RELEASE_EXPLICIT_VERSION="openlist/0.0.0-0" \
  bash "$ROOT/scripts/release_plan.sh" >/dev/null 2>&1; then
  echo "expected failure for explicit version != Makefile" >&2
  exit 1
fi
if RELEASE_EVENT=workflow_dispatch RELEASE_EXPLICIT_VERSION="openlist/${openlist_make}" \
  bash "$ROOT/scripts/release_plan.sh" >/dev/null 2>&1; then
  echo "expected failure for dispatch when catalog not behind Makefile" >&2
  exit 1
fi

echo "release_plan_test: ok"