#!/usr/bin/env bash
# soc_run.sh - chạy một lần mô phỏng tb_soc, gọi từ make fw-soc.
#
#   soc_run.sh <thư mục vvp> <thư mục test>/<tên>@<cấu hình>
#
# Ảnh bộ nhớ và địa chỉ tohost lấy từ <thư mục test>/<tên>.{imem.hex,dmem.hex,tohost}
# (do rule elf2hex tạo). Dòng LOI của mô hình macro (X trên chân) cũng là FAIL.
# In đúng một dòng PASS, hoặc dòng [FAIL] kèm 20 dòng cuối log.
set -u

vvp_dir=$1
run=$2
dt=${run%%@*}
cfg=${run#*@}
dir=${dt%/*}
t=${dt##*/}
log=$vvp_dir/$t.$cfg.log

# shellcheck disable=SC2086 # plusarg tách theo dấu cách là chủ ý
if ${VVP:-vvp} -n "$vvp_dir/tb_soc_$cfg.vvp" +imem="$dir/$t.imem.hex" +dmem="$dir/$t.dmem.hex" \
       +"$(cat "$dir/$t.tohost")" +test="$t/$cfg" ${PLUSARGS:-} > "$log" 2>&1 &&
   grep -q '^PASS' "$log" && ! grep -q '^FAIL\|^LOI' "$log"; then
    msg="  $(grep '^PASS' "$log" | tail -n 1)"
else
    msg="  [FAIL] $t/$cfg (log: $log)"$'\n'"$(tail -n 20 "$log" | sed 's/^/      /')"
fi
# Một lần printf để dòng của các tiến trình chạy song song không xen nhau
printf '%s\n' "$msg"
