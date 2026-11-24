#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/release-common.sh
source "$ROOT/scripts/release-common.sh"

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

openlist_ver=$(read_catalog_version openlist)
[[ $openlist_ver == "4.2.10-3" ]] || {
  echo "read_catalog_version openlist: expected 4.2.10-3 got ${openlist_ver}" >&2
  exit 1
}
easytier_ver=$(read_catalog_version EasyTier)
[[ $easytier_ver == "2.7.0-10" ]] || {
  echo "read_catalog_version EasyTier: expected 2.7.0-10 got ${easytier_ver}" >&2
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

echo "release_plan_test: ok"