#!/usr/bin/env bash
# slice1/s3-refusals.sh — R1 (the customers birth's pin names the create-table:customers atom at
# its revision), then the three wrong writes, each signed by `compiler`, which holds observe+mutate
# on every cell it writes here (so a refusal is the law's or the kernel's, never a missing grant):
#   R2 obj-r2 birth with zero transclusions          -> refused by L-obj
#   R3 a decision appended to the review cell        -> refused by L-rev
#   R4 obj-r2 birth whose transclusion's source is not read in the same command -> sourceNotCovered
. "$(dirname "$0")/world-lib.sh"
C=$(dirname "$0"); D=$RUN/refusals; mkdir -p "$D"
TAG=${TAG:-1}
hexs() { printf '%s' "$1" | xxd -p | tr -d '\n'; }
idof() { python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import mapper; print(mapper.num(*sys.argv[2:]))' "$C" "$@"; }

# R1 -------------------------------------------------------------------------------------------
t0=$(now)
read_to "$D/obj-customers.json" verifier obj-customers
read_to "$D/src-shop.json" verifier src-shop
want_atom=$(idof atom shop ecommerce.sql 'create-table:customers#0')
want_rev=$(jq -r --arg a "$want_atom" '.cell.entries[] | select(.type=="atom" and .id==$a) | .revision' "$D/src-shop.json")
got=$(jq -r --arg a "$want_atom" --arg s "$(target_of src-shop)" '[.cell.entries[] | select(.type=="transclusion")
  | .opening as $o | select(($o.source|tostring)==$s) | $o.pins[] | select(.atom==$a) | .revision] | first // "none"' "$D/obj-customers.json")
outc=$(outcome "compile-$TAG-obj-customers")
row R1 customers-birth-pinned "installed; pin create-table:customers@$want_rev" "$outc; pin create-table:customers@$got" "$(since "$t0")" \
  "atom $want_atom; $(attempt_dir "compile-$TAG-obj-customers"); transclusion records: $(jq '[.cell.entries[] | select(.type=="transclusion")] | length' "$D/obj-customers.json")"

# R2 -------------------------------------------------------------------------------------------
t0=$(now)
root=$(idof element obj-r2 root); hdr=$(idof atom obj-r2 header)
jq -n --arg root "$root" --arg sch "$(idof schema ekos/object/v1)" --arg h "$hdr" --arg hs "$(idof schema ekos/header/v1)" \
  --arg p "$(hexs '{"kind":"Table","logical_key":"sql-analyzer-table:r2","name":"r2"}')" \
  '{type:"minidregg-workspace-proposal-v1",action:"invoke",targets:[{name:"obj-r2",payload:{type:"content",actions:[
    {type:"createDocument",rootElement:$root,schema:$sch},
    {type:"createAtom",atom:$h,kind:{type:"inlineObject",schema:$hs},payload:$p}]}}]}' >"$D/r2.req.json"
submit_req r2-birth-no-evidence compiler "$D/r2.req.json"
row R2 birth-without-transclusion refused "$(outcome r2-birth-no-evidence)" "$(since "$t0")" "$(refusal_text r2-birth-no-evidence)"

# R3 -------------------------------------------------------------------------------------------
t0=$(now)
jq -n --arg root "$(idof element review root)" --arg sch "$(idof schema ekos/review/v1)" --arg c "$(idof element review r3)" \
  --arg a "$(idof atom review r3)" --arg ds "$(idof schema ekos/decision/v1)" \
  --arg p "$(hexs '{"note":"compiler resolves its own conflict","pick":"shop","verb":"resolve"}')" \
  '{type:"minidregg-workspace-proposal-v1",action:"invoke",targets:[{name:"review",payload:{type:"content",actions:[
    {type:"createDocument",rootElement:$root,schema:$sch},
    {type:"createContainer",element:$c},
    {type:"createAtom",atom:$a,kind:{type:"inlineObject",schema:$ds},payload:$p}]}}]}' >"$D/r3.req.json"
submit_req r3-compiler-resolves compiler "$D/r3.req.json"
row R3 compiler-writes-review refused "$(outcome r3-compiler-resolves)" "$(since "$t0")" "$(refusal_text r3-compiler-resolves)"

# R4 -------------------------------------------------------------------------------------------
t0=$(now)
run_id=$(idof run shop ecommerce.sql statements)
jq -n --arg root "$root" --arg sch "$(idof schema ekos/object/v1)" --arg h "$hdr" --arg hs "$(idof schema ekos/header/v1)" \
  --arg p "$(hexs '{"kind":"Table","logical_key":"sql-analyzer-table:r4","name":"r4"}')" \
  --arg t "$(idof transclusion obj-r2 r4)" --arg l "$(idof link obj-r2 r4)" --arg src "$(target_of src-shop)" \
  --arg run "$run_id" --arg a "$want_atom" --arg rev "$want_rev" \
  '{type:"minidregg-workspace-proposal-v1",action:"invoke",targets:[{name:"obj-r2",payload:{type:"content",actions:[
    {type:"createDocument",rootElement:$root,schema:$sch},
    {type:"createAtom",atom:$h,kind:{type:"inlineObject",schema:$hs},payload:$p},
    {type:"transclude",transclusion:$t,link:$l,request:{source:$src,
      range:{start:{run:$run,neighbor:$a,bias:"before",death:"keepTombstone"},finish:{run:$run,neighbor:$a,bias:"after",death:"keepTombstone"}},
      mode:"snapshot",pins:[{atom:$a,revision:$rev}]}}]}}]}' >"$D/r4.req.json"
submit_req r4-no-read compiler "$D/r4.req.json"
row R4 transclude-unread-source refused "$(outcome r4-no-read)" "$(since "$t0")" "$(refusal_text r4-no-read)"
