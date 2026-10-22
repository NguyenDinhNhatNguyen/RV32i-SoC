#!/usr/bin/env bash
# arch_run.sh - dịch một test riscv-arch-test và chạy trên tb_core, ghi signature.
# Dùng chung cho plugin RISCOF (tb/riscof/rv32_core) và make arch-core-dut.
#
#   arch_run.sh <cấu hình M0W1|M1W1> <test.S> <thư mục làm việc> [macro ...]
#
# Macro là các "NAME=VALUE" (không có -D), lấy từ RVTEST_CASE của test.
# Kết quả trong thư mục làm việc: my.elf, DUT-rv32_core.signature, tb.log.
# In một dòng PASS hoặc [FAIL], mã thoát 0 khi PASS.
set -u

cfg=$1
src=$(realpath "$2")
work=$3
shift 3

root=$(cd "$(dirname "$0")/.." && pwd)
env_dir=$root/tb/riscof/rv32_core/env
suite_env=$root/fw/riscv-arch-test/riscv-test-suite/env
vvp_file=$root/tb/core/out/tb_core_arch_$cfg.vvp
imem_size=${ARCH_IMEM_SIZE:-2097152}     # phải khớp lúc dịch tb_core_arch_*.vvp
prefix=${RV_PREFIX:-riscv64-unknown-elf}
name=$(basename "$src" .S)

case $cfg in
    M1*) march=rv32im_zicsr_zifencei ;;
    *)   march=rv32i_zicsr_zifencei ;;
esac

mkdir -p "$work"
cd "$work" || exit 1
rm -f my.elf DUT-rv32_core.signature tb.log

defs=()
for m in "$@"; do defs+=("-D$m"); done

fail() {
    echo "  [FAIL] $name/$cfg: $1 (log: $work/tb.log)"
    exit 1
}

"$prefix-gcc" -march=$march -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden \
    -nostdlib -nostartfiles -T "$env_dir/link.ld" -I "$env_dir" -I "$suite_env" \
    -DXLEN=32 "${defs[@]}" -o my.elf "$src" > tb.log 2>&1 || fail "compile"

sym() { "$prefix-nm" my.elf | awk -v s="$1" '$3 == s { print $1 }'; }
begin=$(sym begin_signature)
end=$(sym end_signature)
[ -n "$begin" ] && [ -n "$end" ] || fail "no begin_signature/end_signature"

tohost=$(python3 "$root/scripts/elf2hex.py" my.elf --imem my.imem.hex --dmem my.dmem.hex \
         --imem-size "$imem_size" 2>>tb.log) || fail "elf2hex"

${VVP:-vvp} -n "$vvp_file" +imem=my.imem.hex +dmem=my.dmem.hex +"$tohost" +test="$name/$cfg" \
    +signature=DUT-rv32_core.signature +sig_begin="$begin" +sig_end="$end" \
    +timeout=${ARCH_TIMEOUT:-5000000} >> tb.log 2>&1
grep -q '^PASS' tb.log && ! grep -q '^FAIL' tb.log || fail "$(grep -m1 '^FAIL' tb.log || echo 'no PASS line')"
rm -f my.imem.hex my.dmem.hex
echo "  $(grep '^PASS' tb.log | tail -n 1), signature $(wc -l < DUT-rv32_core.signature) words"
