#!/usr/bin/env bash
# yosys_summary.sh - in tóm tắt kết quả syn/yosys/synth.tcl: số cell, số flip-flop,
# đường tổ hợp dài nhất (số cell) với điểm đầu và điểm cuối.
#   yosys_summary.sh <nhãn> <thư mục kết quả>
set -eu
label=$1
dir=$2
cells=$(awk '/Number of cells:/ {n=$4} END {print n}' "$dir/stat.txt")
ffs=$(grep -E '\$_(S)?DFF' "$dir/stat.txt" | awk '{s+=$2} END {print s+0}')
ltp=$(grep -o 'length=[0-9]*' "$dir/ltp.txt" | tail -n 1 | cut -d= -f2)
# Dòng đường đi có dạng "  <số>: <net> (via <cell>)", lấy net đầu và net cuối
from=$(awk '/^ +0: / {print $2; exit}' "$dir/ltp.txt")
to=$(awk '/^ +[0-9]+: / {n=$2} END {print n}' "$dir/ltp.txt")
printf '  %-20s cells %6s, flip-flop %5s, đường dài nhất %3s cell (%s -> %s)\n' \
    "$label" "$cells" "$ffs" "${ltp:-?}" "$from" "$to"
