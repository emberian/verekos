# slice1/world-lib.sh — sourced by the slice-1 step scripts on hbox. Raw `mini workspace`
# command lines as journey.d/j12t-kernel.sh and j10-kernel.sh use them (read-only reference:
# ~/kn-gate/src/native/resource-client/journey.d/). Nothing here writes outside $RUN.
set -uo pipefail
umask 077
TIP=/home/hbox/kn-gate/fix/tipbin
RCDIR=/home/hbox/kn-gate/src/native/resource-client
MINI=$TIP/mini; HOST=$TIP/minidregg-host; STORE=$TIP/minidregg-link-sqlite-store
VERIFIER=$TIP/minidregg-credential-signature-verifier
BASE=/home/hbox/verekos-runs/slice1
RUN=${RUN:-$BASE/${RUNID:-run-1}}
W=$RUN/world
SOCKET=$RUN/w.sock
CONFIG=$W/deployment/pinned-config.json
SPONSOR_WS=$W/sponsor
L=$RUN/log; R=$RUN/req; RX=$RUN/receipts
REFUSAL_TAG=44524547472f4e41544956452d484f53542f4f5554434f4d45

now() { date +%s.%N; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN{printf "%.3f", b-a}'; }
ws_of() { case $1 in sponsor) echo "$SPONSOR_WS";; *) echo "$W/$1-workspace";; esac; }

# run NAME cmd... : stdout/stderr/rc under $L
run() { local n=$1; shift; nice -n 10 "$@" >"$L/$n.out" 2>"$L/$n.err"; echo $? >"$L/$n.rc"; }
rc() { cat "$L/$1.rc"; }
ok() { [ "$(rc "$1")" = 0 ] || { echo "setup $1 failed: $(tail -3 "$L/$1.err")" >&2; exit 1; }; }
attempt_dir() { grep -o 'workspace attempt: .*' "$L/$1.err" | tail -1 | cut -d' ' -f3; }
refusal_text() { # NAME -> the Host's own refusal words
  local dir; dir=$(attempt_dir "$1")
  if [ -n "$dir" ] && [ -f "$dir/outcome.json" ] && [ "$(jq -r .type "$dir/outcome.json")" != installed ]; then
    printf 'outcome %s phase %s: %s ' "$(jq -r .type "$dir/outcome.json")" \
      "$(jq -r '.phase // ""' "$dir/outcome.json" | xxd -r -p 2>/dev/null)" "$(jq -r '.detail // ""' "$dir/outcome.json" | xxd -r -p 2>/dev/null)"
  fi
  grep -o 'encoded refusal: [0-9a-f]*' "$L/$1.err" | tail -1 | cut -d' ' -f3 | xxd -r -p 2>/dev/null | tr -c '[:print:]' ' ' | tr -s ' '
  echo; grep -m1 -E 'refused|error' "$L/$1.err" | cut -c1-400
}
outcome() { if [ "$(rc "$1")" = 0 ]; then echo installed
  elif grep -q "refused" "$L/$1.err"; then echo refused; else echo client-error; fi; }

