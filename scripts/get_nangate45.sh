#!/usr/bin/env bash
# get_nangate45.sh - downloads the open Nangate45 liberty (typical) for the home timing flow.
# The file lives in syn/run_yosys/lib/ (blocked by .gitignore) and is never committed.
# Source: OpenROAD-flow-scripts, flow/platforms/nangate45. Not GPDK45.
#   scripts/get_nangate45.sh [target dir]
set -euo pipefail

dst=${1:-syn/run_yosys/lib}
lib=NangateOpenCellLibrary_typical.lib
url=https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/master/flow/platforms/nangate45/lib/$lib
# sha256 of the copy used for docs/timing_core.md (23/10/2026)
sum=8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1

mkdir -p "$dst"
if [ ! -f "$dst/$lib" ]; then
    echo "Tai $lib ..."
    curl -sfL -o "$dst/$lib.tmp" "$url"
    mv "$dst/$lib.tmp" "$dst/$lib"
fi
if ! echo "$sum  $dst/$lib" | sha256sum -c --status; then
    echo "WARNING: the sha256 of $dst/$lib differs from the copy used before, numbers may differ" >&2
fi
echo "$dst/$lib"
