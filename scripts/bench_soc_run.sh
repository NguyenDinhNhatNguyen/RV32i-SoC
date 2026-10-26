#!/usr/bin/env bash
# bench_soc_run.sh - runs one benchmark on tb_soc, called from make bench-soc.
#
#   bench_soc_run.sh <vvp dir> <test dir>/<name>@<config>
#
# Same as soc_run.sh, except that the CoreMark line "ERROR! Must execute for at least 10 secs"
# is expected in simulation (as in bench-core) and does not fail the run. Any other line
# starting with ERROR (for example X on a macro pin) still fails it.
# Prints exactly one PASS line, or a [FAIL] line with the last 20 log lines.
set -u

vvp_dir=$1
run=$2
dt=${run%%@*}
cfg=${run#*@}
dir=${dt%/*}
t=${dt##*/}
log=$vvp_dir/$t.$cfg.log

# shellcheck disable=SC2086 # Splitting plusargs on spaces is intended
if ${VVP:-vvp} -n "$vvp_dir/tb_soc_$cfg.vvp" +imem="$dir/$t.imem.hex" +dmem="$dir/$t.dmem.hex" \
       +"$(cat "$dir/$t.tohost")" +test="$t/$cfg" ${PLUSARGS:-} > "$log" 2>&1 &&
   grep -q '^PASS' "$log" && ! grep -q '^FAIL' "$log" &&
   ! grep '^ERROR' "$log" | grep -vq 'at least 10 secs'; then
    msg="  $(grep '^PASS' "$log" | tail -n 1)"
else
    msg="  [FAIL] $t/$cfg (log: $log)"$'\n'"$(tail -n 20 "$log" | sed 's/^/      /')"
fi
# A single printf so lines from parallel processes do not interleave
printf '%s\n' "$msg"
