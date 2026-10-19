#!/usr/bin/env bash
# slice1/s5-r5.sh PHASE — the R5 observations. PHASE before: after the legacy re-import, before the
# recompile. PHASE after: after the recompile.
. "$(dirname "$0")/world-lib.sh"
C=$(dirname "$0"); P=$1; D=$RUN/r5-$P; mkdir -p "$D"
CF=cf-customers-columns-email-data-type
# ids computed on the Mac by `verekos-map id` (slice1/ids.sh), sent as ids.tsv
idof() { awk -F'\t' -v k="$*" '$1 == k { print $2; f = 1 } END { exit !f }' "$C/ids.tsv" || echo "idof: '$*' not in $C/ids.tsv" >&2; }
legacy_atom=$(idof atom legacy legacy_customers.sql 'create-table:customers#0')
t0=$(now)
read_to "$D/src-legacy.json" verifier src-legacy
read_to "$D/obj-customers.json" verifier obj-customers
read_to "$D/cf.json" verifier "$CF"
read_to "$D/cf-columns.json" verifier cf-customers-columns
renders "$D/customers" verifier obj-customers
renders "$D/review" reviewer review
rev_now=$(jq -r --arg a "$legacy_atom" '.cell.entries[] | select(.type=="atom" and .id==$a) | .revision' "$D/src-legacy.json")
# the customers cell's transclusions of the legacy statement: pin revision -> Host render
legacy_tr=$(jq -r --arg a "$legacy_atom" '.cell.entries[] | select(.type=="transclusion") | select(.opening.pins[0].atom==$a) | "\(.id):\(.opening.pins[0].revision)"' "$D/obj-customers.json")
views=""; for x in $legacy_tr; do id=${x%%:*}; rv=${x#*:}; v=$(view_of "$D/customers.host.json" "$id")
  views="$views $([ "$rv" = "$rev_now" ] && echo current || echo old)-pin:$v"; done
row R5 "$P-legacy-evidence" "${EXPECT_EVIDENCE:-?}" "$(echo $views)" "$(since "$t0")" "legacy atom $legacy_atom now at revision $rev_now; client: $(jq -r --arg a "$legacy_atom" '[.transclusions[] | select(.opening.pins[0].atom==$a) | "\(.render.view)@\(.at // "-")"] | join(",")' "$D/customers.client.json")"
hdr=$(idof atom "$CF" header); hdr2=$(idof atom cf-customers-columns header)
hstate() { jq -r --arg a "$2" '.cell.entries[] | select(.type=="atom" and .id==$a) | "\(.revision) \(.payload)"' "$1"; }
sig() { jq -r --arg a "$2" '.cell.entries[] | select(.type=="atom" and .id==$a) | .payload' "$1" | xxd -r -p | jq -r .signature; }
B=$RUN/r5-before
if [ "$P" = after ] && [ -f "$B/cf.json" ]; then
  [ "$(hstate "$B/cf.json" "$hdr")" = "$(hstate "$D/cf.json" "$hdr")" ] && h=unchanged || h=edited
  [ "$(hstate "$B/cf-columns.json" "$hdr2")" = "$(hstate "$D/cf-columns.json" "$hdr2")" ] && h2=unchanged || h2=edited
  row R5 "$P-conflict-header" "${EXPECT_HEADER:-?}" "$h" 0 "signature $(sig "$B/cf.json" "$hdr" | cut -c1-16)… -> $(sig "$D/cf.json" "$hdr" | cut -c1-16)…; control cf-customers-columns header $h2 (signature $(sig "$D/cf-columns.json" "$hdr2" | cut -c1-16)…)"
else
  row R5 "$P-conflict-header" "${EXPECT_HEADER:-?}" "signature $(sig "$D/cf.json" "$hdr" | cut -c1-16)…" 0 "revision $(hstate "$D/cf.json" "$hdr" | cut -c1-16)…"
fi
row R5 "$P-review-pin" "${EXPECT_REVIEW:-?}" "$(jq -r '[.transclusions[].render.view] | join(",")' "$D/review.host.json")" 0 \
  "client: $(jq -r '[.transclusions[] | "\(.render.view)@\(.at // "-")"] | join(",")' "$D/review.client.json"); $(jq -r '[.transclusions[].text] | join(" | ")' "$D/review.client.json" | head -c 300)"
