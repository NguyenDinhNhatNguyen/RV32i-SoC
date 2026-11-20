#!/bin/bash
# run_lec_g2g.sh - LEC-03: synthesized netlist (golden) vs post-layout netlist (revised).
# Run on the school server from the repo:
#   DRY_RUN=1 bash lec/run_lec_g2g.sh                                  checks + dofile only
#   CHECK=1   bash lec/run_lec_g2g.sh                                  + read design only (minutes)
#   nohup bash lec/run_lec_g2g.sh > ~/lec_g2g_run.txt 2>&1 &           full run
# Env: GOLDEN (default syn/out_soc/soc_top_netlist.v), REVISED (default pnr/out_soc_p9/soc_top_pnr.v,
#      the Sheet says: not the pre_eco/ copy), LEC_DIR (default syn/out_soc_lec_g2g)
set -u
cd "$(dirname "$0")/.." || exit 1
GOLDEN=${GOLDEN:-syn/out_soc/soc_top_netlist.v}
REVISED=${REVISED:-pnr/out_soc_p9/soc_top_pnr.v}
LEC_DIR=${LEC_DIR:-syn/out_soc_lec_g2g}
LIBV=$HOME/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v
TEMPLATE=lec/soc_gate2gate.do.in
DO=lec/soc_gate2gate.do
die() { echo "ERROR: $*"; exit 1; }

[ -f "$TEMPLATE" ] || die "$TEMPLATE not found"
[ -f "$GOLDEN" ]   || die "golden $GOLDEN not found"
[ -f "$REVISED" ]  || die "revised $REVISED not found"
case "$REVISED" in *pre_eco*) die "revised is a pre_eco netlist, use the post-ECO one" ;; esac
[ -f "$LIBV" ] || echo "WARNING: $LIBV not found"

echo "== Inputs"
echo "golden  : $GOLDEN ($(wc -c < "$GOLDEN") bytes, $(date -r "$GOLDEN" '+%d/%m %H:%M'))"
echo "revised : $REVISED ($(wc -c < "$REVISED") bytes, $(date -r "$REVISED" '+%d/%m %H:%M'))"
[ "$REVISED" -nt "$GOLDEN" ] || echo "WARNING: revised is not newer than golden, check you have the right pair"

# Cell types used in a netlist: first word of each instance line "CELL inst ("
cells() { grep -E '^\s*[A-Za-z_][A-Za-z0-9_]*\s+\\?[^ ;(]+\s*\(' "$1" | awk '{print $1}' \
          | grep -v -E '^(module|input|output|inout|wire|reg|assign|endmodule)$' | sort -u; }
mods()  { grep -E '^\s*module\s' "$1" | awk '{print $2}' | sed 's/[(;].*//' | sort -u; }

echo "== Macros (expect 8 on both sides)"
echo "golden  : $(grep -c -E '^\s*sram_2k_macro\s' "$GOLDEN")"
echo "revised : $(grep -c -E '^\s*sram_2k_macro\s' "$REVISED")"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mods "$LIBV" > "$tmp/lib" 2>/dev/null
mods "$GOLDEN" > "$tmp/gmod"; mods "$REVISED" > "$tmp/rmod"
cells "$REVISED" | comm -23 - "$tmp/rmod" > "$tmp/rcell"
cells "$GOLDEN"  | comm -23 - "$tmp/gmod" > "$tmp/gcell"
echo "== Cell types in revised that are not in the cell library (expect only sram_2k_macro)"
comm -23 "$tmp/rcell" "$tmp/lib" | sed 's/^/   /'
echo "== Cell types only in revised (CTS, hold and ECO cells are expected here)"
comm -13 "$tmp/gcell" "$tmp/rcell" | head -40 | sed 's/^/   /'
echo "== FILL/DECAP/TAP instances in revised (expect 0 in the netlist without -includePhysicalCell)"
grep -c -E '^\s*(FILL|DECAP|TAP|WELLTAP)\w*\s' "$REVISED"

mkdir -p "$LEC_DIR/reports"
cp "$GOLDEN"  "$LEC_DIR/golden_netlist.v"
cp "$REVISED" "$LEC_DIR/revised_pnr.v"
sed -e "s|@@GOLDEN@@|$LEC_DIR/golden_netlist.v|g" -e "s|@@REVISED@@|$LEC_DIR/revised_pnr.v|g" \
    -e "s|@@OUTDIR@@|$LEC_DIR/reports|g" "$TEMPLATE" > "$DO"
echo "== Dofile written: $DO (LEC_DIR=$LEC_DIR)"
[ "${DRY_RUN:-0}" = 1 ] && { echo "DRY_RUN=1: lec not started"; exit 0; }
command -v lec > /dev/null || die "lec not found"

if [ "${CHECK:-0}" = 1 ]; then
    sed '/^set system mode lec/,$d' "$DO" > "$LEC_DIR/check.do"; echo "exit -force" >> "$LEC_DIR/check.do"
    lec -nogui -dofile "$LEC_DIR/check.do" < /dev/null > "$LEC_DIR/check.log" 2>&1 || true
    echo "== // Error lines (expect none)"; grep -n '// Error' "$LEC_DIR/check.log" | head -20
    echo "== report black box (expect only sram_2k_macro)"; grep -n -A12 'report black box' "$LEC_DIR/check.log" | head -30
    exit 0
fi

echo "== Starting lec at $(date '+%H:%M:%S'), log: $LEC_DIR/lec.txt"
s=$(date +%s)
lec -nogui -dofile "$DO" < /dev/null > "$LEC_DIR/lec.txt" 2>&1 || true
echo "== lec finished after $(( ($(date +%s) - s) / 60 )) min"
grep -E 'Compare Results|Non-equivalent|Equivalent|Abort|Unmapped|// Error' "$LEC_DIR/lec.txt" | tail -20
echo "Reports in $LEC_DIR/reports. Never commit the netlist copies in $LEC_DIR."
