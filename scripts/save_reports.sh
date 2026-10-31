#!/usr/bin/env bash
# save_reports.sh - copies the text reports of a flow run into appendix/ for the repo.
# Usage (on the server, from the repo folder):
#   bash scripts/save_reports.sh pnr/out_soc/reports appendix/pnr_soc
#   make save-pnr-soc            (same, plus a check of what git would commit)
# Only report files are copied (.rpt .txt .log .summary .htm .ascii and their .gz).
# Netlists, SPEF, SDF, GDS, LEF, .lib and databases are skipped, because they are built from
# the school PDK and must never reach the public repo.

set -u
SRC=${1:?usage: save_reports.sh <reports folder> <appendix folder>}
DST=${2:?usage: save_reports.sh <reports folder> <appendix folder>}
[ -d "$SRC" ] || { echo "ERROR: $SRC not found, run the flow first"; exit 1; }
case "$DST" in
    appendix/*) ;;
    *) echo "ERROR: the destination must be inside appendix/"; exit 1 ;;
esac

n_copy=0
n_skip=0
while IFS= read -r -d '' f; do
    rel=${f#"$SRC"/}
    case "$f" in
        *.rpt|*.rpt.gz|*.txt|*.log|*.summary|*.summary.gz|*.tarpt|*.tarpt.gz|*.htm|*.ascii|\
        *.cap.gz|*.fanout.gz|*.length.gz|*.tran.gz)
            mkdir -p "$DST/$(dirname "$rel")"
            cp "$f" "$DST/$rel"
            n_copy=$((n_copy + 1)) ;;
        *)
            echo "Skipped: $rel"
            n_skip=$((n_skip + 1)) ;;
    esac
done < <(find "$SRC" -type f -print0)

echo "Copied $n_copy files to $DST, skipped $n_skip."
echo "Check before committing: git status --short $DST"
