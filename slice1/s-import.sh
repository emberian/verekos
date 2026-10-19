#!/usr/bin/env bash
# slice1/s-import.sh TAG STEP — the importer imports both sources (exploration 01 §2.2): a signed
# read of each source cell, the mapper's diff, and a submit only when there is something to submit.
. "$(dirname "$0")/world-lib.sh"
TAG=$1; STEP=$2; C=$(dirname "$0")
D=$RUN/import-$TAG; mkdir -p "$D"
for spec in shop:src-shop:ecommerce.sql:$C/inputs/ecommerce.sql legacy:src-legacy:legacy_customers.sql:$C/fixtures/legacy_customers.sql; do
  IFS=: read -r key cell path file <<<"$spec"
  t0=$(now)
  read_to "$D/$cell-before.json" importer "$cell"
  python3 -I "$C/mapper.py" import --source-key "$key" --path "$path" --file "$file" --cell "$cell" \
    --read "$D/$cell-before.json" --out "$D/$cell.req.json" >"$D/$cell.mapper.txt" 2>&1 || { cat "$D/$cell.mapper.txt"; exit 1; }
  if [ -f "$D/$cell.req.json" ]; then
    submit_req "import-$TAG-$cell" importer "$D/$cell.req.json"
    row "$STEP" "import-$TAG-$cell" "${EXPECT:-installed}" "$(outcome "import-$TAG-$cell")" "$(since "$t0")" \
      "$(cat "$D/$cell.mapper.txt"); sha256 $(sha256sum <"$D/$cell.req.json" | cut -c1-16); $(attempt_dir "import-$TAG-$cell")"
  else
    row "$STEP" "import-$TAG-$cell" "${EXPECT:-installed}" "nothing-submitted" "$(since "$t0")" "$(cat "$D/$cell.mapper.txt")"
  fi
  read_to "$D/$cell-after.json" importer "$cell"
done
