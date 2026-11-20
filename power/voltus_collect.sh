#!/bin/bash
# voltus_collect.sh - LEC-04 preparation: collect what the Voltus script needs. Reads only, runs no tool
# except printing versions. Run on the school server from the repo:
#   bash power/voltus_collect.sh > ~/voltus_info.txt 2>&1
# Then send ~/voltus_info.txt. Nothing here goes to git.
cd "$(dirname "$0")/.." || exit 1
s() { echo; echo "==== $*"; }
s "Tools"
for t in voltus innovus tempus quantus qrc; do printf '%-8s ' $t; command -v $t || echo "(not in PATH)"; done
(voltus -version 2>/dev/null || voltus -help 2>/dev/null) | head -3
s "Post-layout outputs (Sheet: pnr/out_soc_p9, not pre_eco)"
ls -la pnr/out_soc_p9/ 2>&1 | head -30
ls pnr/out_soc_p9/reports/ 2>&1 | head -40
s "pd_checks.rpt (core and die box)"
cat pnr/out_soc_p9/reports/pd_checks.rpt 2>&1 | head -20
s "power.rpt (first lines)"
head -40 pnr/out_soc_p9/reports/power.rpt 2>&1
s "Innovus databases"
ls -d pnr/run_soc*/DBS 2>&1; ls -la pnr/run_soc*/DBS/ 2>&1 | head -30
s "Power plan and nets in the PnR scripts"
grep -n -i -E 'VDD|VSS|globalNetConnect|addRing|addStripe|sroute|power' pnr/scripts/config.tcl pnr/scripts/run_all.tcl pnr/scripts/soc_floorplan.tcl 2>&1 | head -60
s "LEF, lib and RC files referenced by config.tcl"
grep -n -i -E 'lef|lib|qrc|tch|captable|corner|rc_' pnr/scripts/config.tcl 2>&1 | head -40
s "PDK files that Voltus may need (QRC tech, power-grid views, LEF)"
find ~/PDK_GPDK45 -maxdepth 4 \( -iname '*.tch' -o -iname '*qrc*' -o -iname '*.cl' -o -iname '*pgv*' \
     -o -iname '*.lef' -o -iname '*.capTbl' -o -iname '*.ict' \) 2>/dev/null | head -40
s "Lab folders in home (Lab 06 IR drop script, pad file)"
find ~ -maxdepth 3 -iname '*lab*' -type d 2>/dev/null | head -20
find ~ -maxdepth 4 \( -iname '*voltus*' -o -iname '*.pp' -o -iname '*pad*loc*' -o -iname '*vsrc*' -o -iname '*rail*' \) 2>/dev/null | grep -v RV32i-SoC | head -30
s "Repo power folder"
ls -la power/ 2>&1
