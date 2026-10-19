#!/usr/bin/env bash
# slice1/replay.sh TAG STEP — the verifier replays compile TAG (Mac side: EKOS is a Mac build).
# Its own signed reads of the source cells, its own fresh EKOS workspace over the rendered files,
# the mapper over its export with the compile's pre-state (TAG 1: every cell unborn), and the
# SHA-256 of the request bytes compared with the compile-run record's. Then the attestation.
set -euo pipefail
TAG=$1; STEP=$2
HERE=$(cd "$(dirname "$0")" && pwd); V=$HERE/..; LOCAL=$V/var/w17/${RUNID:-run-1}/replay-$TAG
RRUN=verekos-runs/slice1/${RUNID:-run-1}; RC=verekos-runs/slice1/code/slice1
mkdir -p "$LOCAL"
ssh hbox "set -e; RUN=\$HOME/$RRUN; . $RC/world-lib.sh; mkdir -p \$RUN/replay-$TAG; for c in src-shop src-legacy; do read_to \$RUN/replay-$TAG/\$c.json verifier \$c; done"
scp -q "hbox:$RRUN/replay-$TAG/src-shop.json" "hbox:$RRUN/replay-$TAG/src-legacy.json" "$LOCAL/"
rm -rf "$LOCAL/ws"; mkdir -p "$LOCAL/ws"
python3 -I "$HERE/mapper.py" render --key shop --read "$LOCAL/src-shop.json" --out "$LOCAL/ws/src/shop/ecommerce.sql"
python3 -I "$HERE/mapper.py" render --key legacy --read "$LOCAL/src-legacy.json" --out "$LOCAL/ws/src/legacy/legacy_customers.sql"
cp "$HERE/ekos.toml" "$LOCAL/ws/ekos.toml"
bash "$HERE/ekos-compile.sh" "$LOCAL/ws" "$LOCAL/ekos"
scp -q "$LOCAL/ekos/export.ndjson" "$LOCAL/ekos/ekos-version.txt" "hbox:$RRUN/replay-$TAG/"
ssh hbox "RUN=\$HOME/$RRUN bash $RC/s4-attest.sh $TAG $STEP" 2>&1 | tail -8
