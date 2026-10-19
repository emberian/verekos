#!/usr/bin/env bash
# slice1/dry.sh [SRC_RUN] [OUT] — the Mac half of run.sh's compiles and replay with no hbox: from a
# finished run's saved signed reads (default var/w17/run-2), render the sources, run the unchanged
# EKOS pipeline afresh, plan and compile with verekos-map (the same mac-lib.sh functions compile.sh
# and replay.sh call), and compare each commands.sha256 with the one the run recorded.
set -euo pipefail
. "$(dirname "$0")/mac-lib.sh"
SRC=${1:-$V/var/w17/run-2}; OUT=${2:-$V/var/w24/dry}
rm -rf "$OUT"; mkdir -p "$OUT"
fail=0
for t in compile-1 compile-2 replay-1; do
  d=$OUT/$t; mkdir -p "$d"
  cp "$SRC/$t/src-shop.json" "$SRC/$t/src-legacy.json" "$d/"
  render_sources "$d"
  for f in shop/ecommerce.sql legacy/legacy_customers.sql; do
    cmp -s "$d/ws/src/$f" "$SRC/$t/ws/src/$f" || { echo "DIFFERS $t rendered $f"; fail=1; }
  done
  bash "$HERE/ekos-compile.sh" "$d/ws" "$d/ekos"
  cp "$d/ekos/export.ndjson" "$d/ekos/ekos-version.txt" "$d/"
  "$MAP" plan --export "$d/export.ndjson" --source shop="$d/src-shop.json" --source legacy="$d/src-legacy.json" >"$d/plan.json"
  cur=()
  if [ "$t" = compile-2 ]; then
    mkdir -p "$d/cur"
    for c in $(jq -r '.[].cell' "$d/plan.json"); do cp "$SRC/$t/cur-$c.json" "$d/cur/$c.json"; done
    cur=("$d/cur")
  fi
  map_compile "$d" "$SRC/cells.json" ${cur[@]+"${cur[@]}"}
  want=$(cat "$SRC/$t/req/commands.sha256"); got=$(cat "$d/req/commands.sha256")
  [ "$want" = "$got" ] && echo "same    $t commands.sha256 $got" || { echo "DIFFERS $t commands.sha256 $got (recorded $want)"; fail=1; }
  cmp -s "$d/plan.json" "$SRC/$t/plan.json" 2>/dev/null && echo "same    $t plan.json" || { [ -f "$SRC/$t/plan.json" ] && { echo "DIFFERS $t plan.json"; fail=1; }; }
  if [ "$t" != replay-1 ]; then
    before=(); [ "$t" = compile-2 ] && before=("$SRC/$t/compile-run-before.json")
    map_runrec "$d" ${before[@]+"${before[@]}"}
    echo "        $t runrec: $(cat "$d/runrec.txt")"
  fi
done
exit $fail
