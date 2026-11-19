#!/usr/bin/env bash
# power_soc.sh - pre-layout power of the soc_top netlist per testcase (PWR-01, server only).
# Called by make power-soc after make gls-soc-saif. Docs: docs/power_soc.md.
#
# Runs Genus (syn/scripts/power_soc.tcl) once per case:
#   default     no activity file, Genus default toggle rate
#   <test>      the SAIF (or VCD) of that test from the gate-level run
# Then writes OUT/summary.md: leakage, internal, switching, total power, cycles of the
# activity window, and energy = total power x cycles x clock period.
#
# Environment variables:
#   NETLIST   Genus netlist (default syn/out_soc/soc_top_netlist.v)
#   ACT_DIR   Folder of the gate-level run (default syn/out_soc/gls_pwr): ACT_DIR/saif/<test>.saif
#             or ACT_DIR/vcd/<test>.vcd, and ACT_DIR/<test>.log for the cycle count
#   T         Cases (default: default and every activity file in ACT_DIR)
#   PERIOD    Clock period in ns (default 10, same as the gate-level run)
#   OUT       Report folder (default syn/out_soc/power)
set -u
export LC_ALL=C    # decimal point in awk output, whatever the user locale

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO" || exit 1
absp() { case $1 in /*) echo "$1" ;; *) echo "$REPO/$1" ;; esac; }

NETLIST=$(absp "${NETLIST:-syn/out_soc/soc_top_netlist.v}")
ACT_DIR=$(absp "${ACT_DIR:-syn/out_soc/gls_pwr}")
PERIOD=${PERIOD:-10}
OUT=$(absp "${OUT:-syn/out_soc/power}")

command -v genus > /dev/null || { echo "ERROR: genus not found, power-soc runs on the school server"; exit 1; }
[ -f "$NETLIST" ] || { echo "ERROR: no netlist $NETLIST (set NETLIST)"; exit 1; }

# Activity file of a test: SAIF first, then VCD
act_of() {
    if [ -s "$ACT_DIR/saif/$1.saif" ]; then echo "SAIF $ACT_DIR/saif/$1.saif"
    elif [ -s "$ACT_DIR/vcd/$1.vcd" ]; then echo "VCD $ACT_DIR/vcd/$1.vcd"
    fi
}

if [ -n "${T:-}" ]; then
    cases=$T
else
    cases="default $(ls "$ACT_DIR"/saif/*.saif "$ACT_DIR"/vcd/*.vcd 2>/dev/null |
                     xargs -r -n1 basename | sed -E 's/\.(saif|vcd)$//' | sort -u | tr '\n' ' ')"
fi
[ "$(echo $cases)" != default ] ||
    echo "WARNING: no activity file in $ACT_DIR, only the default case (run make gls-soc-saif first)"

mkdir -p "$OUT"
sum=$OUT/summary.md
{
    echo "# Power soc_top before layout (PWR-01)"
    echo
    echo "Netlist $NETLIST, Genus, slow corner, clock $PERIOD ns. Power in mW, energy in uJ."
    echo
    echo "| Case | Activity | Cycles | Leakage | Internal | Switching | Total | Energy |"
    echo "|------|----------|-------:|--------:|---------:|----------:|------:|-------:|"
} > "$sum"

fail=0
for c in $cases; do
    d=$OUT/$c
    rm -rf "$d"
    mkdir -p "$d"
    fmt=""; act=""; cyc=""
    if [ "$c" != default ]; then
        read -r fmt act <<< "$(act_of "$c")"
        if [ -z "$act" ]; then echo "  [FAIL] $c: no SAIF or VCD in $ACT_DIR"; fail=1; continue; fi
        cyc=$(grep -oE '(cycles|cycle) [0-9]+' "$ACT_DIR/$c.log" 2>/dev/null | tail -n 1 | awk '{print $2}')
    fi
    (cd "$d" && PWR_NETLIST=$NETLIST PWR_OUT=$d PWR_ACT=$act PWR_FMT=$fmt PERIOD=$PERIOD \
        genus -batch -files "$REPO/syn/scripts/power_soc.tcl" -log genus.log > /dev/null 2>&1)
    line=$(grep -m1 'Subtotal' "$d/power.rpt" 2>/dev/null)
    if [ -z "$line" ] || grep -q '^ERROR' "$d/activity.txt" 2>/dev/null; then
        echo "  [FAIL] $c: no power report, see $d/genus.log"
        grep -E '^(Error|ERROR)' "$d/genus.log" 2>/dev/null | head -5 | sed 's/^/      /'
        fail=1
        continue
    fi
    # Subtotal  leakage internal switching total (W)
    read -r lk in sw tot <<< "$(echo "$line" | awk '{print $2, $3, $4, $5}')"
    row=$(awk -v c="$c" -v f="${fmt:-default}" -v n="${cyc:-}" -v p="$PERIOD" \
              -v lk="$lk" -v in_="$in" -v sw="$sw" -v t="$tot" 'BEGIN {
        e = (n == "") ? "" : sprintf("%.4f", t * n * p * 1e-9 * 1e6)
        printf "| %s | %s | %s | %.4f | %.4f | %.4f | %.4f | %s |", c, f, (n == "" ? "" : n),
               lk * 1e3, in_ * 1e3, sw * 1e3, t * 1e3, e }')
    echo "$row" >> "$sum"
    echo "  $c: total $(awk -v t="$tot" 'BEGIN{printf "%.4f", t*1e3}') mW ($(sed -n 1p "$d/activity.txt"))"
done

echo "power-soc: report in $sum"
[ "$fail" -eq 0 ]
