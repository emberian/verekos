#!/usr/bin/env bash
# slice1/s5-review.sh — the reviewer resolves the email-type conflict: a decision container whose
# snapshot transclusion pins the conflict's header atom (exploration 01 §2.1 ekos/review/v1).
. "$(dirname "$0")/world-lib.sh"
C=$(dirname "$0"); D=$RUN/review; mkdir -p "$D"
CF=cf-customers-columns-email-data-type
t0=$(now)
read_to "$D/cf.json" reviewer "$CF"
python3 -I "$C/mapper.py" review --conflict "$D/cf.json" --conflict-cell "$CF" --cell review --pick shop \
  --note "the shop schema is the system of record for customers" --out "$D/review.req.json" >"$D/mapper.txt" 2>&1 || { cat "$D/mapper.txt"; exit 1; }
submit_req review-resolve reviewer "$D/review.req.json"
row S5 review-resolve installed "$(outcome review-resolve)" "$(since "$t0")" "$(cat "$D/mapper.txt") $( [ "$(outcome review-resolve)" = installed ] || refusal_text review-resolve)"
renders "$D/review-after-resolve" reviewer review
row S5 review-pin-renders snapshot "$(jq -r '[.transclusions[].render.view] | join(",")' "$D/review-after-resolve.host.json")" 0 \
  "$(jq -r '[.transclusions[].text] | join(" | ")' "$D/review-after-resolve.client.json" | head -c 300)"
