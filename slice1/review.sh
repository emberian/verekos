#!/usr/bin/env bash
# slice1/review.sh — the reviewer resolves the email-type conflict: its signed read of the conflict
# cell (hbox), the decision by `verekos-map review` (here), the submit and renders (s5-review.sh).
set -euo pipefail
. "$(dirname "$0")/mac-lib.sh"
CF=cf-customers-columns-email-data-type; L=$LOCALRUN/review
hread review "$L" reviewer "$CF"
"$MAP" review --conflict "$L/$CF.json" --conflict-cell "$CF" --cell review --pick shop \
  --note "the shop schema is the system of record for customers" --out "$L/review.req.json" >"$L/mapper.txt"
hput "$L/review.req.json" "$L/mapper.txt" review
ssh hbox "export RUNID=$RUNID; bash $RC/s5-review.sh"
