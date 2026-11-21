#!/bin/bash
# run_ir.sh - LEC-04: static IR drop of soc_top with Innovus/Voltus (Lab 06 section 3.2).
# From the repo on the school server:
#   IR_DB=<path to route.enc.dat> bash power/run_ir.sh                  scenario A (activity 0.1)
#   IR_DB=<...> IR_ACT=0.5 bash power/run_ir.sh                         scenario B (stress, 0.5)
# Official database (20/11): pnr/run_soc_p9/DBS/route_eco.enc.dat (saved 18/11 15:10). The post-ECO
# netlist, SPEF and GDS were written at 15:31 from this same database, with no layout change.
# Needs IR_TECH=/home/eda/library/cadence/gpdk045_v_6_0/qrc/typical/qrcTechFile (the PDK .tch is not readable, VOLTUS-5360).
# Optional: IR_PADS=<pad file, format in ir_static.tcl>, IR_VIEW (default av_setup). Output: power/run_ir_act<ACT>/
set -u
cd "$(dirname "$0")/.." || exit 1
REPO=$PWD
: "${IR_DB:?set IR_DB to the routed database of the official layout (route.enc.dat of the _p9 run)}"
[ -e "$IR_DB" ] || { echo "ERROR: $IR_DB not found"; exit 1; }
case "$IR_DB" in /*) ;; *) IR_DB=$REPO/$IR_DB ;; esac
export IR_DB IR_TOP=${IR_TOP:-soc_top} IR_ACT=${IR_ACT:-0.1}
RUN=$REPO/power/run_ir_act$IR_ACT
export IR_OUT=$RUN/reports IR_PADS=${IR_PADS:-} IR_VIEW=${IR_VIEW:-av_setup} IR_VOLT=${IR_VOLT:-0.9} IR_TECH=${IR_TECH:-} IR_PERIOD=${IR_PERIOD:-10.0}
mkdir -p "$RUN" && cd "$RUN" || exit 1
command -v innovus > /dev/null || { echo "ERROR: innovus not found"; exit 1; }
echo "== $(date '+%H:%M') innovus batch, DB=$IR_DB, activity=$IR_ACT, log: $RUN/innovus.log"
rm -f innovus.log* innovus.cmd* rail_missing_files
innovus -batch -files "$REPO/power/ir_static.tcl" -log innovus.log < /dev/null > /dev/null 2>&1 || true
echo "== Steps"
cat "$IR_OUT/steps.txt" 2>/dev/null || echo "(no steps.txt)"
echo "== Errors (first 15)"
grep -E '\*\*ERROR' innovus.log | head -15
echo "== Lines about IR drop in the log"
grep -i -E 'worst|ir drop|max.*drop|drop.*max|min.*volt' innovus.log | grep -v '^#' | tail -20
echo "== rail_missing_files (if any)"
cat rail_missing_files 2>/dev/null | head -20
echo "== Rail result files"
find "$IR_OUT" -maxdepth 3 -type f | head -30
