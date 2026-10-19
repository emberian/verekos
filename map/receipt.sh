#!/usr/bin/env bash
# map/receipt.sh — run verekos-map on slice 1's run-2 inputs (var/w17/run-2, local and
# git-ignored) and compare every file it writes with the file the deleted twins (slice1/mapper.py,
# slice1/laws.py) wrote then: the committed request files under var/w17/run-2, laws/L-*.json, and
# map/fixtures/ (the twin's split, id, structural-key and table-cell outputs, recorded before it went).
# Prints one row per file: same | DIFFERS, and the SHA-256 of the Lean output.
# Usage: bash map/receipt.sh [OUT]   (OUT defaults to var/w24/receipt; never builds)
set -uo pipefail
V=$(cd "$(dirname "$0")/.." && pwd)
M=$V/map/.lake/build/bin/verekos-map
R=$V/var/w17/run-2
O=${1:-$V/var/w24/receipt}
rm -rf "$O"; mkdir -p "$O"
fail=0
sha() { shasum -a 256 "$1" | cut -c1-64; }
cmpf() {  # cmpf LABEL TWIN LEAN
  if cmp -s "$2" "$3"; then printf 'same\t%s\t%s\n' "$1" "$(sha "$3")"
  else printf 'DIFFERS\t%s\t%s\n' "$1" "$(sha "$3")"; fail=1; fi
}
cmptext() {  # cmptext LABEL EXPECTED-TEXT ACTUAL-TEXT
  if [ "$2" = "$3" ]; then printf 'same\t%s\t%s\n' "$1" "$3"
  else printf 'DIFFERS\t%s\t%s | %s\n' "$1" "$2" "$3"; fail=1; fi
}
S="--source shop=@/src-shop.json --source legacy=@/src-legacy.json"
src() { echo "${S//@/$1}"; }

