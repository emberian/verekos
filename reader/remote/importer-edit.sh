#!/usr/bin/env bash
# reader/remote/importer-edit.sh PHASE MINI WS CELL OUT PROPOSAL-ID
# SCENE ONLY, and a WORLD WRITE, run on the node by reader/edit_as_importer.py. The mapping is done
# on the Mac by `verekos-map`; this script only reads and submits, as the importer (workspace WS):
#   PHASE read:   a signed read of CELL -> OUT/before.json (with the reference's target added)
#   PHASE submit: propose + submit OUT/req.json (written on the Mac), logs under OUT
# It is not part of the reader: the reader never runs it.
set -uo pipefail
umask 077
PHASE=$1; MINI=$2; WS=$3; CELL=$4; OUT=$5; PID=$6
mkdir -p "$OUT"; t0=$(date +%s.%N)
case $PHASE in
read)
  nice -n 10 "$MINI" workspace --action read --dir "$WS" --name "$CELL" >"$OUT/before.raw" 2>"$OUT/read.err" || { echo "importer read failed: $(tail -2 "$OUT/read.err")"; exit 1; }
  jq --arg t "$(jq -r .target "$WS/refs/$CELL.json")" '. + {target:$t}' "$OUT/before.raw" >"$OUT/before.json" ;;
submit)
  [ -f "$OUT/req.json" ] || { echo "no $OUT/req.json"; exit 1; }
  nice -n 10 "$MINI" workspace --action propose --dir "$WS" --request "$OUT/req.json" --proposal-id "$PID" >"$OUT/propose.out" 2>"$OUT/propose.err" || { echo "propose failed: $(tail -2 "$OUT/propose.err")"; exit 1; }
  nice -n 10 "$MINI" workspace --action submit --dir "$WS" --intent "$WS/proposals/$PID/intent.json" --attempt "$WS/attempts/$PID" >"$OUT/submit.out" 2>"$OUT/submit.err"; rc=$?
  secs=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}')
  echo "submitted rc=$rc ($secs s): $(cat "$OUT/mapper.txt" 2>/dev/null); request sha256 $(sha256sum <"$OUT/req.json" | cut -c1-16)"
  [ $rc = 0 ] || tail -3 "$OUT/submit.err"
  exit $rc ;;
*) echo "phase must be read or submit" >&2; exit 2 ;;
esac
