#!/usr/bin/env bash
# core_run.sh - chạy một lần mô phỏng tb_core, gọi từ make fw-core / isa-core.
#
#   core_run.sh <thư mục vvp> <thư mục test>/<tên>@<cấu hình>@<chế độ>
#
# Ảnh bộ nhớ và địa chỉ tohost lấy từ <thư mục test>/<tên>.{imem.hex,dmem.hex,tohost}.
# Plusarg của chế độ lấy từ biến môi trường CORE_PLUS_<chế độ>, thêm PLUSARGS
# nếu có. In đúng một dòng PASS, hoặc dòng [FAIL] kèm 20 dòng cuối log.
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

# shellcheck disable=SC2086 # plusarg tách theo dấu cách là chủ ý
if ${VVP:-vvp} -n "$vvp_dir/tb_core_$cfg.vvp" +imem="$dir/$t.imem.hex" +dmem="$dir/$t.dmem.hex" \
       +"$(cat "$dir/$t.tohost")" +test="$t/$cfg/$mode" ${!plus_var:-} ${PLUSARGS:-} > "$log" 2>&1 &&
   grep -q '^PASS' "$log" && ! grep -q '^FAIL' "$log"; then
    msg="  $(grep '^PASS' "$log" | tail -n 1)"
else
    msg="  [FAIL] $t/$cfg/$mode (log: $log)"$'\n'"$(tail -n 20 "$log" | sed 's/^/      /')"
fi
# Một lần printf để dòng của các tiến trình chạy song song không xen nhau
printf '%s\n' "$msg"
