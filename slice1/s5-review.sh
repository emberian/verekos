#!/usr/bin/env bash
# slice1/s5-review.sh — hbox side of slice1/review.sh: the reviewer submits the decision the Mac's
# `verekos-map review` wrote ($RUN/review/review.req.json), a decision container whose snapshot
# transclusion pins the conflict's header atom (exploration 01 §2.1 ekos/review/v1); then renders.
. "$(dirname "$0")/world-lib.sh"
D=$RUN/review; mkdir -p "$D"
t0=$(now)
[ -f "$D/review.req.json" ] || { echo "no $D/review.req.json (run slice1/review.sh on the Mac)" >&2; exit 1; }
submit_req review-resolve reviewer "$D/review.req.json"
row S5 review-resolve installed "$(outcome review-resolve)" "$(since "$t0")" "$(cat "$D/mapper.txt") $( [ "$(outcome review-resolve)" = installed ] || refusal_text review-resolve)"
renders "$D/review-after-resolve" reviewer review
row S5 review-pin-renders snapshot "$(jq -r '[.transclusions[].render.view] | join(",")' "$D/review-after-resolve.host.json")" 0 \
  "$(jq -r '[.transclusions[].text] | join(" | ")' "$D/review-after-resolve.client.json" | head -c 300)"
