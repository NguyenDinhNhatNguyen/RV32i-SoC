#!/usr/bin/env bash
# soc_cov.sh - code coverage of soc_top with Verilator (VER-05), called by make cov-soc.
# Steps and results in docs/regression.md.
#
# Builds tb_soc with Verilator --coverage-line --coverage-toggle (ENABLE_M=1,
# ENABLE_WFI_SLEEP=1, ENABLE_DMA=1, the M1W1 build of fw-soc), runs every program that
# make fw-soc, fw-soc-c and bench-soc run on that build, then merges the coverage files and
# writes OUT/summary.txt with line and toggle coverage per module.
# Each program must also PASS on Verilator. This is a second simulator next to Icarus.
#
# Environment variables:
#   OUT     Output folder (default tb/cov)
#   JOBS    Parallel runs (default nproc)
#
# The memory images must exist: run make fw-soc fw-soc-c bench-soc first (make regress does).
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO" || exit 1

OUT=${OUT:-tb/cov}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}
OBJ=$OUT/obj
SKIP="rv32ui-p-ma_data rv32mi-p-breakpoint rv32mi-p-pmpaddr"   # CORE_ISA_SKIP in the Makefile

# Programs of the M1W1 build: <dir>/<name>. Same lists as the Makefile.
progs=""
for f in fw/tests/soc/*.S;  do progs="$progs tb/soc/out/soc/fw/$(basename "$f" .S)"; done
for f in fw/tests/bus/*.S;  do progs="$progs tb/soc/out/fw/$(basename "$f" .S)"; done
progs="$progs tb/core/out/fw/smoke tb/core/out/fw/hazard tb/soc/out/soc/fw_c/soc_fw_rv32im"
for g in rv32ui rv32mi rv32um; do
    for f in fw/riscv-tests/isa/$g/*.S; do
        t=$g-p-$(basename "$f" .S)
        case " $SKIP " in *" $t "*) ;; *) progs="$progs tb/core/out/isa/$t" ;; esac
    done
done
for b in dhrystone_rv32im coremark_rv32im accel_bench_rv32im; do
    progs="$progs tb/core/out/bench_soc/$b"
done

missing=""
for p in $progs; do [ -f "$p.tohost" ] || missing="$missing $p.tohost"; done
if [ -n "$missing" ]; then
    echo "ERROR: missing memory images, run make fw-soc fw-soc-c bench-soc first:"
    echo "$missing" | tr ' ' '\n' | head -5
    exit 1
fi

# Build
rm -rf "$OUT"
mkdir -p "$OUT/dat" "$OUT/log"
rtl=$(ls rtl/core/*.v rtl/bus/*.v rtl/mem/*.v rtl/periph/*.v rtl/accel/*.v)
echo "cov-soc: building tb_soc with Verilator coverage"
# shellcheck disable=SC2086 # One argument per file
if ! verilator --binary --timing --coverage-line --coverage-toggle -Wno-fatal -Wno-lint -Wno-style \
        -Irtl/bus -Irtl/mem -Irtl/core --top-module tb_soc \
        -GENABLE_M=1 -GENABLE_WFI_SLEEP=1 -GENABLE_DMA=1 --Mdir "$OBJ" -o Vtb_soc -j "$JOBS" \
        $rtl tb/models/sram_2k_macro.v tb/models/i2c_slave_model.v tb/soc/tb_soc.v \
        > "$OUT/build.log" 2>&1; then
    echo "ERROR: Verilator build failed, see $OUT/build.log"
    tail -n 20 "$OUT/build.log"
    exit 1
fi

# Run, one coverage file per program
run_one() {
    p=$1
    t=$(basename "$p")
    log=$OUT/log/$t.log
    "$OBJ/Vtb_soc" +imem="$p.imem.hex" +dmem="$p.dmem.hex" +"$(cat "$p.tohost")" +test="$t/cov" \
        +timeout=50000000 +verilator+coverage+file+"$OUT/dat/$t.dat" > "$log" 2>&1
    # Verilator prints the PASS line of tb_soc as numbers: its format string is a concatenation
    # {"...", "..."}, which Icarus accepts as text. The FAIL line is a plain string and prints
    # normally. tb_soc only calls $finish in end_test, so a run passes when it reaches $finish
    # with no FAIL or ERROR line (timeout, trap and UART errors all print FAIL).
    if grep -q 'Verilog \$finish' "$log" && ! grep -q '^FAIL' "$log" &&
       ! grep '^ERROR' "$log" | grep -vq 'at least 10 secs'; then
        echo "  PASS $t"
    else
        echo "  [FAIL] $t (log: $log)"
    fi
}
export -f run_one
export OUT OBJ
n=$(echo $progs | wc -w)
echo "cov-soc: running $n programs"
echo $progs | tr ' ' '\n' | xargs -P "$JOBS" -I{} bash -c 'run_one {}' > "$OUT/runs.txt"
pass=$(grep -c '^  PASS' "$OUT/runs.txt")
fail=$(grep -c '^  \[FAIL\]' "$OUT/runs.txt")
grep '^  \[FAIL\]' "$OUT/runs.txt"

verilator_coverage --write "$OUT/merged.dat" "$OUT"/dat/*.dat > /dev/null
verilator_coverage --annotate "$OUT/annotated" --annotate-min 1 "$OUT/merged.dat" > /dev/null 2>&1

# Per module summary from the merged file
python3 - "$OUT/merged.dat" "$pass" "$n" > "$OUT/summary.txt" <<'EOF'
import re, sys, collections
path, npass, nprog = sys.argv[1], sys.argv[2], sys.argv[3]
cnt = collections.defaultdict(lambda: [0, 0])
lines = collections.OrderedDict()             # (file, line) -> hits, line points only
for line in open(path, errors="replace"):
    if not line.startswith("C "):
        continue
    key, val = line[2:].rsplit(" ", 1)
    key = key.strip("'")
    f = dict(p.split("\x02", 1) for p in key.split("\x01") if "\x02" in p)
    kind = f.get("page", "").split("/")[0].replace("v_", "")
    fn = f.get("f", "")
    # Only RTL modules. Not the testbench, the macro model or boot_rom_init.vh (a ROM table
    # whose 143 case lines would inflate the total).
    if not fn.startswith("rtl/") or not fn.endswith(".v"):
        continue
    mod = fn.split("/")[-1]
    c = cnt[(mod, kind)]
    c[1] += 1
    if int(val) > 0:
        c[0] += 1
    if kind == "line":
        k = (fn, int(f.get("l", 0)))
        lines[k] = lines.get(k, 0) + int(val)
mods = sorted({m for m, _ in cnt})
def pct(m, k):
    hit, tot = cnt.get((m, k), [0, 0])
    return f"{100.0 * hit / tot:5.1f}% ({hit}/{tot})" if tot else "    -"
print(f"cov-soc: {npass}/{nprog} programs PASS on Verilator, ENABLE_M=1 WFI_SLEEP=1 DMA=1")
print()
print(f"{'module file':<22} {'line':<22} {'toggle':<22}")
tot = {"line": [0, 0], "toggle": [0, 0]}
for m in mods:
    print(f"{m:<22} {pct(m, 'line'):<22} {pct(m, 'toggle'):<22}")
    for k in tot:
        h, t = cnt.get((m, k), [0, 0])
        tot[k][0] += h
        tot[k][1] += t
print()
for k, (h, t) in tot.items():
    print(f"RTL total {k}: {100.0 * h / t:.1f}% ({h}/{t})")
print()
print("Lines never reached:")
for (fn, ln), hits in lines.items():
    if hits == 0:
        src = open(fn, errors="replace").read().splitlines()[ln - 1].strip()
        print(f"  {fn}:{ln}  {src[:80]}")
EOF
cat "$OUT/summary.txt"
echo "cov-soc: $pass passed, $fail failed. Uncovered lines: $OUT/annotated (lines starting with %000000)"
[ "$fail" -eq 0 ]
