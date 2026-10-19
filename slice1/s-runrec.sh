#!/usr/bin/env bash
# slice1/s-runrec.sh TAG STEP — hbox side of the compile-run append: as `compiler`, submit the record
# the Mac's `verekos-map runrec` wrote ($RUN/compile-TAG/compile-run.req.json, runrec.txt).
. "$(dirname "$0")/world-lib.sh"
TAG=$1; STEP=$2; D=$RUN/compile-$TAG
[ -f "$D/compile-run.req.json" ] || { echo "no $D/compile-run.req.json (run slice1/compile.sh on the Mac)" >&2; exit 1; }
t0=$(now)
submit_req "compile-$TAG-run" compiler "$D/compile-run.req.json"
row "$STEP" "compile-$TAG-run" installed "$(outcome "compile-$TAG-run")" "$(since "$t0")" "$(cat "$D/runrec.txt") $( [ "$(outcome "compile-$TAG-run")" = installed ] || refusal_text "compile-$TAG-run")"
