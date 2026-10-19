#!/usr/bin/env bash
# slice1/s-import.sh TAG STEP — hbox side of slice1/import.sh: for each source cell, submit the request
# the Mac's `verekos-map import` wrote ($RUN/import-TAG/CELL.req.json, with CELL.mapper.txt) as the
# importer, or record that there was nothing to submit; then a signed read of the cell after.
. "$(dirname "$0")/world-lib.sh"
TAG=$1; STEP=$2
D=$RUN/import-$TAG; mkdir -p "$D"
for cell in src-shop src-legacy; do
  t0=$(now)
  [ -f "$D/$cell.mapper.txt" ] || { echo "no $D/$cell.mapper.txt (run slice1/import.sh on the Mac)" >&2; exit 1; }
  if [ -f "$D/$cell.req.json" ]; then
    submit_req "import-$TAG-$cell" importer "$D/$cell.req.json"
    row "$STEP" "import-$TAG-$cell" "${EXPECT:-installed}" "$(outcome "import-$TAG-$cell")" "$(since "$t0")" \
      "$(cat "$D/$cell.mapper.txt"); sha256 $(sha256sum <"$D/$cell.req.json" | cut -c1-16); $(attempt_dir "import-$TAG-$cell")"
  else
    row "$STEP" "import-$TAG-$cell" "${EXPECT:-installed}" "nothing-submitted" "$(since "$t0")" "$(cat "$D/$cell.mapper.txt")"
  fi
  read_to "$D/$cell-after.json" importer "$cell"
done