# compile 1 and 2, the replay's compile: every request file, commands.json, commands.sha256
for t in compile-1 compile-2 replay-1; do
  D=$R/$t; cur=()
  if [ "$t" = compile-2 ]; then
    for c in $(python3 -I -c "import json,sys;print(' '.join(r['cell'] for r in json.load(open(sys.argv[1]))))" "$D/plan.json"); do
      cur+=(--current "$c=$D/cur-$c.json"); done
  fi
  # shellcheck disable=SC2046
  out=$("$M" compile --export "$D/export.ndjson" $(src "$D") --cells "$R/cells.json" \
    --ekos-version "$(cat "$D/ekos-version.txt")" --out "$O/$t/req" "${cur[@]}")
  cmptext "$t stdout" "$(cat "$D/mapper.txt")" "$out"
  for f in "$D"/req/*; do cmpf "$t/req/$(basename "$f")" "$f" "$O/$t/req/$(basename "$f")"; done
  extra=$(comm -13 <(ls "$D/req") <(ls "$O/$t/req")); [ -z "$extra" ] || { echo "DIFFERS	$t extra files: $extra"; fail=1; }
  printf 'concat\t%s\t%s\n' "$t" "$(cat $(python3 -I -c "import json,sys;print(' '.join(sys.argv[2]+'/'+r['file'] for r in json.load(open(sys.argv[1]))['requests']))" "$O/$t/req/commands.json" "$O/$t/req") | shasum -a 256 | cut -c1-64)"
done

# plan and render (compile-1 and compile-2)
for t in compile-1 compile-2; do
  D=$R/$t
  # shellcheck disable=SC2046
  "$M" plan --export "$D/ekos/export.ndjson" $(src "$D") >"$O/$t-plan.json"; cmpf "$t/plan.json" "$D/plan.json" "$O/$t-plan.json"
  "$M" render --key shop --read "$D/src-shop.json" --out "$O/$t-ws/src/shop/ecommerce.sql" >/dev/null
  "$M" render --key legacy --read "$D/src-legacy.json" --out "$O/$t-ws/src/legacy/legacy_customers.sql" >/dev/null
  cmpf "$t/ws/src/shop/ecommerce.sql" "$D/ws/src/shop/ecommerce.sql" "$O/$t-ws/src/shop/ecommerce.sql"
  cmpf "$t/ws/src/legacy/legacy_customers.sql" "$D/ws/src/legacy/legacy_customers.sql" "$O/$t-ws/src/legacy/legacy_customers.sql"
done

# the compile-run appends. mapper_sha256 records the mapper that ran: on run-2 that was slice1/mapper.py
# at fc8c7e1 (SHA-256 c9264a14...), given here as a value
MAPPER_AS_RUN=c9264a14fdfb855b3819729248effdded5bff752a5a09b709b185c29ab67eae3
for t in compile-1 compile-2; do
  D=$R/$t; rd=(); [ "$t" = compile-2 ] && rd=(--read "$D/compile-run-before.json")
  # shellcheck disable=SC2046
  out=$("$M" runrec --dir "$D/req" $(src "$D") --cell compile-run --ekos-version "$(cat "$D/ekos-version.txt")" \
    --mapper-sha256 "$MAPPER_AS_RUN" --out "$O/$t-compile-run.req.json" "${rd[@]}")
  cmptext "$t runrec stdout" "$(cat "$D/runrec.txt")" "$out"
  cmpf "$t/compile-run.req.json" "$D/compile-run.req.json" "$O/$t-compile-run.req.json"
done

# imports: 1 (births), 2 (nothing to submit), 3 (the CITEXT edit to legacy)
for n in 1 2 3; do
  D=$R/import-$n
  for spec in shop:src-shop:ecommerce.sql:$V/slice1/inputs/ecommerce.sql legacy:src-legacy:legacy_customers.sql:$V/slice1/fixtures/legacy_customers.sql; do
    IFS=: read -r key cell path file <<<"$spec"
    [ "$n" = 3 ] && [ "$key" = legacy ] && file=$V/slice1/inputs/legacy_customers.v2.sql
    out=$("$M" import --source-key "$key" --path "$path" --file "$file" --cell "$cell" --read "$D/$cell-before.json" --out "$O/import-$n-$cell.req.json")
    cmptext "import-$n $cell stdout" "$(cat "$D/$cell.mapper.txt")" "$out"
    if [ -f "$D/$cell.req.json" ]; then cmpf "import-$n/$cell.req.json" "$D/$cell.req.json" "$O/import-$n-$cell.req.json"
    elif [ -f "$O/import-$n-$cell.req.json" ]; then echo "DIFFERS	import-$n/$cell: Lean wrote a request, the twin wrote none"; fail=1
    else printf 'same\timport-%s/%s: no request (nothing to submit)\n' "$n" "$cell"; fi
  done
done

# the attestation and the review
D=$R/replay-1
out=$("$M" attest --compile-run "$D/compile-run.json" --claimed bcd84c6407873338f39a80edc4eacadd836dca7ec48f8c1f40909b8d43778443 \
  --replayed "$(cat "$O/replay-1/req/commands.sha256")" --cell attestation --source-cell compile-run --out "$O/attest.req.json")
cmptext "attest stdout" "$(cat "$D/attest.txt")" "$out"
cmpf "replay-1/attest.req.json" "$D/attest.req.json" "$O/attest.req.json"
D=$R/review
out=$("$M" review --conflict "$D/cf.json" --conflict-cell cf-customers-columns-email-data-type --cell review --pick shop \
  --note "the shop schema is the system of record for customers" --out "$O/review.req.json")
cmptext "review stdout" "$(cat "$D/mapper.txt")" "$out"
cmpf "review/review.req.json" "$D/review.req.json" "$O/review.req.json"

# laws: the deployed files (laws.py, real subjects) and the repository files (placeholders)
P=$(cat "$R/principals.json")
pr() { python3 -I -c "import json,sys;print(json.loads(sys.argv[1])[sys.argv[2]])" "$P" "$1"; }
"$M" laws --out "$O/laws-deployed" --owner 7 --importer "$(pr importer)" --compiler "$(pr compiler)" \
  --reviewer "$(pr reviewer)" --verifier "$(pr verifier)" >"$O/laws-deployed.txt"
for f in "$O"/laws-deployed/*.json; do cmpf "run-2/laws/$(basename "$f")" "$R/laws/$(basename "$f")" "$f"; done
"$M" laws --out "$O/laws" >/dev/null
for f in "$O"/laws/*.json; do cmpf "laws/$(basename "$f")" "$V/laws/$(basename "$f")" "$f"; done
# split, id, structural-key, table-cell: against the twin's outputs recorded in map/fixtures/
F=$V/map/fixtures
for f in slice1/inputs/ecommerce.sql slice1/fixtures/legacy_customers.sql slice1/inputs/legacy_customers.v2.sql; do
  "$M" split "$V/$f" >"$O/split-$(basename "$f").txt"
  cmpf "split $f" "$F/split-$(basename "$f").txt" "$O/split-$(basename "$f").txt"
done
while IFS=$'\t' read -r parts want; do
  # shellcheck disable=SC2086
  cmptext "id $parts" "$want" "$("$M" id $parts)"
done <"$F/ids.tsv"
while IFS=$'\t' read -r text want; do cmptext "structural-key $text" "$want" "$("$M" structural-key "$text")"; done <"$F/structural-keys.tsv"
while IFS=$'\t' read -r name want; do cmptext "table-cell $name" "$want" "$("$M" table-cell "$name")"; done <"$F/table-cells.tsv"
exit $fail
