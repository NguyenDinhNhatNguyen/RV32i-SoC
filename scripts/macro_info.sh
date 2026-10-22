#!/usr/bin/env bash
# macro_info.sh - tóm tắt SRAM macro trên server trường (đọc LEF, .lib, .v), không chép file.
# Cách dùng (trong MobaXterm, thư mục repo):
#   bash scripts/macro_info.sh                      # macro mặc định sram_2k_macro trong ~/PDK_GPDK45
#   bash scripts/macro_info.sh <tên_macro> <PDK_DIR>
# Phần cấu trúc (kích thước, chân, lớp kim loại) ghi vào appendix/macro_check/ để đưa lên repo.
# Phần timing và hành vi mô hình .v chỉ in ra màn hình, không ghi file, vì là dữ liệu của thư viện.

set -u
MACRO=${1:-sram_2k_macro}
PDK=${2:-${PDK_DIR:-$HOME/PDK_GPDK45}}
LEF=$PDK/lef/$MACRO.lef
LIB=$PDK/lib/$MACRO.lib
VMOD=$PDK/lib/$MACRO.v
OUTDIR="$(cd "$(dirname "$0")/.." && pwd)/appendix/macro_check"
mkdir -p "$OUTDIR"
OUT="$OUTDIR/${MACRO}_$(date +%Y%m%d).txt"

for f in "$LEF" "$LIB" "$VMOD"; do
    [ -f "$f" ] || echo "CANH BAO: khong thay $f"
done

{
echo "Macro $MACRO, đọc từ $PDK, $(date '+%Y-%m-%d %H:%M')"
echo
echo "==== 1. LEF: thông tin chung ===="
awk -v M="$MACRO" '{sub(/\r$/,"")}
    $1=="MACRO" && $2==M {in_m=1}
    in_m && $1=="END" && $2==M {in_m=0}
    in_m && ($1=="CLASS"||$1=="SIZE"||$1=="SYMMETRY"||$1=="ORIGIN"||$1=="SITE"||$1=="FOREIGN") {print "  " $0}
' "$LEF"

echo
echo "==== 2. LEF: chân (gom bus) ===="
echo "  Tên chân | hướng | loại | lớp kim loại"
awk -v M="$MACRO" '{sub(/\r$/,"")}
    $1=="MACRO" && $2==M {in_m=1}
    in_m && $1=="END" && $2==M {in_m=0}
    !in_m {next}
    $1=="PIN" {pin=$2; base=pin; sub(/\[.*/,"",base); if(!(base in seen)){order[++n]=base; seen[base]=1}; cnt[base]++; in_p=1; next}
    in_p && $1=="DIRECTION" {dir[base]=$2}
    in_p && $1=="USE" {use[base]=$2}
    in_p && $1=="LAYER" {l=$2; if(index(" " lay[base] " ", " " l " ")==0) lay[base]=lay[base] " " l}
    in_p && $1=="END" && $2==pin {in_p=0}
    END {for(i=1;i<=n;i++){b=order[i]; w=(cnt[b]>1)?"[" cnt[b] " bit]":""; printf "  %s%s | %s | %s |%s\n", b, w, dir[b], (use[b]==""?"SIGNAL":use[b]), lay[b]}}
' "$LEF" | sed 's/ ;//g'

echo
echo "==== 3. LEF: vùng cấm (OBS) theo lớp ===="
awk -v M="$MACRO" '{sub(/\r$/,"")}
    $1=="MACRO" && $2==M {in_m=1}
    in_m && $1=="END" && $2==M {in_m=0}
    in_m && $1=="OBS" {in_o=1; next}
    in_o && $1=="END" {in_o=0}
    in_o && $1=="LAYER" {c[$2]++}
    END {for (l in c) printf "  %s: %d hình\n", l, c[l]}
' "$LEF" | sed 's/ ;//g' | sort

echo
echo "==== 4. .lib: corner và diện tích ===="
grep -m1 -E '^\s*library\s*\(' "$LIB" | sed 's/^/  /'
grep -m3 -E 'nom_(voltage|temperature|process)' "$LIB" | sed 's/^/  /'
grep -m2 -E 'operating_conditions\s*\(' "$LIB" | sed 's/^/  /'
grep -m1 -E '^\s*area\s*:' "$LIB" | sed 's/^/  /'
echo "  Số file .lib của macro trong PDK (mỗi file thường là 1 corner):"
ls "$PDK"/lib/"$MACRO"*.lib 2>/dev/null | sed 's/^/    /'

echo
echo "==== 5. Đối chiếu nhanh ===="
echo "  GDS của macro: $(ls "$PDK"/*/"$MACRO"*.gds* "$PDK"/"$MACRO"*.gds* 2>/dev/null | head -1 || true)"
echo "  CDL/SPICE cho LVS: $(ls "$PDK"/*/"$MACRO"*.cdl "$PDK"/*/"$MACRO"*.sp* 2>/dev/null | head -1 || true)"
} | tee "$OUT"

echo
echo "==== 6. .lib: loại cung timing (chỉ in màn hình) ===="
grep -E 'timing_type|related_pin' "$LIB" | sed -E 's/^\s+//' | sort | uniq -c | sort -rn | head -20

echo
echo "==== 7. Mô hình .v: hành vi khi ghi và khi CEN=1 (chỉ in màn hình) ===="
grep -n -E 'always|posedge|CEN|WEN|Q\s*<?=' "$VMOD" | head -30

echo
echo "Đã ghi phần cấu trúc vào: $OUT"
echo "Dán toàn bộ output màn hình vào chat để phân tích. Chỉ commit file trong appendix/macro_check/."
