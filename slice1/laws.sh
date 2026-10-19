#!/usr/bin/env bash
# slice1/laws.sh — between s2-setup.sh and s2-cells.sh: the four laws with run's real subject ids,
# rendered here by `verekos-map laws` from minidregg Pred values (placeholders 91001 importer,
# 91002 owner, 91003 compiler or verifier, 91004 reviewer), sent to hbox as $RUN/laws/ and laws.tsv.
set -euo pipefail
. "$(dirname "$0")/mac-lib.sh"
mkdir -p "$LOCALRUN"
scp -q "hbox:$RRUN/principals.json" "$LOCALRUN/principals.json"
who() { jq -r --arg k "$1" '.[$k]' "$LOCALRUN/principals.json"; }
rm -rf "$LOCALRUN/laws"
"$MAP" laws --out "$LOCALRUN/laws" --owner "$(who owner)" --importer "$(who importer)" --compiler "$(who compiler)" \
  --reviewer "$(who reviewer)" --verifier "$(who verifier)" >"$LOCALRUN/laws.tsv"
printf '%s\n' '{"type":"all","predicates":[]}' >"$LOCALRUN/laws/permit-all.json"
hput "$LOCALRUN/laws" "$LOCALRUN/laws.tsv" .
