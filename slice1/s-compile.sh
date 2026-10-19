#!/usr/bin/env bash
# slice1/s-compile.sh TAG STEP — as `compiler`: the mapper's requests for compile TAG (export at
# $RUN/compile-TAG/export.ndjson, source reads already taken), each submitted in order, then the
# compile-run append. With CURRENT=1 the compiled cells' present documents are read first (recompile).
. "$(dirname "$0")/world-lib.sh"
TAG=$1; STEP=$2; C=$(dirname "$0"); D=$RUN/compile-$TAG
cur=()
if [ "${CURRENT:-0}" = 1 ]; then
  for cell in $(jq -r '.[].cell' "$D/plan.json"); do read_to "$D/cur-$cell.json" compiler "$cell"; cur+=(--current "$cell=$D/cur-$cell.json"); done
fi
t0=$(now)
python3 -I "$C/mapper.py" compile --export "$D/export.ndjson" --source shop="$D/src-shop.json" --source legacy="$D/src-legacy.json" \
  --cells "$RUN/cells.json" --ekos-version "$(cat "$D/ekos-version.txt")" --out "$D/req" "${cur[@]}" >"$D/mapper.txt" 2>&1 || { cat "$D/mapper.txt"; exit 1; }
row "$STEP" "mapper-$TAG" "requests" "$(cat "$D/mapper.txt")" "$(since "$t0")" "$(jq -c '[.requests[] | {cell, actions, transclusions}]' "$D/req/commands.json")"
for f in $(jq -r '.requests[].file' "$D/req/commands.json"); do
  cell=$(jq -r --arg f "$f" '.requests[] | select(.file == $f) | .cell' "$D/req/commands.json")
  t0=$(now)
  submit_req "compile-$TAG-$cell" compiler "$D/req/$f"
  row "$STEP" "compile-$TAG-$cell" installed "$(outcome "compile-$TAG-$cell")" "$(since "$t0")" \
    "$(jq -c --arg f "$f" '.requests[] | select(.file == $f) | {actions, transclusions, births, reads}' "$D/req/commands.json") $( [ "$(outcome "compile-$TAG-$cell")" = installed ] || refusal_text "compile-$TAG-$cell") $(attempt_dir "compile-$TAG-$cell")"
done
t0=$(now)
runrec=()
[ "$TAG" != 1 ] && { read_to "$D/compile-run-before.json" compiler compile-run; runrec=(--read "$D/compile-run-before.json"); }
python3 -I "$C/mapper.py" runrec --dir "$D/req" --source shop="$D/src-shop.json" --source legacy="$D/src-legacy.json" \
  --cell compile-run --ekos-version "$(cat "$D/ekos-version.txt")" --out "$D/compile-run.req.json" "${runrec[@]}" >"$D/runrec.txt" 2>&1 || { cat "$D/runrec.txt"; exit 1; }
submit_req "compile-$TAG-run" compiler "$D/compile-run.req.json"
row "$STEP" "compile-$TAG-run" installed "$(outcome "compile-$TAG-run")" "$(since "$t0")" "$(cat "$D/runrec.txt") $( [ "$(outcome "compile-$TAG-run")" = installed ] || refusal_text "compile-$TAG-run")"
