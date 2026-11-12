#!/usr/bin/env bash
# hal_lint.sh - Cadence HAL lint of the whole soc_top RTL with Xcelium (server only, VER-03).
# Called by make lint-hal, steps in docs/lint_status.md.
#
# Environment variables:
#   XRUN   xrun binary (default xrun)
#   TOP    Top module (default soc_top, default parameters)
#   OUT    Run folder (default lint/run_hal)
#
# Runs xrun -hal on the same files as lint-soc, keeps xrun.log and hal.log in OUT, then writes
# OUT/summary.txt with the number of messages per severity and per rule. Exits 1 only on
# *E or *F messages. HAL warnings are recorded for the report, they do not fail the run,
# because the team criterion is 0 Verilator warnings (make lint-all).
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO" || exit 1

XRUN=${XRUN:-xrun}
TOP=${TOP:-soc_top}
OUT=${OUT:-lint/run_hal}

if ! command -v "$XRUN" > /dev/null; then
    echo "ERROR: $XRUN not found, lint-hal runs on the school server"
    exit 1
fi

# Same file set as SOC_RTL in the Makefile
files=$(ls rtl/core/*.v rtl/bus/*.v rtl/mem/*.v rtl/periph/*.v rtl/accel/*.v)
for f in $files; do
    [ -s "$f" ] || { echo "ERROR: $f is empty"; exit 1; }
done

mkdir -p "$OUT"
rm -rf "$OUT"/xcelium.d "$OUT"/*.log "$OUT"/summary.txt
echo "lint-hal: $TOP, $(echo "$files" | wc -w) files, run folder $OUT"

# shellcheck disable=SC2086 # One argument per file
(cd "$OUT" && "$XRUN" -64bit -hal -top "$TOP" -timescale 1ns/1ps \
    -incdir "$REPO/rtl/core" -incdir "$REPO/rtl/bus" -incdir "$REPO/rtl/mem" \
    $(for f in $files; do echo "$REPO/$f"; done) -l xrun.log > /dev/null 2>&1)
status=$?

log=$OUT/hal.log
[ -f "$log" ] || log=$OUT/xrun.log
if [ ! -s "$log" ]; then
    echo "ERROR: no HAL log in $OUT (xrun exit $status). Check that this xrun accepts -hal."
    exit 1
fi

# HAL and xrun messages look like "tool: *W,RULE (file,line|col): text"
{
    echo "lint-hal $(date +%d/%m/%Y) commit $(git rev-parse --short HEAD 2>/dev/null) top $TOP"
    echo "$("$XRUN" -version 2>/dev/null | head -n 1)"
    echo
    echo "Messages per severity:"
    for s in F E W N; do
        echo "  *$s: $(grep -cE "\*$s,[A-Za-z0-9_]+" "$log")"
    done
    echo
    echo "Messages per rule (count, severity, rule):"
    grep -oE '\*[EFWN],[A-Za-z0-9_]+' "$log" | sort | uniq -c | sort -rn | sed 's/^/  /'
} > "$OUT/summary.txt"

cat "$OUT/summary.txt"
n_err=$(grep -cE '\*[EF],[A-Za-z0-9_]+' "$log")
if [ "$n_err" -gt 0 ]; then
    echo "LINT-HAL FAIL: $n_err *E/*F messages, see $log"
    exit 1
fi
echo "LINT-HAL DONE: no *E/*F, warnings listed above (log: $log)"
