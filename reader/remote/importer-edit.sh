#!/usr/bin/env bash
# reader/remote/importer-edit.sh MINI WS CELL KEY PATH NEWFILE MAPPER OUT PROPOSAL-ID
# SCENE ONLY, and a WORLD WRITE: the importer principal (workspace WS) reads CELL, diffs the
# statements in NEWFILE against it with slice 1's mapper (`import`, vendored), and submits the
# one request if there is something to submit. This is slice1/s-import.sh for one cell, with
# its logs under OUT. It is not part of the reader: the reader never runs it.
set -uo pipefail
umask 077
MINI=$1; WS=$2; CELL=$3; KEY=$4; PATHN=$5; NEW=$6; MAPPER=$7; OUT=$8; PID=$9
mkdir -p "$OUT"; t0=$(date +%s.%N)
nice -n 10 "$MINI" workspace --action read --dir "$WS" --name "$CELL" >"$OUT/before.raw" 2>"$OUT/read.err" || { echo "importer read failed: $(tail -2 "$OUT/read.err")"; exit 1; }
jq --arg t "$(jq -r .target "$WS/refs/$CELL.json")" '. + {target:$t}' "$OUT/before.raw" >"$OUT/before.json"
if [ -n "${ATOM_KEY:-}" ]; then   # one editAtom with NEW's whole text as the payload of that statement atom
  python3 -I "$(dirname "$MAPPER")/../edit-atom.py" "$(dirname "$MAPPER")" "$OUT/before.json" "$KEY" "$ATOM_KEY" "$CELL" "$NEW" "$OUT/req.json" >"$OUT/mapper.txt" 2>&1 || { cat "$OUT/mapper.txt"; exit 1; }
else
  python3 -I "$MAPPER" import --source-key "$KEY" --path "$PATHN" --file "$NEW" --cell "$CELL" --read "$OUT/before.json" --out "$OUT/req.json" >"$OUT/mapper.txt" 2>&1 || { cat "$OUT/mapper.txt"; exit 1; }
fi
if [ ! -f "$OUT/req.json" ]; then echo "nothing to submit ($(cat "$OUT/mapper.txt"))"; exit 0; fi
nice -n 10 "$MINI" workspace --action propose --dir "$WS" --request "$OUT/req.json" --proposal-id "$PID" >"$OUT/propose.out" 2>"$OUT/propose.err" || { echo "propose failed: $(tail -2 "$OUT/propose.err")"; exit 1; }
nice -n 10 "$MINI" workspace --action submit --dir "$WS" --intent "$WS/proposals/$PID/intent.json" --attempt "$WS/attempts/$PID" >"$OUT/submit.out" 2>"$OUT/submit.err"; rc=$?
secs=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}')
echo "submitted rc=$rc ($secs s): $(cat "$OUT/mapper.txt"); request sha256 $(sha256sum <"$OUT/req.json" | cut -c1-16)"
[ $rc = 0 ] || tail -3 "$OUT/submit.err"
exit $rc
