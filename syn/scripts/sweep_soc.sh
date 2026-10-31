#!/usr/bin/env bash
# sweep_soc.sh - runs synth_soc.tcl at several clock periods to find F_max of soc_top (STA-03,
# server only). Called by make synth-soc-sweep, same idea as sweep_core.sh for rv32_core.
#
#   PERIODS="6 5.5 5 4.5"      periods in ns (default), around the F_max found on 30-31/10
#                              (5 ns met, 4 ns failed, docs/sta_results.md section 4)
#   CG                         passed to synth_soc.tcl as in make synth-soc
#
# Each run goes to syn/out_soc_sweep/p<period>/ (Genus log in syn/run_soc_sweep/p<period>/).
# The summary is printed and written to syn/out_soc_sweep/summary.md.
# F_max = 1 / (period - WNS) is only an estimate from the worst path of that run.
set -u

REPO=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO" || exit 1
PERIODS=${PERIODS:-6 5.5 5 4.5}
SWEEP_OUT=syn/out_soc_sweep
SWEEP_RUN=syn/run_soc_sweep

if ! command -v genus > /dev/null; then
    echo "ERROR: genus not found, the sweep runs on the school server"
    exit 1
fi
mkdir -p "$SWEEP_OUT"

# Value of key=<value> in summary.txt (written by synth_soc.tcl)
summary_val() {
    tr ' ' '\n' < "$1/summary.txt" 2>/dev/null | sed -n "s/^$2=//p" | head -n 1
}

# Cell area of the top row in area.rpt (columns ... Cell Count, Cell Area, Net Area, Total Area)
cell_area() {
    awk '$1 == "soc_top" && NF >= 4 { print $(NF - 2); exit }' \
        "$1/reports/synthesis/area.rpt" 2>/dev/null
}

for p in $PERIODS; do
    out=$SWEEP_OUT/p$p
    run=$SWEEP_RUN/p$p
    rm -rf "$out"
    mkdir -p "$run"
    rm -f "$run"/genus.log* "$run"/genus.cmd*
    echo "sweep-soc: PERIOD=$p ns ..."
    (cd "$run" && PERIOD=$p SYN_OUT=$REPO/$out \
        genus -batch -files "$REPO/syn/scripts/synth_soc.tcl" -log genus.log > /dev/null 2>&1)
    [ -f "$out/soc_top_netlist.v" ] || echo "ERROR: no netlist at PERIOD=$p, see $run/genus.log"
done

{
    # WNS with 4 decimals: below 14 ns Genus ends a few ps above 0 (30/10 sweep)
    head="| Chu kỳ (ns) | WNS (ns) | Chu kỳ nhỏ nhất (ns) | F_max ước lượng (MHz)"
    echo "$head | Diện tích (µm²) | Macro | Scan flop |"
    echo "| --- | --- | --- | --- | --- | --- | --- |"
    for p in $PERIODS; do
        out=$SWEEP_OUT/p$p
        w=$(summary_val "$out" wns_ps)
        a=$(cell_area "$out")
        m=$(summary_val "$out" macros)
        s=$(summary_val "$out" scan_flops)
        if [ -n "$w" ] && [ "$w" != "n/a" ]; then
            awk -v p="$p" -v w="$w" -v a="${a:--}" -v m="${m:--}" -v s="${s:--}" 'BEGIN {
                wns = w / 1000.0; tmin = p - wns
                printf "| %s | %.4f | %.4f | %.0f | %s | %s | %s |\n",
                       p, wns, tmin, 1000.0 / tmin, a, m, s }'
        else
            echo "| $p | - | - | - | ${a:--} | ${m:--} | ${s:--} |"
        fi
    done
} > "$SWEEP_OUT/summary.md"
cat "$SWEEP_OUT/summary.md"
echo "sweep-soc: summary in $SWEEP_OUT/summary.md"
