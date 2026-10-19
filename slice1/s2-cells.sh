#!/usr/bin/env bash
# slice1/s2-cells.sh — step 2, world, second half (after slice1/laws.sh on the Mac wrote $RUN/laws):
# the rooms `shop` and `legacy`, the source / review / compile-run / attestation cells born by the
# sponsor (the only owner) under the four laws with real subject ids, and the grants.
. "$(dirname "$0")/world-lib.sh"
for f in permit-all L-src L-rev L-run-compiler L-run-verifier L-obj; do
  [ -f "$RUN/laws/$f.json" ] || { echo "no $RUN/laws/$f.json (run slice1/laws.sh on the Mac)" >&2; exit 1; }
done
t0=$(now)
create shop "$RUN/laws/permit-all.json" declared
create legacy "$RUN/laws/permit-all.json" declared
create src-shop "$RUN/laws/L-src.json" content shop
create src-legacy "$RUN/laws/L-src.json" content legacy
create review "$RUN/laws/L-rev.json" content
create compile-run "$RUN/laws/L-run-compiler.json" content
create attestation "$RUN/laws/L-run-verifier.json" content
row S2 rooms-and-cells "7 born" "$(ls "$SPONSOR_WS/refs" | grep -c -E '^(shop|legacy|src-shop|src-legacy|review|compile-run|attestation)\.json$') born" "$(since "$t0")" \
  "src-shop in $(jq -r '.birth.resources[0].room // "-"' "$SPONSOR_WS/sources/create-src-shop.json" 2>/dev/null)"

t0=$(now)
O='["observe"]'; OM='["observe","mutate"]'
delegate g-imp-shop src-shop importer "$OM" src-shop
delegate g-imp-legacy src-legacy importer "$OM" src-legacy
delegate g-cmp-shop src-shop compiler "$O" src-shop
delegate g-cmp-legacy src-legacy compiler "$O" src-legacy
delegate g-cmp-run compile-run compiler "$OM" compile-run
delegate g-cmp-review review compiler "$OM" review          # held, so R3 is the law's refusal, not a missing grant
delegate g-rev-review review reviewer "$OM" review
delegate g-ver-att attestation verifier "$OM" attestation
for c in src-shop src-legacy compile-run review; do delegate "g-ver-$c" "$c" verifier "$O" "$c"; done
delegate g-reader-shop shop reader-shop "$O" shop room
row S2 grants "14 delegations" "$(ls -d "$SPONSOR_WS"/proposals/g-* | wc -l) delegations" "$(since "$t0")" "reader-shop holds a room delegation on shop only"
