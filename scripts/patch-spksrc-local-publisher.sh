#!/usr/bin/env bash
# Ensure spksrc local.mk publisher fields are set (make setup leaves them empty).
set -euo pipefail

LOCAL_MK="${1:?local.mk path required}"
[ -f "${LOCAL_MK}" ] || exit 0

sed -i \
  -e 's/^DISTRIBUTOR =[[:space:]]*$/DISTRIBUTOR = Herbert Gao/' \
  -e 's|^DISTRIBUTOR_URL =[[:space:]]*$|DISTRIBUTOR_URL = https://github.com/HerbertGao/synology-packages|' \
  "${LOCAL_MK}"