#!/usr/bin/env bash
# slice1/ids.sh — the identifiers the hbox step scripts look up (`idof` in s3-refusals.sh,
# s5-r5.sh, s6-reader.sh), computed on the Mac by `verekos-map id` and written as
# "<parts joined by spaces>\t<id>" lines. run.sh sends the file to hbox as code/slice1/ids.tsv.
. "$(dirname "$0")/mac-lib.sh"
while read -r parts; do
  [ -n "$parts" ] || continue
  # shellcheck disable=SC2086
  printf '%s\t%s\n' "$parts" "$("$MAP" id $parts)"
done <<'IDS'
atom shop ecommerce.sql create-table:customers#0
atom legacy legacy_customers.sql create-table:customers#0
run shop ecommerce.sql statements
element obj-r2 root
atom obj-r2 header
transclusion obj-r2 r4
link obj-r2 r4
element review root
element review r3
atom review r3
schema ekos/object/v1
schema ekos/header/v1
schema ekos/review/v1
schema ekos/decision/v1
atom obj-customers properties
atom cf-customers-columns-email-data-type header
atom cf-customers-columns header
IDS
