#!/usr/bin/env bash
# slice1/compile.sh TAG STEP [CURRENT] — runs on the Mac (EKOS's release binary is a Mac build):
# the compiler's signed reads of both source cells (on hbox) -> rendered files -> the unchanged
# EKOS pipeline -> export -> plan -> (owner creates any new cells) -> requests submitted as compiler.
set -euo pipefail
TAG=$1; STEP=$2; CURRENT=${3:-0}
HERE=$(cd "$(dirname "$0")" && pwd); V=$HERE/..; LOCAL=$V/var/w17/${RUNID:-run-1}/compile-$TAG
RRUN=verekos-runs/slice1/${RUNID:-run-1}; RC=verekos-runs/slice1/code/slice1
mkdir -p "$LOCAL"
ssh hbox "set -e; RUN=\$HOME/$RRUN; . $RC/world-lib.sh; mkdir -p \$RUN/compile-$TAG; for c in src-shop src-legacy; do read_to \$RUN/compile-$TAG/\$c.json compiler \$c; done"
scp -q "hbox:$RRUN/compile-$TAG/src-shop.json" "hbox:$RRUN/compile-$TAG/src-legacy.json" "$LOCAL/"
rm -rf "$LOCAL/ws"; mkdir -p "$LOCAL/ws"
python3 -I "$HERE/mapper.py" render --key shop --read "$LOCAL/src-shop.json" --out "$LOCAL/ws/src/shop/ecommerce.sql"
python3 -I "$HERE/mapper.py" render --key legacy --read "$LOCAL/src-legacy.json" --out "$LOCAL/ws/src/legacy/legacy_customers.sql"
cp "$HERE/ekos.toml" "$LOCAL/ws/ekos.toml"
t0=$(date +%s.%N)
bash "$HERE/ekos-compile.sh" "$LOCAL/ws" "$LOCAL/ekos"
echo "ekos pipeline $(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.3f", b-a}')s" >"$LOCAL/ekos-seconds.txt"
python3 -I "$HERE/mapper.py" plan --export "$LOCAL/ekos/export.ndjson" --source shop="$LOCAL/src-shop.json" --source legacy="$LOCAL/src-legacy.json" >"$LOCAL/plan.json"
scp -q "$LOCAL/ekos/export.ndjson" "$LOCAL/ekos/ekos-version.txt" "$LOCAL/ekos/conflicts.json" "$LOCAL/plan.json" "$LOCAL/ekos-seconds.txt" "hbox:$RRUN/compile-$TAG/"
ssh hbox "export RUN=\$HOME/$RRUN; STEP=$STEP bash $RC/s-cells.sh \$RUN/compile-$TAG/plan.json && CURRENT=$CURRENT bash $RC/s-compile.sh $TAG $STEP" 2>&1 | tail -20
