#!/usr/bin/env bash
# yosys_summary.sh - prints a summary of syn/yosys/synth.tcl results: cells, flip-flops,
# and the longest combinational path (in cells) with its start and end points.
#   yosys_summary.sh <label> <result dir>
set -eu
label=$1
dir=$2
cells=$(awk '/Number of cells:/ {n=$4} END {print n}' "$dir/stat.txt")
ffs=$(grep -E '\$_(S)?DFF' "$dir/stat.txt" | awk '{s+=$2} END {print s+0}')
ltp=$(grep -o 'length=[0-9]*' "$dir/ltp.txt" | tail -n 1 | cut -d= -f2)
# Path lines look like "  <n>: <net> (via <cell>)", take the first and last net
from=$(awk '/^ +0: / {print $2; exit}' "$dir/ltp.txt")
to=$(awk '/^ +[0-9]+: / {n=$2} END {print n}' "$dir/ltp.txt")
printf '  %-20s cells %6s, flip-flop %5s, longest path %3s cells (%s -> %s)\n' \
    "$label" "$cells" "$ffs" "${ltp:-?}" "$from" "$to"
