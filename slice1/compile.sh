#!/usr/bin/env bash
# slice1/compile.sh TAG STEP [CURRENT] — runs on the Mac (EKOS's release binary and verekos-map are
# Mac builds): the compiler's signed reads of both source cells (on hbox) -> rendered files -> the
# unchanged EKOS pipeline -> export -> plan -> (owner creates any new cells, on hbox) -> the requests
# (verekos-map compile, here) -> submitted as compiler on hbox -> the compile-run append.
# CURRENT=1: the compiled cells' present documents are read first (recompile).
set -euo pipefail
. "$(dirname "$0")/mac-lib.sh"
TAG=$1; STEP=$2; CURRENT=${3:-0}; LOCAL=$LOCALRUN/compile-$TAG
mkdir -p "$LOCAL"
hread "compile-$TAG" "$LOCAL" compiler src-shop src-legacy
render_sources "$LOCAL"
t0=$(date +%s.%N)
bash "$HERE/ekos-compile.sh" "$LOCAL/ws" "$LOCAL/ekos"
echo "ekos pipeline $(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.3f", b-a}')s" >"$LOCAL/ekos-seconds.txt"
cp "$LOCAL/ekos/export.ndjson" "$LOCAL/ekos/ekos-version.txt" "$LOCAL/ekos/conflicts.json" "$LOCAL/"
"$MAP" plan --export "$LOCAL/export.ndjson" --source shop="$LOCAL/src-shop.json" --source legacy="$LOCAL/src-legacy.json" >"$LOCAL/plan.json"
hput "$LOCAL/export.ndjson" "$LOCAL/ekos-version.txt" "$LOCAL/conflicts.json" "$LOCAL/plan.json" "$LOCAL/ekos-seconds.txt" "compile-$TAG"
ssh hbox "export RUN=\$HOME/$RRUN; STEP=$STEP bash $RC/s-cells.sh \$RUN/compile-$TAG/plan.json" 2>&1 | tail -5
scp -q "hbox:$RRUN/cells.json" "$LOCALRUN/cells.json"
cur=()
if [ "$CURRENT" = 1 ]; then
  # shellcheck disable=SC2046
  hread "compile-$TAG/cur" "$LOCAL/cur" compiler $(jq -r '.[].cell' "$LOCAL/plan.json")
  cur=("$LOCAL/cur")
fi
t0=$(date +%s.%N)
map_compile "$LOCAL" "$LOCALRUN/cells.json" ${cur[@]+"${cur[@]}"}
msec=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.3f", b-a}')
ssh hbox "rm -rf \$HOME/$RRUN/compile-$TAG/req"
hput "$LOCAL/req" "$LOCAL/mapper.txt" "compile-$TAG"
ssh hbox "export RUN=\$HOME/$RRUN; MAPSEC=$msec bash $RC/s-compile.sh $TAG $STEP" 2>&1 | tail -20
before=()
if [ "$TAG" != 1 ]; then hread "compile-$TAG" "$LOCAL" compiler compile-run; before=("$LOCAL/compile-run.json"); fi
map_runrec "$LOCAL" ${before[@]+"${before[@]}"}
hput "$LOCAL/compile-run.req.json" "$LOCAL/runrec.txt" "compile-$TAG"
ssh hbox "export RUN=\$HOME/$RRUN; bash $RC/s-runrec.sh $TAG $STEP" 2>&1 | tail -5
