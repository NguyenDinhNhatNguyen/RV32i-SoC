#!/bin/bash
# precheck_lec02.sh - checks before the full LEC-02 run (about 5 minutes less than a wasted 106 min run).
# Run on the school server from the repo:  bash lec/precheck_lec02.sh [PHAT_COMMIT]
# PHAT_COMMIT = commit used for the STA-04 synthesis (ask Phat). Optional.
set -u
cd "$(dirname "$0")/.." || exit 1
NET=${NET:-syn/out_soc/soc_top_netlist.v}
echo "== 1. Netlist"
[ -f "$NET" ] || { echo "FAIL: $NET not found"; exit 1; }
echo "file    : $(ls -la "$NET" | awk '{print $5, $6, $7, $8}')"
echo "summary : $(cat "$(dirname "$NET")/summary.txt" 2>/dev/null || echo 'no summary.txt')"
echo "== 2. Old constant flops must be gone (expect 0)"
# Only the 4 registers of LEC-01, matched with their block, so a state_reg[3] of another block
# (for example a 4-bit FSM elsewhere) is not counted
pat='uart[^ ]*tx_sh_reg\[8\]|spi[^ ]*ctrl_div_reg\[(8|9|1[0-5])\]|i2c[^ ]*state_reg\[3\]|core[^ ]*wb_cause_q_reg\[4\]'
hits=$(grep -o -E "$pat" "$NET" | sort -u)
n=$(printf '%s' "$hits" | grep -c .)
echo "matches : $n"
[ -n "$hits" ] && echo "$hits" | sed 's/^/   /'
[ "$n" = 0 ] && echo "OK" || echo "FAIL: the netlist still has the old registers listed above. Do not run LEC, ask Phat."
echo "all state_reg[3] in the netlist (info only):"
grep -o -E '[^ (]*state_reg\[3\]' "$NET" | sort -u | sed 's/^/   /' 
echo "== 3. Repo"
git status --short | head
echo "branch  : $(git rev-parse --abbrev-ref HEAD)   commit: $(git log -1 --format='%h %s')"
if [ -n "${1:-}" ]; then
  echo "== 4. RTL changed since $1 (expect nothing)"
  git diff --stat "$1" HEAD -- rtl
fi
echo "== 5. Tools"
command -v lec >/dev/null && echo "lec: ok" || echo "FAIL: lec not found"
echo "== 6. Dry run"
DRY_RUN=1 LEC_DIR=${LEC_DIR:-syn/out_soc_lec3} bash lec/run_lec_soc.sh | tail -8
echo "Run for real:  LEC_DIR=syn/out_soc_lec3 nohup bash lec/run_lec_soc.sh > ~/lec_soc_run3.txt 2>&1 &"
