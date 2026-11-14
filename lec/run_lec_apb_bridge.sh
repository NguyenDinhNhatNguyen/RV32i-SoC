#!/bin/bash
# run_lec_apb_bridge.sh - block-level LEC of apb_bridge (RTL vs Genus block netlist).
# Run on the school server from anywhere in the repo:
#   nohup bash lec/run_lec_apb_bridge.sh > ~/lec_apb.txt 2>&1 &
# Env: NET_DIR=<folder with apb_bridge_netlist.v>  (default: the only syn/out_block*/apb_bridge)
set -u
cd "$(dirname "$0")/.." || exit 1
NET_DIR=${NET_DIR:-$(ls -d syn/out_block*/apb_bridge 2>/dev/null | head -1)}
NET=$NET_DIR/apb_bridge_netlist.v
[ -f "$NET" ] || { echo "ERROR: netlist not found ($NET). Set NET_DIR."; exit 1; }
OUT=${OUT:-syn/out_apb_bridge_lec}
mkdir -p "$OUT/reports"; cp "$NET" "$OUT/apb_bridge_netlist.v"
echo "netlist : $NET ($(date -r "$NET" '+%d/%m %H:%M'))"
echo "summary : $(cat "$NET_DIR/summary.txt" 2>/dev/null)"
newer=$(find rtl/bus/apb_bridge.v rtl/bus/soc_map.vh -newer "$NET" 2>/dev/null)
if [ -n "$newer" ]; then
  echo "WARNING: newer than the netlist (RTL changed after synthesis, LEC will probably fail on parameters/ports):"
  echo "$newer" | sed 's/^/   /'
  echo "         Re-synthesize the block first (make synth-blocks / synth-block)."
fi
sed -e "s|@@NETLIST@@|$OUT/apb_bridge_netlist.v|g" -e "s|@@OUTDIR@@|$OUT/reports|g" \
    lec/apb_bridge_rtl2gate.do.in > lec/apb_bridge_rtl2gate.do
[ "${DRY_RUN:-0}" = 1 ] && { echo "DRY_RUN: dofile written, lec not started"; exit 0; }
command -v lec >/dev/null || { echo "ERROR: lec not found"; exit 1; }
s=$(date +%s)
lec -nogui -dofile lec/apb_bridge_rtl2gate.do < /dev/null > "$OUT/lec.txt" 2>&1 || true
echo "lec finished after $(( ($(date +%s)-s)/60 )) min"
grep -E 'Compare Results|Non-equivalent|Equivalent|Abort|Unmapped|// Error' "$OUT/lec.txt" | tail -15
echo "Reports: $OUT/reports (do not commit netlist copies)"
