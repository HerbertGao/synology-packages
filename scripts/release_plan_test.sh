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

echo "release_plan_test: ok"