#!/usr/bin/env bash
# slice1/s4-empty.sh — R7b's control: the empty command the importer never sends, sent once by hand.
. "$(dirname "$0")/world-lib.sh"
D=$RUN/r7b; mkdir -p "$D"; t0=$(now)
jq -n '{type:"minidregg-workspace-proposal-v1",action:"invoke",targets:[{name:"src-shop",payload:{type:"content",actions:[]}}]}' >"$D/empty.req.json"
submit_req r7b-empty importer "$D/empty.req.json"
got=$(outcome r7b-empty); [ "$got" = client-error ] && got="refused by the client before signing"
row R7b empty-command "refused" "$got" "$(since "$t0")" "$(grep -m1 '^mini:' "$L/r7b-empty.err") $(refusal_text r7b-empty)"
