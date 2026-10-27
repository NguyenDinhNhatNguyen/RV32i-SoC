#!/usr/bin/env bash
# sweep_core.sh - runs synth_core.tcl at several clock periods to find F_max of rv32_core
# (server only). Called by make synth-core-sweep, steps in docs/genus_core.md.
#
#   PERIODS="20 10 8 6 5"   periods in ns (default)
#   CG, ENABLE_BTB          passed to synth_core.tcl as in make synth-core
#
# Each run goes to syn/out_core_sweep/p<period>/ (Genus log in syn/run_core_sweep/p<period>/).
# The summary is printed and written to syn/out_core_sweep/summary.md.
# F_max = 1 / (period - WNS) is only an estimate from the worst path of that run.
set -u

REPO=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO" || exit 1
PERIODS=${PERIODS:-20 10 8 6 5}
SWEEP_OUT=syn/out_core_sweep
SWEEP_RUN=syn/run_core_sweep

if ! command -v genus > /dev/null; then
    echo "ERROR: genus not found, the sweep runs on the school server"
    exit 1
fi
mkdir -p "$SWEEP_OUT"

# WNS in ps: run_info.txt (design slack attribute), else "Timing slack" of timing.rpt
wns_ps() {
    local w
    w=$(sed -n 's/.*WNS_PS=\(-\{0,1\}[0-9.]*\).*/\1/p' "$1/reports/synthesis/run_info.txt" 2>/dev/null)
    if [ -z "$w" ]; then
        w=$(sed -n 's/.*Timing slack *: *\(-\{0,1\}[0-9.]*\) *ps.*/\1/p' \
                "$1/reports/synthesis/timing.rpt" 2>/dev/null | head -n 1)
    fi
    # Last resort: the clk row of qor.rpt (slack, TNS, violating paths), as in ppa_table.py
    if [ -z "$w" ]; then
        w=$(awk '$1 == "clk" && NF == 4 && $4 ~ /^[0-9]+$/ { print $2; exit }' \
                "$1/reports/synthesis/qor.rpt" 2>/dev/null)
    fi
    echo "$w"
}

# Cell area of the top row in area.rpt (columns ... Cell Count, Cell Area, Net Area, Total Area)
cell_area() {
    awk '$1 == "rv32_core_syn" && NF >= 4 { print $(NF - 2); exit }' \
        "$1/reports/synthesis/area.rpt" 2>/dev/null
}

for p in $PERIODS; do
    out=$SWEEP_OUT/p$p
    run=$SWEEP_RUN/p$p
    rm -rf "$out"
    mkdir -p "$run"
    rm -f "$run"/genus.log* "$run"/genus.cmd*
    echo "sweep-core: PERIOD=$p ns ..."
    (cd "$run" && PERIOD=$p SYN_OUT=$REPO/$out \
        genus -batch -files "$REPO/syn/scripts/synth_core.tcl" -log genus.log > /dev/null 2>&1)
    [ -f "$out/rv32_core_syn_netlist.v" ] || echo "ERROR: no netlist at PERIOD=$p, see $run/genus.log"
done

{
    head="| Chu kỳ (ns) | WNS (ns) | Chu kỳ nhỏ nhất (ns) | F_max ước lượng (MHz)"
    echo "$head | Cell area (µm²) |"
    echo "| --- | --- | --- | --- | --- |"
    for p in $PERIODS; do
        out=$SWEEP_OUT/p$p
        w=$(wns_ps "$out")
        a=$(cell_area "$out")
        if [ -n "$w" ]; then
            awk -v p="$p" -v w="$w" -v a="${a:--}" 'BEGIN {
                wns = w / 1000.0; tmin = p - wns
                printf "| %s | %.3f | %.3f | %.0f | %s |\n", p, wns, tmin, 1000.0 / tmin, a }'
        else
            echo "| $p | - | - | - | ${a:--} |"
        fi
    done
} > "$SWEEP_OUT/summary.md"
cat "$SWEEP_OUT/summary.md"
echo "sweep-core: summary in $SWEEP_OUT/summary.md"
