#!/usr/bin/env bash
# slice1/s6-reader.sh — R6: reader-shop, who holds only a room delegation on `shop`, reads the
# customers cell (born in shop) and tries the conflict cell (born in no room).
. "$(dirname "$0")/world-lib.sh"
C=$(dirname "$0"); D=$RUN/r6; mkdir -p "$D"
CF=cf-customers-columns-email-data-type
idof() { python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import mapper; print(mapper.num(*sys.argv[2:]))' "$C" "$@"; }
t0=$(now)
run r6-show "$MINI" workspace --action doc-show --dir "$(ws_of reader-shop)" --name obj-customers --format json
cp "$L/r6-show.out" "$D/show.json"
props=$(jq -r --arg a "$(idof atom obj-customers properties)" '[.lines[] | select(.atom==$a) | .payload] | first // ""' "$D/show.json" | xxd -r -p | jq -c '.columns | map(.name)' 2>/dev/null)
row R6 reader-sees-properties "columns visible" "$( [ -n "$props" ] && echo "columns visible $props" || echo "not visible: $(tail -1 "$L/r6-show.err")")" "$(since "$t0")" "doc-show rc $(rc r6-show)"
t0=$(now)
renders "$D/customers" reader-shop obj-customers
legacy_atom=$(idof atom legacy legacy_customers.sql 'create-table:customers#0'); shop_atom=$(idof atom shop ecommerce.sql 'create-table:customers#0')
lv=$(jq -r --arg a "$legacy_atom" '[.transclusions[] | select(.opening.pins[0].atom==$a) | .render.view] | join(",")' "$D/customers.client.json")
sv=$(jq -r --arg a "$shop_atom" '[.transclusions[] | select(.opening.pins[0].atom==$a) | .render.view] | join(",")' "$D/customers.client.json")
# legacy bytes in anything reader-shop was given: plain text, or hex as views carry payloads
pat="CITEXT\|email  TEXT\|$(printf 'CITEXT' | xxd -p)\|$(printf 'email  TEXT' | xxd -p)"
leak=$(cat "$D/customers.client.json" "$D/customers.host.json" "$D/show.json" | grep -c "$pat")
row R6 reader-legacy-transclusion "legacy unavailable; shop snapshot; 0 legacy bytes" "legacy $lv; shop $sv; $leak legacy bytes" "$(since "$t0")" \
  "$(jq -r --arg a "$legacy_atom" '[.transclusions[] | select(.opening.pins[0].atom==$a) | .text] | join(" | ")' "$D/customers.client.json")"
t0=$(now)
import_via reader-shop "$CF" "$(target_of "$CF")" "$(jq -r .observeCapability "$(ws_of reader-shop)/refs/shop.json")"
run r6-conflict "$MINI" workspace --action read --dir "$(ws_of reader-shop)" --name "$CF"
row R6 reader-conflict-unreadable refused "$(outcome r6-conflict)" "$(since "$t0")" "$(grep -m1 -E 'refused' "$L/r6-conflict.err" | cut -c1-300)"
