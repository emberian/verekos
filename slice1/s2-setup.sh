#!/usr/bin/env bash
# slice1/s2-setup.sh — step 2, world, first half: a fresh private Store (newparticipant-acceptance.sh,
# the script journey J0 runs) and five principals enrolled with --new-key ($RUN/principals.json).
# Then the Mac renders the laws with those subjects (slice1/laws.sh) and s2-cells.sh does the rest.
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

