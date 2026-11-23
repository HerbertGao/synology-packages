#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="${ROOT}/.build/verify-easytier"
mkdir -p "${TMP}"

ROOT="${ROOT}" python3 <<'PY'
import hashlib
import json
import os
import sys
import urllib.request

root = os.environ["ROOT"]
lock_path = os.path.join(root, "packages/easytier/upstream.lock.json")
tmp = os.path.join(root, ".build/verify-easytier")
os.makedirs(tmp, exist_ok=True)

with open(lock_path, encoding="utf-8") as f:
    data = json.load(f)

def digest(path):
    h = {"md5": hashlib.md5(), "sha1": hashlib.sha1(), "sha256": hashlib.sha256()}
    with open(path, "rb") as rf:
        for chunk in iter(lambda: rf.read(1024 * 1024), b""):
            for algo in h.values():
                algo.update(chunk)
    return {k: v.hexdigest() for k, v in h.items()}

key = "easytier_linux_x86_64"
meta = data["artifacts"][key]
out = os.path.join(tmp, meta["dist_file"])
print(f"Downloading {meta['url']}")
urllib.request.urlretrieve(meta["url"], out)
got = digest(out)
for algo in ("md5", "sha1", "sha256"):
    expected = meta[algo]
    if got[algo] != expected:
        print(f"FAIL {key} {algo}: expected {expected}, got {got[algo]}", file=sys.stderr)
        sys.exit(1)
print(f"OK {key} digests match upstream.lock.json")

overlay_digest = os.path.join(root, "packages/easytier/overlay/cross/easytier/digests")
text = open(overlay_digest, encoding="utf-8").read()
file_name = meta["dist_file"]
for algo in ("MD5", "SHA1", "SHA256"):
    expected = meta[algo.lower()]
    if f"{file_name} {algo} {expected}" not in text:
        print(f"FAIL overlay digests missing {algo}", file=sys.stderr)
        sys.exit(1)
print("OK overlay digests file aligned with lock")
PY