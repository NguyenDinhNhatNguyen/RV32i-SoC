#!/usr/bin/env bash
# Kiểm tra môi trường trên server trường (HT-01).
# Cách dùng (trong MobaXterm, đã source môi trường Cadence như khi làm Lab):
#   bash scripts/check_server.sh            # quét các thư mục mặc định
#   bash scripts/check_server.sh /duong/dan/them ...   # quét thêm thư mục
# Kết quả ghi vào appendix/server_check/server_check_<ngày>.txt, gửi file này cho Phát.
# Script chỉ đọc, không sửa hay copy gì.

set -u
OUTDIR="$(cd "$(dirname "$0")/.." && pwd)/appendix/server_check"
mkdir -p "$OUTDIR"
OUT="$OUTDIR/server_check_$(date +%Y%m%d_%H%M).txt"

ROOTS=(/tools /opt /cad /eda /usr/local /home/cadence /home/tools "$HOME" "$@")
MAXDEPTH=7

log() { echo "$*" | tee -a "$OUT"; }
section() { log ""; log "==== $* ===="; }

: > "$OUT"
log "Server check $(date '+%Y-%m-%d %H:%M')  host=$(hostname)  user=$(whoami)"
log "OS: $(uname -sr)"

section "1. Tool Cadence (tìm trong PATH)"
for t in xrun genus innovus tempus voltus joules lec pegasus pvs virtuoso; do
  p=$(command -v "$t" 2>/dev/null)
  if [ -n "$p" ]; then
    v=$("$t" -version 2>/dev/null | head -n 2 | tr '\n' ' ')
    log "[OK]  $t -> $p  ${v}"
  else
    log "[--]  $t không có trong PATH (có thể cần source script môi trường khác)"
  fi
done

section "2. Biến môi trường liên quan"
# Bỏ PATH dài và che địa chỉ license server trước khi ghi ra file
env | grep -iE 'cds|cadence|gpdk|gsclib|pdk|lm_license|cdslmd' | grep -vE '^(PATH|SPECMAN_PATH|LD_LIBRARY_PATH)=' \
  | sed -E 's/^((LM_LICENSE_FILE|CDS_LIC_FILE)=).*/\1(da an)/; s/^/  /' | tee -a "$OUT" >/dev/null
env | grep -iE 'cds|cadence|gpdk|gsclib|pdk|lm_license|cdslmd' >/dev/null || log "  (không thấy biến nào)"

section "3. Thư viện GPDK45 (thư mục PDK_GPDK45 của Lab, gsclib045)"
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || continue
  find "$r" -maxdepth "$MAXDEPTH" -path '*.enc.dat' -prune -o \( -iname 'PDK_GPDK45' -o -iname 'gsclib045*' -o -iname 'gpdk045*' -o -iname 'gpdk45*' \) -print 2>/dev/null
done | sort -u | head -n 40 | sed 's/^/  /' | tee -a "$OUT"

section "4. File timing/LEF của thư viện cell (slow/fast/typical)"
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || continue
  find "$r" -maxdepth "$MAXDEPTH" -path '*.enc.dat' -prune -o \( -path '*gsclib045*' -o -path '*PDK_GPDK45*' \) \( -iname '*basiccells*.lib' -o -name '*.lef' -o -name '*.tch' -o -name '*.qrcTech' -o -name '*.capTbl' -o -name '*.map' -o -name '*.gds' \) -print 2>/dev/null
done | sort -u | head -n 60 | sed 's/^/  /' | tee -a "$OUT"

section "5. SRAM macro (LEF/LIB/GDS/Verilog)"
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || continue
  find "$r" -maxdepth "$MAXDEPTH" -iname '*sram*' \( -name '*.lef' -o -name '*.lib' -o -name '*.gds*' -o -name '*.v' -o -name '*.cdl' -o -name '*.sp' \) -print 2>/dev/null
done | sort -u | head -n 80 | sed 's/^/  /' | tee -a "$OUT"

section "6. Kích thước SRAM macro (đọc SIZE trong LEF)"
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || continue
  find "$r" -maxdepth "$MAXDEPTH" -iname '*sram*.lef' -print 2>/dev/null
done | sort -u | head -n 20 | while read -r f; do
  awk -v F="$f" '{sub(/\r$/,"")} /^MACRO/{m=$2} /^[ \t]*SIZE/{printf "  %s: MACRO %s SIZE %s x %s um\n", F, m, $2, $4}' "$f"
done | tee -a "$OUT"
log "  Ghi chú: số word x số bit thường nằm trong tên macro hoặc file .lib (tìm 'address_width'/'word_width' hoặc tên pin A[..], D[..])."

section "7. Toolchain RISC-V"
found=0
for t in riscv32-unknown-elf-gcc riscv64-unknown-elf-gcc riscv-none-elf-gcc riscv64-linux-gnu-gcc; do
  p=$(command -v "$t" 2>/dev/null)
  if [ -n "$p" ]; then found=1; log "[OK]  $t -> $p  $($t --version | head -n1)"; fi
done
[ $found -eq 1 ] || log "[--]  Không có toolchain RISC-V trên server: build firmware ở nhà rồi copy file .hex lên."

section "8. Python / git trên server"
for t in python3 git make tmux; do
  p=$(command -v "$t" 2>/dev/null); [ -n "$p" ] && log "[OK]  $t -> $p" || log "[--]  $t"
done
log "  Kết nối GitHub: $(timeout 8 git ls-remote https://github.com/git/git.git HEAD >/dev/null 2>&1 && echo 'được (dùng git pull/push trực tiếp)' || echo 'không được (dùng scp qua MobaXterm)')"

section "9. Dung lượng home"
df -h "$HOME" 2>/dev/null | tail -n 1 | sed 's/^/  /' | tee -a "$OUT"

log ""
log "Gợi ý: đặt PDK_DIR=<đường dẫn PDK_GPDK45 ở mục 3> trước khi chạy make synth-accel / make pnr-accel."
log "Xong. Gửi file này cho Phát: $OUT"
