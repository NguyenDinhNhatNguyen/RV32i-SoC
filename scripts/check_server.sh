#!/usr/bin/env bash
# Checks the environment on the school server (HT-01).
# Usage (in MobaXterm, after sourcing the Cadence environment as in the Labs):
#   bash scripts/check_server.sh            # scan the default folders
#   bash scripts/check_server.sh /extra/path ...       # scan extra folders
# The result goes to appendix/server_check/server_check_<date>.txt, send it to Phat.
# Read only, it never modifies or copies anything.

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

section "1. Cadence tools (searched in PATH)"
for t in xrun genus innovus tempus voltus joules lec pegasus pvs virtuoso; do
  p=$(command -v "$t" 2>/dev/null)
  if [ -n "$p" ]; then
    v=$("$t" -version 2>/dev/null | head -n 2 | tr '\n' ' ')
    log "[OK]  $t -> $p  ${v}"
  else
    log "[--]  $t not in PATH (you may need to source another environment script)"
  fi
done

section "2. Related environment variables"
# Drop the long PATH and hide the license server address before writing to the file
env | grep -iE 'cds|cadence|gpdk|gsclib|pdk|lm_license|cdslmd' | grep -vE '^(PATH|SPECMAN_PATH|LD_LIBRARY_PATH)=' \
  | sed -E 's/^((LM_LICENSE_FILE|CDS_LIC_FILE)=).*/\1(hidden)/; s/^/  /' | tee -a "$OUT" >/dev/null
env | grep -iE 'cds|cadence|gpdk|gsclib|pdk|lm_license|cdslmd' >/dev/null || log "  (no matching variables)"

section "3. GPDK45 libraries (the Lab PDK_GPDK45 folder, gsclib045)"
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || continue
  find "$r" -maxdepth "$MAXDEPTH" -path '*.enc.dat' -prune -o \( -iname 'PDK_GPDK45' -o -iname 'gsclib045*' -o -iname 'gpdk045*' -o -iname 'gpdk45*' \) -print 2>/dev/null
done | sort -u | head -n 40 | sed 's/^/  /' | tee -a "$OUT"

section "4. Cell library timing/LEF files (slow/fast/typical)"
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || continue
  find "$r" -maxdepth "$MAXDEPTH" -path '*.enc.dat' -prune -o \( -path '*gsclib045*' -o -path '*PDK_GPDK45*' \) \( -iname '*basiccells*.lib' -o -name '*.lef' -o -name '*.tch' -o -name '*.qrcTech' -o -name '*.capTbl' -o -name '*.map' -o -name '*.gds' \) -print 2>/dev/null
done | sort -u | head -n 60 | sed 's/^/  /' | tee -a "$OUT"

section "5. SRAM macro (LEF/LIB/GDS/Verilog)"
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || continue
  find "$r" -maxdepth "$MAXDEPTH" -iname '*sram*' \( -name '*.lef' -o -name '*.lib' -o -name '*.gds*' -o -name '*.v' -o -name '*.cdl' -o -name '*.sp' \) -print 2>/dev/null
done | sort -u | head -n 80 | sed 's/^/  /' | tee -a "$OUT"

section "6. SRAM macro size (SIZE read from the LEF)"
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || continue
  find "$r" -maxdepth "$MAXDEPTH" -iname '*sram*.lef' -print 2>/dev/null
done | sort -u | head -n 20 | while read -r f; do
  awk -v F="$f" '{sub(/\r$/,"")} /^MACRO/{m=$2} /^[ \t]*SIZE/{printf "  %s: MACRO %s SIZE %s x %s um\n", F, m, $2, $4}' "$f"
done | tee -a "$OUT"
log "  Note: words x bits is usually in the macro name or the .lib file (look for 'address_width'/'word_width' or pin names A[..], D[..])."

section "7. Toolchain RISC-V"
found=0
for t in riscv32-unknown-elf-gcc riscv64-unknown-elf-gcc riscv-none-elf-gcc riscv64-linux-gnu-gcc; do
  p=$(command -v "$t" 2>/dev/null)
  if [ -n "$p" ]; then found=1; log "[OK]  $t -> $p  $($t --version | head -n1)"; fi
done
[ $found -eq 1 ] || log "[--]  No RISC-V toolchain on the server: build firmware at home and copy the .hex files up."

section "8. Python / git on the server"
for t in python3 git make tmux; do
  p=$(command -v "$t" 2>/dev/null); [ -n "$p" ] && log "[OK]  $t -> $p" || log "[--]  $t"
done
log "  GitHub access: $(timeout 8 git ls-remote https://github.com/git/git.git HEAD >/dev/null 2>&1 && echo 'yes (use git pull/push directly)' || echo 'no (use scp through MobaXterm)')"

section "9. Home disk space"
df -h "$HOME" 2>/dev/null | tail -n 1 | sed 's/^/  /' | tee -a "$OUT"

log ""
log "Tip: set PDK_DIR=<PDK_GPDK45 path from section 3> before make synth-accel / make pnr-accel."
log "Done. Send this file to Phat: $OUT"
