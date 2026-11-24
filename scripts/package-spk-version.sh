#!/usr/bin/env bash
# Read overlay SPK version (SPK_VERS-SPK_REV) for supported packages.
set -euo pipefail

usage() {
  cat <<'EOF'
用法: package-spk-version.sh <openlist|easytier>

输出一行版本号，例如 4.2.10-3 或 2.7.0-10。
EOF
}

pkg=${1:-}
case "$pkg" in
openlist)
  makefile=packages/openlist/overlay/spk/openlist/Makefile
  ;;
easytier)
  makefile=packages/easytier/overlay/spk/EasyTier/Makefile
  ;;
*)
  usage >&2
  exit 2
  ;;
esac

vers=$(sed -nE 's/^SPK_VERS = (.*)$/\1/p' "$makefile" | head -1)
rev=$(sed -nE 's/^SPK_REV = (.*)$/\1/p' "$makefile" | head -1)
[[ -n $vers && -n $rev ]] || {
  echo "package-spk-version: cannot read SPK_VERS/SPK_REV from $makefile" >&2
  exit 1
}
printf '%s-%s\n' "$vers" "$rev"