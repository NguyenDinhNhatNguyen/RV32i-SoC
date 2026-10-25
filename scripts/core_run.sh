#!/usr/bin/env bash
# core_run.sh - runs one tb_core simulation, called from make fw-core / isa-core.
#
#   core_run.sh <vvp dir> <test dir>/<name>@<config>@<mode>
#
# Memory images and the tohost address come from <test dir>/<name>.{imem.hex,dmem.hex,tohost}.
# Mode plusargs come from the CORE_PLUS_<mode> environment variable, plus PLUSARGS
# if set. Prints exactly one PASS line, or a [FAIL] line with the last 20 log lines.
set -u

vvp_dir=$1
run=$2
dt=${run%%@*}
rest=${run#*@}
cfg=${rest%%@*}
mode=${rest#*@}
dir=${dt%/*}
t=${dt##*/}
log=$dir/$t.$cfg.$mode.log
plus_var=CORE_PLUS_$mode

# shellcheck disable=SC2086 # Splitting plusargs on spaces is intended
if ${VVP:-vvp} -n "$vvp_dir/tb_core_$cfg.vvp" +imem="$dir/$t.imem.hex" +dmem="$dir/$t.dmem.hex" \
       +"$(cat "$dir/$t.tohost")" +test="$t/$cfg/$mode" ${!plus_var:-} ${PLUSARGS:-} > "$log" 2>&1 &&
   grep -q '^PASS' "$log" && ! grep -q '^FAIL' "$log"; then
    msg="  $(grep '^PASS' "$log" | tail -n 1)"
else
    msg="  [FAIL] $t/$cfg/$mode (log: $log)"$'\n'"$(tail -n 20 "$log" | sed 's/^/      /')"
fi
# A single printf so lines from parallel processes do not interleave
printf '%s\n' "$msg"
