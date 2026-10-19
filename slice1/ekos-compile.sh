#!/usr/bin/env bash
# slice1/ekos-compile.sh WS OUT_DIR — run the unchanged EKOS pipeline over a scratch
# workspace WS (ekos.toml with [[sources]] shop + legacy) and write OUT_DIR/export.ndjson
# and OUT_DIR/conflicts.json. EKOS itself is never edited; only its release binary runs.
set -euo pipefail
WS=$1; OUT=$2
EKOS=${EKOS:-/Users/ember/dev/EKOS/ekos/target/release/ekos}
# The property keys carried into the export (graph_export.rs: `p` holds only the named keys).
PROPS=(columns check_constraints indexes description source sources
       signature claims subject_id attribute status subject_kind conflict_type chosen subject_name)
args=(); for k in "${PROPS[@]}"; do args+=(--include-property "$k"); done
mkdir -p "$OUT"
cd "$WS"
[ -d .ekos ] || "$EKOS" init >"$OUT/init.log" 2>&1
for s in build recover resolve compile commit; do
  "$EKOS" "$s" >"$OUT/$s.log" 2>&1
done
"$EKOS" graph export --format ndjson "${args[@]}" >"$OUT/export.ndjson"
"$EKOS" conflicts list --json >"$OUT/conflicts.json"
"$EKOS" --version >"$OUT/ekos-version.txt"
