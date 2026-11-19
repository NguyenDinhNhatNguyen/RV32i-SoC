#!/usr/bin/env bash
# gls_soc.sh - gate-level simulation of the soc_top netlist with tb_soc -DGLS (VER-07).
# Called by make gls-soc (server, Xcelium) and make gls-soc-home (Yosys netlist, Icarus).
# Steps in docs/gls_soc.md.
#
# Environment variables:
#   SIM         xrun (default) or iverilog
#   NETLIST     Netlist (default syn/out_soc/soc_top_netlist.v, the Genus netlist of STA-04)
#   GLS_LIB     Verilog model of the cells (default ~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v)
#   MACRO_V     Model of sram_2k_macro. Default with xrun: the real model
#               ~/PDK_GPDK45/lib/sram_2k_macro.v if it exists. Otherwise tb/models/sram_2k_macro.v
#               (the home model, same pins)
#   MACRO_MEM   Name of the word array in MACRO_V (default: the one 2-D reg found in MACRO_V)
#   SDF         Empty (default): zero delay, clock 10 ns. A file: annotate it (VER-08), the
#               clock period then comes from HALF (default 5 ns)
#   HALF        Half clock period in ns (default 5)
#   T           Test names (default every program of the fw-soc M1W1 build, see list_tests)
#   OUT         Run folder (default syn/out_soc/gls)
#   gls_soc.sh --list   prints the memory image files the tests need, for copying to the server
#
# The netlist keeps the 8 sram_2k_macro instances as cells. scripts/gls_paths.py finds them and
# writes OUT/gls_paths.vh, which tb_soc includes to load the programs and to see the tohost
# write. tb_soc loads the programs into the word array of the macro model (MACRO_MEM, define
# GLS_MEM), one word per address, address 0 first, like the home model.
# Prints one PASS line per test, then a summary line, and exits 1 if any test failed.
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO" || exit 1
absp() { case $1 in /*) echo "$1" ;; *) echo "$REPO/$1" ;; esac; }

SIM=${SIM:-xrun}
NETLIST=${NETLIST:-syn/out_soc/soc_top_netlist.v}
GLS_LIB=${GLS_LIB:-${PDK_DIR:-$HOME/PDK_GPDK45}/lib/slow_vdd1v0_basiccells.v}
PDK_MACRO_V=${PDK_DIR:-$HOME/PDK_GPDK45}/lib/sram_2k_macro.v
if [ -z "${MACRO_V:-}" ]; then
    if [ "$SIM" = xrun ] && [ -f "$PDK_MACRO_V" ]; then MACRO_V=$PDK_MACRO_V; else MACRO_V=tb/models/sram_2k_macro.v; fi
fi
SDF=${SDF:-}
HALF=${HALF:-5}
OUT=${OUT:-syn/out_soc/gls}
SKIP="rv32ui-p-ma_data rv32mi-p-breakpoint rv32mi-p-pmpaddr"   # CORE_ISA_SKIP in the Makefile

# Programs of the fw-soc M1W1 build (the netlist has ENABLE_M=1, ENABLE_WFI_SLEEP=1,
# ENABLE_DMA=1): <image dir>/<name>, same lists as the Makefile
list_tests() {
    local f g t
    for f in fw/tests/soc/*.S; do echo "tb/soc/out/soc/fw/$(basename "$f" .S)"; done
    for f in fw/tests/bus/*.S; do echo "tb/soc/out/fw/$(basename "$f" .S)"; done
    echo tb/core/out/fw/smoke
    echo tb/core/out/fw/hazard
    echo tb/soc/out/soc/fw_c/soc_fw_rv32im
    if [ -d fw/riscv-tests/isa/rv32ui ]; then
        for g in rv32ui rv32mi rv32um; do
            for f in fw/riscv-tests/isa/$g/*.S; do
                t=$g-p-$(basename "$f" .S)
                case " $SKIP " in *" $t "*) ;; *) echo "tb/core/out/isa/$t" ;; esac
            done
        done
    else
        ls tb/core/out/isa/rv32u[im]-p-*.tohost tb/core/out/isa/rv32mi-p-*.tohost 2>/dev/null |
            sed 's/\.tohost$//' | while read -r t; do
                case " $SKIP " in *" $(basename "$t") "*) ;; *) echo "$t" ;; esac
            done
    fi
}

if [ "${1:-}" = "--list" ]; then
    list_tests | while read -r p; do echo "$p.imem.hex $p.dmem.hex $p.tohost"; done | tr ' ' '\n'
    exit 0
fi

progs=$(list_tests)
if [ -n "${T:-}" ]; then
    progs=$(for p in $progs; do case " $T " in *" $(basename "$p") "*) echo "$p" ;; esac; done)
fi
[ -n "$progs" ] || { echo "ERROR: no test selected (T=$T)"; exit 1; }

case $SIM in
    xrun)     command -v xrun > /dev/null || { echo "ERROR: xrun not found, gls-soc runs on the school server"; exit 1; } ;;
    iverilog) command -v iverilog > /dev/null || { echo "ERROR: iverilog not found"; exit 1; } ;;
    *)        echo "ERROR: SIM must be xrun or iverilog"; exit 1 ;;
esac
[ -f "$NETLIST" ] || { echo "ERROR: no netlist $NETLIST (make synth-soc on the server)"; exit 1; }
[ -f "$GLS_LIB" ] || { echo "ERROR: cannot find the cell model $GLS_LIB (set GLS_LIB or PDK_DIR)"; exit 1; }
[ -z "$SDF" ] || [ -f "$SDF" ] || { echo "ERROR: SDF file $SDF not found"; exit 1; }
[ -f "$MACRO_V" ] || { echo "ERROR: cannot find the macro model $MACRO_V"; exit 1; }

missing=""
for p in $progs; do [ -f "$p.tohost" ] || missing="$missing $p"; done
if [ -n "$missing" ]; then
    echo "ERROR: missing memory images for:$(echo "$missing" | cut -c1-300)"
    echo "       At home: make fw-soc fw-soc-c, then make gls-soc-pack and copy the tarball"
    echo "       to the server (docs/gls_soc.md step 2)."
    exit 1
fi

mkdir -p "$OUT"
rm -rf "$OUT"/xcelium.d "$OUT"/*.log "$OUT"/gls.vvp "$OUT"/summary.txt
python3 scripts/gls_paths.py "$NETLIST" -o "$OUT/gls_paths.vh" 2> "$OUT/gls_paths.log" ||
    { cat "$OUT/gls_paths.log"; exit 1; }
sed 's/^/  /' "$OUT/gls_paths.log"

# Name of the word array in the macro model: MACRO_MEM, or the one 2-D reg of MACRO_V
if [ -z "${MACRO_MEM:-}" ]; then
    arrs=$(sed 's://.*$::' "$MACRO_V" | grep -oE '\breg\b[^;]*\[[^]]*\][[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\[[^]]*\]' |
           sed -E 's/.*\][[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\[[^]]*\]$/\1/' | sort -u)
    if [ "$(echo "$arrs" | grep -c .)" -ne 1 ]; then
        echo "ERROR: cannot tell the word array of $MACRO_V (found: $(echo $arrs))."
        echo "       Set MACRO_MEM=<array name>, see docs/gls_soc.md."
        exit 1
    fi
    MACRO_MEM=$arrs
fi
echo "  macro model $MACRO_V, word array \"$MACRO_MEM\""

defs=(GLS "GLS_HALF=$HALF" "GLS_MEM=$MACRO_MEM")
[ -z "$SDF" ] || defs+=("GLS_SDF=\"$(absp "$SDF")\"")
if [ -z "$SDF" ]; then mode="zero delay, clock $((HALF * 2)) ns"; else mode="SDF $SDF, clock $((HALF * 2)) ns"; fi
echo "gls-soc: $NETLIST, $SIM, $mode, $(echo "$progs" | wc -w) tests"

# Compile once. tb_soc sets `default_nettype none, so it goes last.
srcs=("$(absp "$GLS_LIB")" "$(absp "$NETLIST")" "$(absp "$MACRO_V")"
      "$REPO/tb/models/i2c_slave_model.v" "$REPO/tb/soc/tb_soc.v")
if [ "$SIM" = xrun ]; then
    xdefs=()
    for d in "${defs[@]}"; do xdefs+=(-define "$d"); done
    timing=()
    [ -n "$SDF" ] || timing=(-nospecify -notimingchecks)
    if ! (cd "$OUT" && xrun -64bit -elaborate -timescale 1ns/1ps "${xdefs[@]}" ${timing[@]+"${timing[@]}"} \
            -incdir "$REPO/$OUT" -top tb_soc -snapshot gls_soc "${srcs[@]}" \
            -l elab.log > /dev/null 2>&1); then
        echo "ERROR: xrun elaboration failed, see $OUT/elab.log"
        grep -E '\*[EF],' "$OUT/elab.log" | head -10
        exit 1
    fi
else
    idefs=()
    for d in "${defs[@]}"; do idefs+=(-D"$d"); done
    if ! iverilog -g2012 "${idefs[@]}" -I"$OUT" -s tb_soc -o "$OUT/gls.vvp" "${srcs[@]}" \
            > "$OUT/elab.log" 2>&1; then
        echo "ERROR: iverilog failed, see $OUT/elab.log"
        head -10 "$OUT/elab.log"
        exit 1
    fi
fi

pass=0
fail=0
for p in $progs; do
    t=$(basename "$p")
    log=$OUT/$t.log
    args=(+imem="$REPO/$p.imem.hex" +dmem="$REPO/$p.dmem.hex" +"$(cat "$p.tohost")"
          +test="$t/gls" +timeout=2000000)
    if [ "$SIM" = xrun ]; then
        (cd "$OUT" && xrun -64bit -R -snapshot gls_soc "${args[@]}" -l "$REPO/$log" > /dev/null 2>&1)
    else
        vvp -n "$OUT/gls.vvp" "${args[@]}" > "$log" 2>&1
    fi
    if grep -q '^PASS' "$log" && ! grep -qE '^(FAIL|ERROR)' "$log"; then
        echo "  $(grep '^PASS' "$log" | tail -n 1)"
        pass=$((pass + 1))
    else
        echo "  [FAIL] $t (log: $log)"
        grep -E '^(FAIL|ERROR)|\*[EF],' "$log" | head -5 | sed 's/^/      /'
        fail=$((fail + 1))
    fi
done | tee "$OUT/summary.txt"
pass=$(grep -c '^  PASS' "$OUT/summary.txt")
fail=$(grep -c '^  \[FAIL\]' "$OUT/summary.txt")
echo "gls-soc: $pass passed, $fail failed" | tee -a "$OUT/summary.txt"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
