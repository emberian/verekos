#!/usr/bin/env bash
# slice1/replay.sh TAG STEP — the verifier replays compile TAG (Mac side: EKOS and verekos-map are
# Mac builds). Its own signed reads of the source cells, its own fresh EKOS workspace over the
# rendered files, `verekos-map compile` over its export with the compile's pre-state (TAG 1: every
# cell unborn), the compile-run record whose inputs are the ones replayed, and the attestation;
# hbox (s4-attest.sh) compares and submits.
set -euo pipefail
. "$(dirname "$0")/mac-lib.sh"
TAG=$1; STEP=$2; LOCAL=$LOCALRUN/replay-$TAG
mkdir -p "$LOCAL"
hread "replay-$TAG" "$LOCAL" verifier src-shop src-legacy
render_sources "$LOCAL"
bash "$HERE/ekos-compile.sh" "$LOCAL/ws" "$LOCAL/ekos"
cp "$LOCAL/ekos/export.ndjson" "$LOCAL/ekos/ekos-version.txt" "$LOCAL/"
map_compile "$LOCAL" "$LOCALRUN/cells.json"
replayed=$(cat "$LOCAL/req/commands.sha256")
hread "replay-$TAG" "$LOCAL" verifier compile-run
# the compile-run record whose recorded inputs (source atoms and revisions) are the ones replayed
claimed=$(python3 -I - "$LOCAL/compile-run.json" "$LOCAL/req/commands.json" <<'PY'
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
"$MAP" attest --compile-run "$LOCAL/compile-run.json" --claimed "$claimed" --replayed "$replayed" \
  --cell attestation --source-cell compile-run --out "$LOCAL/attest.req.json" >"$LOCAL/attest.txt" || true
ssh hbox "rm -rf \$HOME/$RRUN/replay-$TAG/req"
sent=("$LOCAL/export.ndjson" "$LOCAL/ekos-version.txt" "$LOCAL/req" "$LOCAL/mapper.txt" "$LOCAL/attest.txt")
[ -f "$LOCAL/attest.req.json" ] && sent+=("$LOCAL/attest.req.json")
hput "${sent[@]}" "replay-$TAG"
ssh hbox "RUN=\$HOME/$RRUN bash $RC/s4-attest.sh $TAG $STEP $claimed $replayed" 2>&1 | tail -8
