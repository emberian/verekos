#!/usr/bin/env bash
# slice1/s2-setup.sh — step 2, world: a fresh private Store (newparticipant-acceptance.sh, the
# script journey J0 runs), five principals enrolled with --new-key, the rooms `shop` and
# `legacy`, the source / review / compile-run / attestation cells born by the sponsor (the
# only owner) under the four laws with real subject ids, and the grants.
. "$(dirname "$0")/world-lib.sh"
[ ! -e "$RUN" ] || { echo "run root exists: $RUN" >&2; exit 2; }
mkdir -p "$BASE"; mkdir -m 700 "$RUN"; mkdir -p "$L" "$R" "$RX"
: >"$RUN/receipts.tsv"
( cd "$TIP" && sha256sum -c SHA256SUMS ) >"$RUN/sha256-check.txt" 2>&1 || { cat "$RUN/sha256-check.txt"; exit 2; }
jq -n --arg h "$HOST" --arg m "$MINI" --arg s "$STORE" --arg v "$VERIFIER" '{host:$h,mini:$m,store:$s,verifier:$v,shell:$m}' \
  | jq --slurpfile x <(cd "$TIP" && sha256sum minidregg-host mini minidregg-link-sqlite-store minidregg-credential-signature-verifier \
       | jq -R 'split("  ") | {(.[1]):.[0]}' | jq -s add) \
  '. + {sha256:{host:$x[0]["minidregg-host"],mini:$x[0].mini,store:$x[0]["minidregg-link-sqlite-store"],
         verifier:$x[0]["minidregg-credential-signature-verifier"],shell:$x[0].mini}}' >"$RUN/manifest.json"
df -h / | tail -1 >"$RUN/disk-before.txt"

t0=$(now)
run bootstrap sh "$RCDIR/newparticipant-acceptance.sh" "$HOST" "$MINI" "$STORE" "$VERIFIER" "$W" "$SOCKET"; ok bootstrap
row S2 bootstrap up "$(cat "$W/public/server.pid" 2>/dev/null)" "$(since "$t0")" "server.pid $(cat "$W/public/server.pid")"

t0=$(now)
declare -A SUBJ
for p in importer compiler reviewer verifier reader-shop; do SUBJ[$p]=$(enroll "$p"); done
SUBJ[owner]=$(jq -r .subject "$SPONSOR_WS/workspace.json")
jq -n --arg o "${SUBJ[owner]}" --arg i "${SUBJ[importer]}" --arg c "${SUBJ[compiler]}" --arg r "${SUBJ[reviewer]}" \
  --arg v "${SUBJ[verifier]}" --arg s "${SUBJ[reader-shop]}" \
  '{owner:$o,importer:$i,compiler:$c,reviewer:$r,verifier:$v,"reader-shop":$s}' >"$RUN/principals.json"
row S2 enroll-5 "5 subjects" "$(jq -r '[.[]] | length - 1' "$RUN/principals.json") subjects" "$(since "$t0")" "$(jq -c . "$RUN/principals.json")"

python3 -I "$(dirname "$0")/laws.py" "$(dirname "$0")/../laws" "$RUN/laws" owner="${SUBJ[owner]}" importer="${SUBJ[importer]}" \
  compiler="${SUBJ[compiler]}" reviewer="${SUBJ[reviewer]}" verifier="${SUBJ[verifier]}" >"$RUN/laws.tsv" || exit 1
printf '%s\n' '{"type":"all","predicates":[]}' >"$RUN/laws/permit-all.json"

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
