#!/usr/bin/env bash
# regress.sh - full regression of the RTL at home in the team Docker image (VER-05).
# Called by make regress, steps and results in docs/regression.md.
#
# Environment variables:
#   LIST    Make targets to run, in order (default: every functional target below)
#   QUICK   1 skips the slow targets (arch-core-dut, bench-core, bench-soc)
#   CLEAN   1 deletes the simulation outputs first, so every test is rebuilt from source
#   OUT     Log folder (default tb/regress)
#
# Each target runs on its own with its log in OUT/<target>.log. A target passes when make
# exits 0 and the log has no line starting with "FAIL" (some unit benches print FAIL but end
# with exit 0). The last result line of each target goes into OUT/summary.txt. Exits 1 if any
# target failed. Every target still runs after a failure.
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO" || exit 1

OUT=${OUT:-tb/regress}
SLOW="arch-core-dut bench-core bench-soc"
FULL="lint-all unit-core unit-bus unit-periph sim-accel sim-accel-apb \
fw-core isa-core fw-bus fw-soc fw-soc-c sim-boot $SLOW"
if [ -n "${LIST:-}" ]; then
    list=$LIST
elif [ "${QUICK:-0}" = 1 ]; then
    list=$(for t in $FULL; do case " $SLOW " in *" $t "*) ;; *) echo "$t" ;; esac; done)
else
    list=$FULL
fi

if [ "${CLEAN:-0}" = 1 ]; then
    echo "regress: CLEAN=1, deleting tb/unit/out tb/core/out tb/soc/out tb/boot/out tb/riscof/out"
    rm -rf tb/unit/out tb/core/out tb/soc/out tb/boot/out tb/riscof/out
fi

mkdir -p "$OUT"
rm -f "$OUT"/*.log "$OUT"/summary.txt

# Last line that states a result, for the table
result_line() {
    grep -E '(passed|failed|PASS|FAIL)' "$1" | grep -vE '^\s+(PASS|\[ OK \])' | tail -n 1 |
        sed 's/^ *//' | cut -c1-90
}

commit=$(git rev-parse --short HEAD 2>/dev/null)
dirty=$(git status --porcelain -- rtl tb fw scripts Makefile 2>/dev/null | head -n 1)
{
    echo "regress $(date +%d/%m/%Y\ %H:%M) commit $commit${dirty:+ (local changes)}"
    echo "$(verilator --version 2>/dev/null | head -n 1), $(iverilog -V 2>&1 | head -n 1 | cut -d' ' -f1-4)"
    echo "$(${RV_PREFIX:-riscv64-unknown-elf}-gcc --version 2>/dev/null | head -n 1)"
    echo
    printf '%-14s %-6s %7s  %s\n' target result time "last result line"
} > "$OUT/summary.txt"
cat "$OUT/summary.txt"

fail=0
t_all=$(date +%s)
for t in $list; do
    log=$OUT/$t.log
    t0=$(date +%s)
    make --no-print-directory "$t" > "$log" 2>&1
    rc=$?
    dt=$(( $(date +%s) - t0 ))
    if [ $rc -eq 0 ] && ! grep -qE '^FAIL' "$log"; then
        res=PASS
    else
        res=FAIL
        fail=$((fail + 1))
    fi
    line=$(printf '%-14s %-6s %6ds  %s' "$t" "$res" "$dt" "$(result_line "$log")")
    echo "$line" | tee -a "$OUT/summary.txt"
done

n=$(echo $list | wc -w)
{
    echo
    echo "total $(( $(date +%s) - t_all ))s, $((n - fail))/$n targets passed"
    if [ $fail -eq 0 ]; then echo "REGRESS PASS"; else echo "REGRESS FAIL (logs in $OUT)"; fi
} | tee -a "$OUT/summary.txt"
[ $fail -eq 0 ]
