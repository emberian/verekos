#!/usr/bin/env bash
# slice1/s-compile.sh TAG STEP — hbox side of slice1/compile.sh: as `compiler`, submit in order the
# requests the Mac's `verekos-map compile` wrote ($RUN/compile-TAG/req, commands.json, mapper.txt).
# MAPSEC: the mapper's seconds on the Mac, for the row.
. "$(dirname "$0")/world-lib.sh"
TAG=$1; STEP=$2; D=$RUN/compile-$TAG
[ -f "$D/req/commands.json" ] || { echo "no $D/req/commands.json (run slice1/compile.sh on the Mac)" >&2; exit 1; }
row "$STEP" "mapper-$TAG" "requests" "$(cat "$D/mapper.txt")" "${MAPSEC:-0}" "$(jq -c '[.requests[] | {cell, actions, transclusions}]' "$D/req/commands.json")"
for f in $(jq -r '.requests[].file' "$D/req/commands.json"); do
  cell=$(jq -r --arg f "$f" '.requests[] | select(.file == $f) | .cell' "$D/req/commands.json")
  t0=$(now)
  submit_req "compile-$TAG-$cell" compiler "$D/req/$f"
  row "$STEP" "compile-$TAG-$cell" installed "$(outcome "compile-$TAG-$cell")" "$(since "$t0")" \
    "$(jq -c --arg f "$f" '.requests[] | select(.file == $f) | {actions, transclusions, births, reads}' "$D/req/commands.json") $( [ "$(outcome "compile-$TAG-$cell")" = installed ] || refusal_text "compile-$TAG-$cell") $(attempt_dir "compile-$TAG-$cell")"
done
