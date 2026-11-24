#!/usr/bin/env bash
# Regression: caphelper k_cap_blob must match DSM 7.3.2 setcap output (LE vfs_cap_data v2).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/packages/easytier/overlay/cross/caphelper/src/caphelper.c"

# cap_net_admin,cap_net_raw+ep from `setcap` on Virtual DSM 7.3.2 (20-byte security.capability).
DSM_GOOD_HEX='0100000200300000000000000000000000000000'
# Prior misread getfattr display order (kernel rejected at exec → EINVAL).
LEGACY_BAD_HEX='02000001000030000000000000000000000000'

if ! grep -q 'k_cap_blob' "${SRC}"; then
  echo "FAIL: caphelper.c missing k_cap_blob" >&2
  exit 1
fi

blob_hex="$(
  sed -n '/static const unsigned char k_cap_blob/,/};/p' "${SRC}" |
    grep -oE '0x[0-9a-fA-F]{2}' |
    tr -d '\n' |
    sed 's/0x//g'
)"

if [ "${#blob_hex}" -ne 40 ]; then
  echo "FAIL: expected 20-byte k_cap_blob (40 hex chars), got len=${#blob_hex}" >&2
  exit 1
fi

if [ "${blob_hex}" != "${DSM_GOOD_HEX}" ]; then
  echo "FAIL: k_cap_blob must match DSM setcap fixture" >&2
  echo " expect=${DSM_GOOD_HEX}" >&2
  echo " got=${blob_hex}" >&2
  exit 1
fi

if [ "${blob_hex}" = "${LEGACY_BAD_HEX}" ]; then
  echo "FAIL: legacy endian-misread cap blob must not return" >&2
  exit 1
fi

# vfs_cap_data: magic_etc LE32 0x02000001 (rev 2 + effective), permitted LE32 0x3000 (12|13).
magic_le="${blob_hex:0:8}"
perm_le="${blob_hex:8:8}"
if [ "${magic_le}" != '01000002' ] || [ "${perm_le}" != '00300000' ]; then
  echo "FAIL: unexpected vfs_cap header layout magic=${magic_le} permitted=${perm_le}" >&2
  exit 1
fi

if ! grep -q 'ensure_tun_world_rw_settled' "${SRC}"; then
  echo "FAIL: caphelper must settle TUN mode after insmod race" >&2
  exit 1
fi

echo "OK EasyTier cap blob (DSM 7.3.2 setcap fixture, 20 bytes LE vfs_cap_data v2)"