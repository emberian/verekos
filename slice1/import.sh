#!/usr/bin/env bash
# slice1/import.sh TAG STEP — the importer imports both sources (exploration 01 §2.2): signed reads of
# each source cell on hbox, the diff by `verekos-map import` here, and a submit on hbox
# (s-import.sh) only when there is something to submit. Env: LEGACY_FILE (a Mac path), EXPECT.
set -euo pipefail
. "$(dirname "$0")/mac-lib.sh"
TAG=$1; STEP=$2; L=$LOCALRUN/import-$TAG
mkdir -p "$L"
hread "import-$TAG/before" "$L/before" importer src-shop src-legacy
ssh hbox "rm -f \$HOME/$RRUN/import-$TAG/*.req.json"
sent=()
for spec in "shop:src-shop:ecommerce.sql:$HERE/inputs/ecommerce.sql" "legacy:src-legacy:legacy_customers.sql:${LEGACY_FILE:-$HERE/fixtures/legacy_customers.sql}"; do
  IFS=: read -r key cell path file <<<"$spec"
  rm -f "$L/$cell.req.json"
  "$MAP" import --source-key "$key" --path "$path" --file "$file" --cell "$cell" \
    --read "$L/before/$cell.json" --out "$L/$cell.req.json" >"$L/$cell.mapper.txt"
  sent+=("$L/$cell.mapper.txt"); [ -f "$L/$cell.req.json" ] && sent+=("$L/$cell.req.json")
done
hput "${sent[@]}" "import-$TAG"
ssh hbox "export RUNID=$RUNID EXPECT='${EXPECT:-}'; bash $RC/s-import.sh $TAG $STEP"
