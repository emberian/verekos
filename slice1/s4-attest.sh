#!/usr/bin/env bash
# slice1/s4-attest.sh TAG STEP CLAIMED REPLAYED — hbox side of slice1/replay.sh: the compare of the
# verifier's export and requests (written on the Mac by EKOS and `verekos-map compile`) with the
# compile's, and the attestation append (L-run) the Mac's `verekos-map attest` wrote.
. "$(dirname "$0")/world-lib.sh"
TAG=$1; STEP=$2; claimed=$3; replayed=$4; D=$RUN/replay-$TAG
t0=$(now)
cmp -s "$D/export.ndjson" "$RUN/compile-$TAG/export.ndjson" && same_export=identical || same_export=differs
# the export header carries generated_at and the workspace path; the records after it are compared
cmp -s <(tail -n +2 "$D/export.ndjson") <(tail -n +2 "$RUN/compile-$TAG/export.ndjson") && same_body=identical || same_body=differs
row "$STEP" "R7a-replay-$TAG" "$claimed" "$replayed" "$(since "$t0")" "export body $same_body (whole file $same_export); requests $(jq '.requests|length' "$D/req/commands.json"); request files byte-identical: $(diff -rq "$D/req" "$RUN/compile-$TAG/req" >/dev/null && echo yes || echo no)"
t0=$(now)
[ -f "$D/attest.req.json" ] || { echo "no attestation request: $(cat "$D/attest.txt")" >&2; exit 1; }
submit_req "attest-$TAG" verifier "$D/attest.req.json"
row "$STEP" "attestation-$TAG" installed "$(outcome "attest-$TAG")" "$(since "$t0")" "$(cat "$D/attest.txt") $( [ "$(outcome "attest-$TAG")" = installed ] || refusal_text "attest-$TAG")"
