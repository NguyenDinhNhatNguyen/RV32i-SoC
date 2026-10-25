#!/usr/bin/env bash
# bus_run.sh - runs one tb_core_bus simulation, called from make fw-bus.
#
#   bus_run.sh <vvp dir> <test dir>/<name>@<config>
#
# Memory images and the tohost address come from <test dir>/<name>.{imem.hex,dmem.hex,tohost}
# (made by the core elf2hex rule). An ERROR line from the macro model (X on a pin) is also a FAIL.
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
if ${VVP:-vvp} -n "$vvp_dir/tb_core_bus_$cfg.vvp" +imem="$dir/$t.imem.hex" +dmem="$dir/$t.dmem.hex" \
       +"$(cat "$dir/$t.tohost")" +test="$t/$cfg" ${PLUSARGS:-} > "$log" 2>&1 &&
   grep -q '^PASS' "$log" && ! grep -q '^FAIL\|^ERROR' "$log"; then
    msg="  $(grep '^PASS' "$log" | tail -n 1)"
else
    msg="  [FAIL] $t/$cfg (log: $log)"$'\n'"$(tail -n 20 "$log" | sed 's/^/      /')"
fi
# A single printf so lines from parallel processes do not interleave
printf '%s\n' "$msg"
