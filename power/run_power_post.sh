#!/usr/bin/env bash
# run_power_post.sh - PWR-02: post-layout power of soc_top per testcase (server only).
# From the repo:  bash power/run_power_post.sh                  all PWR-01 testcases
#                 T="soc dma" bash power/run_power_post.sh      some of them
# Env: PNR (default pnr/out_soc_p9), DB (default pnr/run_soc_p9/DBS/route_eco.enc.dat),
#      ACT_DIR (default syn/out_soc/gls_pwr, SAIF of PWR-01), PERIOD (clock of that gate-level
#      run in ns, default 10), OUT (default power/run_post)
set -u
export LC_ALL=C    # decimal point in awk output, whatever the user locale

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO" || exit 1
absp() { case $1 in /*) echo "$1" ;; *) echo "$REPO/$1" ;; esac; }

PNR=$(absp "${PNR:-pnr/out_soc_p9}")
DB=$(absp "${DB:-pnr/run_soc_p9/DBS/route_eco.enc.dat}")
ACT_DIR=$(absp "${ACT_DIR:-syn/out_soc/gls_pwr}")
OUT=$(absp "${OUT:-power/run_post}")
PERIOD=${PERIOD:-10}
T=${T:-soc dma i2c spi_pwm soc_fw_rv32im coremark_rv32im dhrystone_rv32im accel_bench_rv32im}

command -v innovus > /dev/null || { echo "ERROR: innovus not found, this runs on the school server"; exit 1; }
for f in "$DB" "$PNR/soc_top.spef" "$ACT_DIR/saif"; do
    [ -e "$f" ] || { echo "ERROR: $f not found"; exit 1; }
done

mkdir -p "$OUT" && cd "$OUT" || exit 1
rm -f steps.txt summary.md innovus.log* innovus.cmd*
for t in $T; do rm -rf "${OUT:?}/$t"; done
PP_DB=$DB PP_SPEF=$PNR/soc_top.spef PP_SAIF=$ACT_DIR/saif PP_TESTS=$T PP_OUT=$OUT \
PP_SCOPE=${PP_SCOPE:-tb_soc/dut} PP_VIEW=${PP_VIEW:-av_setup} \
    innovus -batch -files "$REPO/power/power_post.tcl" -log innovus.log < /dev/null > /dev/null 2>&1 || true
cat steps.txt 2>/dev/null || echo "ERROR: no steps.txt, see $OUT/innovus.log"

sum=$OUT/summary.md
{
    echo "# Power soc_top after layout (PWR-02)"
    echo
    echo "Layout $DB, Innovus, slow corner, activity window clock $PERIOD ns. Power in mW, energy in uJ."
    echo
    echo "| Case | Cycles | Leakage | Internal | Switching | Total | Energy |"
    echo "|------|-------:|--------:|---------:|----------:|------:|-------:|"
} > "$sum"

fail=0
for t in $T; do
    r=$OUT/$t/power.rpt
    read -r leak int sw tot <<< "$(awk -F: '
        /^Total Leakage Power:/   { split($2, a, " "); l = a[1] }
        /^Total Internal Power:/  { split($2, a, " "); i = a[1] }
        /^Total Switching Power:/ { split($2, a, " "); s = a[1] }
        /^Total Power:/           { split($2, a, " "); p = a[1] }
        END { print l, i, s, p }' "$r" 2>/dev/null)"
    if [ -z "$tot" ]; then echo "FAIL: $t has no total power in $r"; fail=1; continue; fi
    cyc=$(grep -oE '(cycles|cycle) [0-9]+' "$ACT_DIR/$t.log" 2>/dev/null | tail -n 1 | awk '{print $2}')
    energy=?
    [ -z "$cyc" ] || energy=$(awk -v p="$tot" -v c="$cyc" -v n="$PERIOD" 'BEGIN { printf "%.4f", p * c * n / 1e6 }')
    echo "| \`$t\` | ${cyc:-?} | $leak | $int | $sw | $tot | $energy |" >> "$sum"
done
cat "$sum"
exit $fail
