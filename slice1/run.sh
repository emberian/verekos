#!/usr/bin/env bash
# slice1/run.sh RUNID — slice 1 end to end on a fresh Store (Mac orchestrator; world on hbox).
# Every mapping step (laws, ids, imports, compiles, the replay, the review) runs here with
# verekos-map (map/, built first); hbox only reads cells and submits the files it is sent.
set -uo pipefail
export RUNID=${1:?RUNID}
HERE=$(cd "$(dirname "$0")" && pwd); V=$HERE/..; LOCAL=$V/var/w17/$RUNID
RC=verekos-runs/slice1/code/slice1
mkdir -p "$LOCAL"; T=$LOCAL/steps.tsv; : >"$T"
h() { ssh hbox "export RUNID=$RUNID; $*"; }
step() { local id=$1; shift; local t0; t0=$(date +%s.%N); echo "== $id $(date +%T)"; "$@"; local rc=$?
  printf '%s\t%s\t%s\n' "$id" "$rc" "$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}')" >>"$T"; }
[ -x "$V/map/.lake/build/bin/verekos-map" ] || { echo "build map/ first (cd map && nice -n 10 lake build)" >&2; exit 2; }
rsync -a "$HERE" hbox:verekos-runs/slice1/code/
bash "$HERE/ids.sh" >"$LOCAL/ids.tsv" && scp -q "$LOCAL/ids.tsv" "hbox:$RC/ids.tsv"
h "df -h / | tail -1"
step S2-setup     h "bash $RC/s2-setup.sh"
step S2-laws      bash "$HERE/laws.sh"
step S2-cells     h "bash $RC/s2-cells.sh"
step S2-import    bash "$HERE/import.sh" 1 S2
step S2-compile   bash "$HERE/compile.sh" 1 S2 0
step S3-refusals  h "TAG=1 bash $RC/s3-refusals.sh"
step S4-replay    bash "$HERE/replay.sh" 1 S4
step S4-reimport  env EXPECT=nothing-submitted bash "$HERE/import.sh" 2 R7b
step S4-empty     h "bash $RC/s4-empty.sh"
step S5-review    bash "$HERE/review.sh"
step S5-edit      env LEGACY_FILE="$HERE/inputs/legacy_customers.v2.sql" bash "$HERE/import.sh" 3 S5
step S5-before    h "EXPECT_EVIDENCE=old-pin:moved EXPECT_HEADER='signature bfc2f80cdccacb27…' EXPECT_REVIEW=snapshot bash $RC/s5-r5.sh before"
step S5-recompile bash "$HERE/compile.sh" 2 S5 1
step S5-after     h "EXPECT_EVIDENCE='old-pin:moved current-pin:snapshot' EXPECT_HEADER=edited EXPECT_REVIEW=moved bash $RC/s5-r5.sh after"
step S6-reader    h "bash $RC/s6-reader.sh"
h "df -h / | tail -1 > \$HOME/verekos-runs/slice1/$RUNID/disk-after.txt; du -sh \$HOME/verekos-runs/slice1/$RUNID > \$HOME/verekos-runs/slice1/$RUNID/du.txt"
step stop         h "bash $RC/s-stop.sh"
scp -q "hbox:verekos-runs/slice1/$RUNID/receipts.tsv" "hbox:verekos-runs/slice1/$RUNID/principals.json" "hbox:verekos-runs/slice1/$RUNID/manifest.json" \
  "hbox:verekos-runs/slice1/$RUNID/cells.json" "hbox:verekos-runs/slice1/$RUNID/disk-before.txt" "hbox:verekos-runs/slice1/$RUNID/disk-after.txt" \
  "hbox:verekos-runs/slice1/$RUNID/du.txt" "$LOCAL/"
echo "done: $LOCAL/receipts.tsv"
