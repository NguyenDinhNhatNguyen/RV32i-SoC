#!/usr/bin/env bash
# run_signoff_reports.sh - Collects the 8 sign-off reports into one reports/pnr folder.
# On the school server: bash pnr/run_signoff_reports.sh
#   DB=<file.enc.dat>   default: final layout route_trim of _p9
#   STA_DIR=<dir>       Tempus reports of the same layout
#   OUT=<dir>           default pnr/out_signoff/reports/pnr (ignored by git)
# qor_summary.rpt and constraint_violators.rpt are copies of the Tempus analysis_summary.rpt
# and violators.rpt.
set -u
cd "$(dirname "$0")/.." || { echo "ERROR: cannot change to the repo root"; exit 1; }
DB=${DB:-$HOME/RV32i-SoC/pnr/run_soc_p9/DBS/route_trim.enc.dat}
STA_DIR=${STA_DIR:-appendix/sta_soc_p9_trim}
OUT=$(realpath -m "${OUT:-pnr/out_signoff/reports/pnr}")
[ -e "$DB" ] || { echo "ERROR: database $DB not found"; exit 1; }
for f in analysis_summary.rpt violators.rpt; do
    [ -s "$STA_DIR/$f" ] || { echo "ERROR: $STA_DIR/$f not found"; exit 1; }
done
command -v innovus > /dev/null || { echo "ERROR: innovus not found, run on the server"; exit 1; }
DB=$(realpath "$DB")

mkdir -p "$OUT" pnr/run_signoff
# Remove only the reports of an earlier run, never the whole folder
for f in design_summary cts_clock_trees cts_skew_groups qor_summary constraint_violators \
         signoff_power geometry connectivity antenna; do
    rm -f "$OUT/$f.rpt"
done
( cd pnr/run_signoff && SIGNOFF_DB="$DB" SIGNOFF_OUT="$OUT" \
    innovus -batch -files ../scripts/signoff_reports.tcl -log signoff.log )
cp "$STA_DIR/analysis_summary.rpt" "$OUT/qor_summary.rpt"
cp "$STA_DIR/violators.rpt" "$OUT/constraint_violators.rpt"

bad=0
for f in design_summary cts_clock_trees qor_summary constraint_violators signoff_power \
         geometry connectivity antenna; do
    if [ -s "$OUT/$f.rpt" ]; then echo "PASS: $f.rpt"; else echo "FAIL: $f.rpt missing"; bad=1; fi
done
echo "Reports are in $OUT"
exit $bad
