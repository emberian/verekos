#!/usr/bin/env bash
# slice1/s4-attest.sh TAG STEP — hbox side of the replay: the verifier's mapper run, the compare
# against the compile-run record (read by the verifier), and the attestation append (L-run).
. "$(dirname "$0")/world-lib.sh"
TAG=$1; STEP=$2; C=$(dirname "$0"); D=$RUN/replay-$TAG
t0=$(now)
cmp -s "$D/export.ndjson" "$RUN/compile-$TAG/export.ndjson" && same_export=identical || same_export=differs
# the export header carries generated_at and the workspace path; the records after it are compared
cmp -s <(tail -n +2 "$D/export.ndjson") <(tail -n +2 "$RUN/compile-$TAG/export.ndjson") && same_body=identical || same_body=differs
python3 -I "$C/mapper.py" compile --export "$D/export.ndjson" --source shop="$D/src-shop.json" --source legacy="$D/src-legacy.json" \
  --cells "$RUN/cells.json" --ekos-version "$(cat "$D/ekos-version.txt")" --out "$D/req" >"$D/mapper.txt" 2>&1 || { cat "$D/mapper.txt"; exit 1; }
replayed=$(cat "$D/req/commands.sha256")
read_to "$D/compile-run.json" verifier compile-run
# the compile-run record whose recorded inputs (source atoms and revisions) are the ones replayed
claimed=$(python3 -I - "$D/compile-run.json" "$D/req/commands.json" <<'PY'
import json, sys
view, mine = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))["inputs"]
for e in view["cell"]["entries"]:
    if e.get("type") == "atom":
        try:
            rec = json.loads(bytes.fromhex(e["payload"]))
        except Exception:
            continue
        if isinstance(rec, dict) and rec.get("inputs") == mine:
            print(rec["commands_sha256"]); break
else:
    print("no-record-with-these-inputs")
PY
)
row "$STEP" "R7a-replay-$TAG" "$claimed" "$replayed" "$(since "$t0")" "export body $same_body (whole file $same_export); requests $(jq '.requests|length' "$D/req/commands.json"); request files byte-identical: $(diff -rq "$D/req" "$RUN/compile-$TAG/req" >/dev/null && echo yes || echo no)"
t0=$(now)
python3 -I "$C/mapper.py" attest --compile-run "$D/compile-run.json" --claimed "$claimed" --replayed "$replayed" \
  --cell attestation --source-cell compile-run --out "$D/attest.req.json" >"$D/attest.txt" 2>&1 || { cat "$D/attest.txt"; exit 1; }
submit_req "attest-$TAG" verifier "$D/attest.req.json"
row "$STEP" "attestation-$TAG" installed "$(outcome "attest-$TAG")" "$(since "$t0")" "$(cat "$D/attest.txt") $( [ "$(outcome "attest-$TAG")" = installed ] || refusal_text "attest-$TAG")"
