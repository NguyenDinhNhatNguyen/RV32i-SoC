#!/usr/bin/env bash
# gls_core.sh - gate-level simulation of the rv32_core netlist (make synth-core) with Xcelium,
# on tb_core built with -DGLS, running riscv-tests rv32ui and rv32um (server only).
# Called by make gls-core, steps in docs/genus_core.md.
#
# Environment variables:
#   NETLIST   Netlist (default syn/out_core/rv32_core_syn_netlist.v)
#   GLS_LIB   Verilog model of the cells (default ~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v)
#   SDF       auto (default): annotate syn/out_core/rv32_core_syn.sdf if it exists,
#             0: zero delay, 1: SDF required
#   T         Test names (default every rv32ui-p-* and rv32um-p-*, like isa-core)
#   HEX_DIR   Memory images from make isa-core (default tb/core/out/isa)
#   OUT       Run folder (default syn/out_core/gls)
#
# Zero delay runs with a 10 ns clock like the RTL tb. The SDF run uses a 20 ns clock, the
# PERIOD of the default synthesis. Prints one PASS line per test, then a summary line, and
# exits 1 if any test failed.
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO" || exit 1

NETLIST=${NETLIST:-syn/out_core/rv32_core_syn_netlist.v}
GLS_LIB=${GLS_LIB:-${PDK_DIR:-$HOME/PDK_GPDK45}/lib/slow_vdd1v0_basiccells.v}
SDF=${SDF:-auto}
SDF_FILE=$(dirname "$NETLIST")/rv32_core_syn.sdf
HEX_DIR=${HEX_DIR:-tb/core/out/isa}
OUT=${OUT:-syn/out_core/gls}
XRUN=${XRUN:-xrun}
# Same exclusion as CORE_ISA_SKIP in the Makefile (docs/riscv-tests-status.md)
SKIP="rv32ui-p-ma_data"

if ! command -v "$XRUN" > /dev/null; then
    echo "ERROR: $XRUN not found, gls-core runs on the school server"
    exit 1
fi
[ -f "$NETLIST" ] || { echo "ERROR: no netlist $NETLIST, run make synth-core first"; exit 1; }
[ -f "$GLS_LIB" ] || { echo "ERROR: cannot find the cell model $GLS_LIB (set GLS_LIB or PDK_DIR)"; exit 1; }

# Test list: from the riscv-tests sources if the submodule is there, else from HEX_DIR
if [ -n "${T:-}" ]; then
    tests=$T
elif [ -d fw/riscv-tests/isa/rv32ui ]; then
    tests=$(for g in rv32ui rv32um; do
                for f in fw/riscv-tests/isa/$g/*.S; do echo "$g-p-$(basename "$f" .S)"; done
            done)
else
    tests=$(ls "$HEX_DIR"/rv32u[im]-p-*.tohost 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.tohost$//')
fi
tests=$(for t in $tests; do case " $SKIP " in *" $t "*) ;; *) echo "$t" ;; esac; done)
[ -n "$tests" ] || { echo "ERROR: no test found (no fw/riscv-tests and no $HEX_DIR/*.tohost)"; exit 1; }

# Memory images: build them with make when riscv gcc is present, otherwise they must be copied
missing=""
for t in $tests; do
    [ -f "$HEX_DIR/$t.tohost" ] || missing="$missing $HEX_DIR/$t.tohost"
done
if [ -n "$missing" ]; then
    if command -v riscv64-unknown-elf-gcc > /dev/null || command -v riscv-none-elf-gcc > /dev/null ||
       command -v riscv32-unknown-elf-gcc > /dev/null; then
        # shellcheck disable=SC2086 # One make target per file
        make -s $missing || { echo "ERROR: could not build the riscv-tests images"; exit 1; }
    else
        echo "ERROR: missing memory images in $HEX_DIR and no riscv gcc on this machine."
        echo "       At home: make isa-core, then copy tb/core/out/isa/*.{imem.hex,dmem.hex,tohost}"
        echo "       to $HEX_DIR on the server (docs/genus_core.md step 4)."
        exit 1
    fi
fi

# SDF or zero delay
defs=(-define GLS)
timing=(-nospecify -notimingchecks)
case $SDF in
    0) mode="zero delay" ;;
    1|auto)
        if [ -f "$SDF_FILE" ]; then
            defs+=(-define GLS_HALF=10 -define "GLS_SDF=\"$REPO/$SDF_FILE\"")
            timing=()
            mode="SDF $SDF_FILE, 20 ns clock"
        elif [ "$SDF" = 1 ]; then
            echo "ERROR: SDF=1 but $SDF_FILE does not exist"
            exit 1
        else
            mode="zero delay (no $SDF_FILE)"
        fi ;;
    *) echo "ERROR: SDF must be auto, 0 or 1"; exit 1 ;;
esac

mkdir -p "$OUT"
rm -rf "$OUT"/xcelium.d "$OUT"/*.log
echo "gls-core: $NETLIST, $mode"

# Compile and elaborate once. tb_core sets `default_nettype none, so it goes last and the
# cell models do not see it.
if ! (cd "$OUT" && "$XRUN" -64bit -elaborate -timescale 1ns/1ps "${defs[@]}" "${timing[@]}" \
        -incdir "$REPO/tb/core" -incdir "$REPO/rtl/core" \
        -defparam tb_core.ENABLE_M=1 -defparam tb_core.ENABLE_WFI_SLEEP=1 \
        -top tb_core -snapshot gls_core \
        "$GLS_LIB" "$REPO/$NETLIST" "$REPO/tb/models/sram_1rw_model.v" "$REPO/tb/core/tb_core.v" \
        -l elab.log > /dev/null 2>&1); then
    echo "ERROR: xrun elaboration failed, see $OUT/elab.log"
    grep -E '\*[EF],' "$OUT/elab.log" | head -10
    exit 1
fi

pass=0
fail=0
for t in $tests; do
    log=$OUT/$t.log
    (cd "$OUT" && "$XRUN" -64bit -R -snapshot gls_core \
        +imem="$REPO/$HEX_DIR/$t.imem.hex" +dmem="$REPO/$HEX_DIR/$t.dmem.hex" \
        +"$(cat "$HEX_DIR/$t.tohost")" +test="$t/gls" -l "$REPO/$log" > /dev/null 2>&1)
    if grep -q '^PASS' "$log" && ! grep -qE '^(FAIL|ERROR)' "$log"; then
        echo "  $(grep '^PASS' "$log" | tail -n 1)"
        pass=$((pass + 1))
    else
        echo "  [FAIL] $t (log: $log)"
        grep -E '^(FAIL|ERROR)|\*[EF],' "$log" | head -5 | sed 's/^/      /'
        fail=$((fail + 1))
    fi
done
echo "gls-core: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