enroll() { # NAME -> prints subject; workspace at $W/NAME-workspace
  local A=$W/attempts/$1
  run "$1-keygen" "$MINI" keygen --secret "$W/$1.key" --public "$W/$1.pub"; ok "$1-keygen"
  run "$1-plan" "$MINI" enroll --action plan --sponsor-workspace "$SPONSOR_WS" --factory-ref factory \
    --name "$1-1" --new-key "$W/$1.key" --dir "$A"; ok "$1-plan"
  run "$1-seal" "$MINI" enroll --action seal --dir "$A"; ok "$1-seal"
  run "$1-enroll" "$MINI" enroll --action submit --dir "$A"; ok "$1-enroll"
  run "$1-init" "$MINI" workspace --action init --host "$HOST" --config "$CONFIG" --socket "$SOCKET" \
    --enrollment "$A/enrollment.json" --dir "$W/$1-workspace"; ok "$1-init"
  jq -r .subject "$L/$1-enroll.out"
}
# create NAME LAWFILE STORAGE [ROOM]: the sponsor (owner) creates a cell under LAWFILE
create() {
  local in=(); [ -n "${4:-}" ] && in=(--in "$4")
  run "create-$1" "$MINI" workspace --action create --dir "$SPONSOR_WS" --name "$1" --storage "$3" \
    --predicate "$2" "${in[@]}"; ok "create-$1"
}
# delegate ID RESOURCE RECIPIENT-WHO VERBS-JSON LOCALNAME [room]
delegate() {
  local id=$1 res=$2 who=$3 verbs=$4 local=$5 room=${6:-} subj
  subj=$(jq -r .subject "$(ws_of "$who")/workspace.json")
  jq -n --arg n "$res" --arg r "$subj" --argjson v "$verbs" --arg room "$room" \
    '{type:"minidregg-workspace-proposal-v1",action:"delegate",name:$n,recipient:$r,verbs:$v,maxCost:"50000"}
     + (if $room == "room" then {room:true} else {} end)' >"$R/$id.json"
  run "$id-propose" "$MINI" workspace --action propose --dir "$SPONSOR_WS" --request "$R/$id.json" --proposal-id "$id"; ok "$id-propose"
  run "$id-submit" "$MINI" workspace --action submit --dir "$SPONSOR_WS" \
    --intent "$SPONSOR_WS/proposals/$id/intent.json" --attempt "$SPONSOR_WS/attempts/$id"; ok "$id-submit"
  run "$id-publish" "$MINI" workspace --action publish-delegation --dir "$SPONSOR_WS" --proposal-id "$id" \
    --attempt "$SPONSOR_WS/attempts/$id"; ok "$id-publish"
  run "$id-import" "$MINI" workspace --action import --dir "$(ws_of "$who")" --name "$local" \
    --from-ref "$SPONSOR_WS/proposals/$id/recipient-reference.json"; ok "$id-import"
}
# import_via WHO LOCALNAME TARGET CAP-FROM-REF: name a cell reached through a room capability
import_via() {
  run "imp-$1-$2" "$MINI" workspace --action import --dir "$(ws_of "$1")" --name "$2" --kind object \
    --target "$3" --observe-capability "$4"; ok "imp-$1-$2"
}
read_cell() { run "$1" "$MINI" workspace --action read --dir "$(ws_of "$2")" --name "$3"; }
# submit_req NAME WHO REQFILE: propose + submit one invoke request as WHO
submit_req() {
  local n=$1 ws; ws=$(ws_of "$2")
  run "$n-propose" "$MINI" workspace --action propose --dir "$ws" --request "$3" --proposal-id "$n"
  if [ "$(rc "$n-propose")" != 0 ]; then cp "$L/$n-propose.rc" "$L/$n.rc"; cp "$L/$n-propose.err" "$L/$n.err"; : >"$L/$n.out"; return; fi
  run "$n" "$MINI" workspace --action submit --dir "$ws" --intent "$ws/proposals/$n/intent.json" --attempt "$ws/attempts/$n"
}
target_of() { jq -r .target "$SPONSOR_WS/refs/$1.json"; }
row() { # STEP NAME EXPECT GOT SECONDS DETAIL
  printf '%s\t%s\texpect=%s\tgot=%s\t%ss\t%s\n' "$1" "$2" "$3" "$4" "$5" "$(printf '%s' "$6" | tr '\n\t' '  ' | cut -c1-600)" >>"$RUN/receipts.tsv"
  printf '%s %s expect=%s got=%s (%ss)\n' "$1" "$2" "$3" "$4" "$5" >&2
}
# read_to OUT WHO REF: a signed read as WHO, saved with the reference's target added
read_to() {
  local n; n=read-$2-$3-$(date +%s%N)
  run "$n" "$MINI" workspace --action read --dir "$(ws_of "$2")" --name "$3"; ok "$n"
  jq --arg t "$(jq -r .target "$(ws_of "$2")/refs/$3.json")" '. + {target:$t}' "$L/$n.out" >"$1"
}
# renders OUT WHO CELL: `workspace --action transclusions` as WHO (the client's final view, after
# its `at` re-read of each snapshot) -> OUT.client.json, and the Host's own current render, the
# first `view-document` the client asked for in that call -> OUT.host.json
renders() {
  local out=$1 who=$2 cell=$3 ws mark n
  ws=$(ws_of "$who"); mark=$(mktemp -p "$RUN" mark.XXXXXX); n=tr-$who-$cell-$(date +%s%N)
  sleep 0.01; run "$n" "$MINI" workspace --action transclusions --dir "$ws" --name "$cell"
  cp "$L/$n.out" "$out.client.json"; cp "$L/$n.err" "$out.client.err"
  python3 -I - "$ws/attempts" "$mark" "$out.host.json" <<'PY'
import json, os, sys, pathlib
base, mark, out = pathlib.Path(sys.argv[1]), os.path.getmtime(sys.argv[2]), sys.argv[3]
cands = sorted((p.stat().st_mtime_ns, p) for p in base.glob("*/transclusions.json") if p.stat().st_mtime > mark)
for _, p in cands:
    inp = json.loads((p.parent / "transclusions-in.json").read_text())
    if inp.get("sources") and not any("at" in s for s in inp["sources"]):
        pathlib.Path(out).write_text(p.read_text()); break
else:
    pathlib.Path(out).write_text(json.dumps({"transclusions": [], "note": "no current render with readable sources"}))
PY
  rm -f "$mark"
}
# view_of FILE ID -> "<host view>" of one transclusion in a renders file
view_of() { jq -r --arg id "$2" '[.transclusions[] | select(.id == $id) | .render.view] | first // "absent"' "$1"; }
