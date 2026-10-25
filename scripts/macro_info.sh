#!/usr/bin/env bash
# macro_info.sh - summarizes the SRAM macro on the school server (reads LEF, .lib, .v), copies nothing.
# Usage (in MobaXterm, from the repo folder):
#   bash scripts/macro_info.sh                      # default macro sram_2k_macro in ~/PDK_GPDK45
#   bash scripts/macro_info.sh <macro_name> <PDK_DIR>
# The structural part (size, pins, metal layers) goes to appendix/macro_check/ for the repo.
# Timing and the .v model behavior are printed to screen only, never to a file, because they are library data.

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
    [ -f "$f" ] || echo "WARNING: cannot find $f"
done

{
echo "Macro $MACRO, read from $PDK, $(date '+%Y-%m-%d %H:%M')"
echo
echo "==== 1. LEF: general ===="
awk -v M="$MACRO" '{sub(/\r$/,"")}
    $1=="MACRO" && $2==M {in_m=1}
    in_m && $1=="END" && $2==M {in_m=0}
    in_m && ($1=="CLASS"||$1=="SIZE"||$1=="SYMMETRY"||$1=="ORIGIN"||$1=="SITE"||$1=="FOREIGN") {print "  " $0}
' "$LEF"

echo
echo "==== 2. LEF: pins (buses grouped) ===="
echo "  Pin name | direction | use | metal layers"
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
echo "==== 3. LEF: obstructions (OBS) per layer ===="
awk -v M="$MACRO" '{sub(/\r$/,"")}
    $1=="MACRO" && $2==M {in_m=1}
    in_m && $1=="END" && $2==M {in_m=0}
    in_m && $1=="OBS" {in_o=1; next}
    in_o && $1=="END" {in_o=0}
    in_o && $1=="LAYER" {c[$2]++}
    END {for (l in c) printf "  %s: %d shapes\n", l, c[l]}
' "$LEF" | sed 's/ ;//g' | sort

echo
echo "==== 4. .lib: corner and area ===="
grep -m1 -E '^\s*library\s*\(' "$LIB" | sed 's/^/  /'
grep -m3 -E 'nom_(voltage|temperature|process)' "$LIB" | sed 's/^/  /'
grep -m2 -E 'operating_conditions\s*\(' "$LIB" | sed 's/^/  /'
grep -m1 -E '^\s*area\s*:' "$LIB" | sed 's/^/  /'
echo "  Number of macro .lib files in the PDK (usually 1 corner each):"
ls "$PDK"/lib/"$MACRO"*.lib 2>/dev/null | sed 's/^/    /'

echo
echo "==== 5. Quick checks ===="
echo "  Macro GDS: $(ls "$PDK"/*/"$MACRO"*.gds* "$PDK"/"$MACRO"*.gds* 2>/dev/null | head -1 || true)"
echo "  CDL/SPICE for LVS: $(ls "$PDK"/*/"$MACRO"*.cdl "$PDK"/*/"$MACRO"*.sp* 2>/dev/null | head -1 || true)"
} | tee "$OUT"

echo
echo "==== 6. .lib: timing arc types (screen only) ===="
grep -E 'timing_type|related_pin' "$LIB" | sed -E 's/^\s+//' | sort | uniq -c | sort -rn | head -20

echo
echo "==== 7. .v model: behavior on write and with CEN=1 (screen only) ===="
grep -n -E 'always|posedge|CEN|WEN|Q\s*<?=' "$VMOD" | head -30

echo
echo "Structural part written to: $OUT"
echo "Paste the whole screen output into the chat for analysis. Commit only the file in appendix/macro_check/."
