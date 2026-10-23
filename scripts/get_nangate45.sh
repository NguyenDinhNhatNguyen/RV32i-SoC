#!/usr/bin/env bash
# get_nangate45.sh - tải liberty mở Nangate45 (typical) cho flow timing ở nhà.
# File nằm trong syn/run_yosys/lib/ (bị .gitignore chặn), không bao giờ commit.
# Nguồn: OpenROAD-flow-scripts, flow/platforms/nangate45. Không phải GPDK45.
#   scripts/get_nangate45.sh [thư mục đích]
set -euo pipefail

dst=${1:-syn/run_yosys/lib}
lib=NangateOpenCellLibrary_typical.lib
url=https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/master/flow/platforms/nangate45/lib/$lib
# sha256 của bản đã dùng cho docs/timing_core.md (23/10/2026)
sum=8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1

mkdir -p "$dst"
if [ ! -f "$dst/$lib" ]; then
    echo "Tai $lib ..."
    curl -sfL -o "$dst/$lib.tmp" "$url"
    mv "$dst/$lib.tmp" "$dst/$lib"
fi
if ! echo "$sum  $dst/$lib" | sha256sum -c --status; then
    echo "CANH BAO: sha256 cua $dst/$lib khac ban da dung, so lieu co the lech" >&2
fi
echo "$dst/$lib"
