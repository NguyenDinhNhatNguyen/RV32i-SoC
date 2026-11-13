#!/bin/bash
# run_lec_soc.sh - LEC-01: Conformal run of soc_top, RTL against the Genus netlist.
# Runs on the school server (needs the lec command). From anywhere inside the repo:
#   bash lec/run_lec_soc.sh                                   foreground
#   nohup bash lec/run_lec_soc.sh > ~/lec_soc_run.txt 2>&1 &  background
#
# Environment (all optional):
#   SRC_DIR=syn/out_soc       where make synth-soc wrote the netlist
#   LEC_DIR=syn/out_soc_lec   private copy of the netlist and the results, so a new
#                             make synth-soc by someone else cannot change the netlist mid-run
#   ONE_LINE=1                write the golden read design as one long line (like
#                             core_rtl2gate.do) instead of lines continued with a backslash
#   DRY_RUN=1                 only check the inputs and write the dofile, do not start lec
#
# The script stops before lec while a TODO_MACRO marker is in the dofile template.
# The netlist copy and the results stay in LEC_DIR and must not go to git.

set -u
cd "$(dirname "$0")/.." || { echo "ERROR: cannot change to the repo root"; exit 1; }

SRC_DIR=${SRC_DIR:-syn/out_soc}
LEC_DIR=${LEC_DIR:-syn/out_soc_lec}
ONE_LINE=${ONE_LINE:-0}
DRY_RUN=${DRY_RUN:-0}
NETLIST_SRC=$SRC_DIR/soc_top_netlist.v
TEMPLATE=lec/soc_rtl2gate.do.in
DO=lec/soc_rtl2gate.do

die() { echo "ERROR: $*"; exit 1; }

# 1. Inputs
[ -f "$TEMPLATE" ]    || die "$TEMPLATE not found"
[ -f "$NETLIST_SRC" ] || die "$NETLIST_SRC not found, run make synth-soc first (or set SRC_DIR)"
if [ "$DRY_RUN" != 1 ]; then
    command -v lec > /dev/null || die "lec (Conformal) not found, this runs on the school server"
fi
[ -f "$HOME/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v" ] || \
    echo "WARNING: ~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v not found, read library will fail"

echo "== Inputs"
echo "repo commit : $(git log -1 --format='%h %s' 2> /dev/null || echo 'no git here')"
echo "netlist     : $NETLIST_SRC ($(wc -c < "$NETLIST_SRC") bytes, $(date -r "$NETLIST_SRC" '+%d/%m %H:%M'))"
if [ -f "$SRC_DIR/summary.txt" ]; then
    echo "synth summary: $(cat "$SRC_DIR/summary.txt")"
fi
# Files newer than the netlist were changed after synthesis (for example by git pull).
newer=$(find rtl \( -name '*.v' -o -name '*.vh' \) -newer "$NETLIST_SRC" | sort)
if [ -n "$newer" ]; then
    echo "WARNING: these RTL files are newer than the netlist, check whether they changed the design"
    echo "         after make synth-soc:"
    echo "$newer" | sed 's/^/           /'
else
    echo "RTL check   : no RTL file is newer than the netlist"
fi

# 2. Private copy of the netlist and the output folder
mkdir -p "$LEC_DIR/reports"
cp "$NETLIST_SRC" "$LEC_DIR/soc_top_netlist.v"
cp "$SRC_DIR/summary.txt" "$LEC_DIR/synth_summary.txt" 2> /dev/null || true

# 3. Golden file list: same set as synth_soc.tcl
files=""
add_files() {
    local f
    for f in "$@"; do
        [ -f "$f" ] || die "RTL file $f not found"
        files="$files $f"
    done
}
add_files $(ls rtl/core/rv32_*.v 2> /dev/null | sort)
add_files $(ls rtl/bus/*.v 2> /dev/null | sort)
add_files $(ls rtl/mem/*.v 2> /dev/null | sort)
add_files $(ls rtl/periph/*.v 2> /dev/null | sort)
add_files rtl/accel/pe.v rtl/accel/accelerator_top.v rtl/accel/accel_wrapper.v rtl/accel/accel_apb.v

tmp_reads=$(mktemp)
trap 'rm -f "$tmp_reads"' EXIT
if [ "$ONE_LINE" = 1 ]; then
    echo "read design -golden -verilog$files" > "$tmp_reads"
else
    # One file per line, each line but the last ends with a backslash
    echo "read design -golden -verilog \\" > "$tmp_reads"
    set -- $files
    while [ $# -gt 1 ]; do
        echo " $1 \\" >> "$tmp_reads"
        shift
    done
    echo " $1" >> "$tmp_reads"
fi

sed -e "s|@@NETLIST@@|$LEC_DIR/soc_top_netlist.v|g" \
    -e "s|@@OUTDIR@@|$LEC_DIR/reports|g" \
    -e "/@@RTL_READ@@/{r $tmp_reads" \
    -e "d}" "$TEMPLATE" > "$DO"
echo "== Dofile written: $DO ($(echo $files | wc -w) golden RTL files, ONE_LINE=$ONE_LINE)"

if grep -q 'TODO_MACRO' "$DO"; then
    echo "STOP: a TODO_MACRO marker is still in the dofile, lec was not started."
    [ "$DRY_RUN" = 1 ] && exit 0
    exit 1
fi
if [ "$DRY_RUN" = 1 ]; then
    echo "DRY_RUN=1: lec not started"
    exit 0
fi

# 4. Run Conformal. < /dev/null so lec exits if the dofile stops midway
echo "== Starting lec at $(date '+%H:%M:%S'), log: $LEC_DIR/lec.txt"
start=$(date +%s)
lec -nogui -dofile "$DO" < /dev/null > "$LEC_DIR/lec.txt" 2>&1 || true
echo "== lec finished after $(( ($(date +%s) - start) / 60 )) min"

# 5. Summary: same grep as make lec-core, plus the lines about the black box command
echo "== Result lines"
grep -E 'Compare Results|Non-equivalent|Equivalent|Abort|Unmapped|// Error' "$LEC_DIR/lec.txt" | tail -20
echo "== Lines mentioning black box"
grep -n -i 'black box' "$LEC_DIR/lec.txt" | head -12

# 6. Safety: no netlist, SDF, SPEF or GDS may reach git
if git status --short 2> /dev/null | grep -E '_netlist\.v|\.sdf|\.spef|\.gds'; then
    echo "WARNING: the files above show up in git status. Do not add them (no git add -f)."
fi
echo "Done. Reports are in $LEC_DIR/reports, copy only the text reports to appendix/lec_soc/."
