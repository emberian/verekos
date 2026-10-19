#!/usr/bin/env bash
# slice1/s-cells.sh PLAN.json — the owner (sponsor) creates the compiled cells the mapper's plan
# names, each under its law and room, and grants: compiler observe+mutate, verifier observe,
# reviewer observe on conflicts, reader-shop a reference through its room capability.
# Also `obj-r2`, a spare L-obj cell for the R2 refusal. Writes $RUN/cells.json (name -> target).
. "$(dirname "$0")/world-lib.sh"
PLAN=$1
t0=$(now)
O='["observe"]'; OM='["observe","mutate"]'
rows=$(jq -c '.[]' "$PLAN"; echo '{"cell":"obj-r2","law":"L-obj","room":"shop"}')
while read -r r; do
  cell=$(jq -r .cell <<<"$r"); law=$(jq -r .law <<<"$r"); room=$(jq -r '.room // ""' <<<"$r")
  [ -f "$SPONSOR_WS/refs/$cell.json" ] && continue
  create "$cell" "$RUN/laws/$law.json" content "$room"
  delegate "g-cmp-$cell" "$cell" compiler "$OM" "$cell"
  delegate "g-ver-$cell" "$cell" verifier "$O" "$cell"
  case $cell in cf-*) delegate "g-rev-$cell" "$cell" reviewer "$O" "$cell";; esac
  if [ "$room" = shop ]; then
    import_via reader-shop "$cell" "$(target_of "$cell")" "$(jq -r .observeCapability "$(ws_of reader-shop)/refs/shop.json")"
  fi
done <<<"$rows"
for c in src-shop src-legacy; do
  [ -f "$(ws_of reader-shop)/refs/$c.json" ] || import_via reader-shop "$c" "$(target_of "$c")" "$(jq -r .observeCapability "$(ws_of reader-shop)/refs/shop.json")"
done
for f in "$SPONSOR_WS"/refs/*.json; do n=$(basename "$f" .json); printf '%s\t%s\n' "$n" "$(jq -r .target "$f")"; done \
  | jq -R 'split("\t") | {(.[0]):.[1]}' | jq -s add >"$RUN/cells.json"
row "${STEP:-S2}" compiled-cells "$(( $(jq length "$PLAN") + 1 )) born" "$(jq --slurpfile p "$PLAN" '. as $c | [$p[0][].cell, "obj-r2"] | map(select($c[.] != null)) | length' "$RUN/cells.json") born" "$(since "$t0")" \
  "rooms: $(jq -r '[.[] | "\(.cell)=\(.room // "none")"] | join(" ")' "$PLAN")"
