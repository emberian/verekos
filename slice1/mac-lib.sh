# slice1/mac-lib.sh — sourced by the Mac-side drivers (run.sh, compile.sh, replay.sh, import.sh,
# review.sh, laws.sh, dry.sh). Every mapping step runs HERE, with the Lean mapper `verekos-map`
# (map/, a Mac build); hbox only reads cells and submits the request files it is sent. Nothing
# needs a Lean toolchain on hbox.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); V=$HERE/..
MAP=${MAP:-$V/map/.lake/build/bin/verekos-map}
[ -x "$MAP" ] || { echo "no $MAP: build it first (cd map && nice -n 10 lake build)" >&2; exit 2; }
RUNID=${RUNID:-run-1}
LOCALRUN=$V/var/w17/$RUNID
RRUN=verekos-runs/slice1/$RUNID; RC=verekos-runs/slice1/code/slice1

# hread REMOTE_DIR LOCAL_DIR WHO CELL... : signed reads as WHO on hbox (REMOTE_DIR/CELL.json,
# relative to the run root), copied to LOCAL_DIR/CELL.json
hread() {
  local rd=$1 ld=$2 who=$3; shift 3
  mkdir -p "$ld"
  ssh hbox "set -e; RUN=\$HOME/$RRUN; . $RC/world-lib.sh; mkdir -p \$RUN/$rd; for c in $*; do read_to \$RUN/$rd/\$c.json $who \$c; done"
  for c in "$@"; do scp -q "hbox:$RRUN/$rd/$c.json" "$ld/$c.json"; done
}
# hput LOCAL... REMOTE_DIR : copy files into REMOTE_DIR (relative to the run root)
hput() { local n=$#; local rd=${!n}; ssh hbox "mkdir -p \$HOME/$RRUN/$rd"; scp -q -r "${@:1:$((n - 1))}" "hbox:$RRUN/$rd/"; }

# render_sources DIR : the two source documents (DIR/src-*.json) as the files EKOS compiles (DIR/ws)
render_sources() {
  local d=$1
  rm -rf "$d/ws"; mkdir -p "$d/ws"
  "$MAP" render --key shop --read "$d/src-shop.json" --out "$d/ws/src/shop/ecommerce.sql" >/dev/null
  "$MAP" render --key legacy --read "$d/src-legacy.json" --out "$d/ws/src/legacy/legacy_customers.sql" >/dev/null
  cp "$HERE/ekos.toml" "$d/ws/ekos.toml"
}
# map_compile DIR CELLS [CURRENT_DIR] : DIR/req (requests, commands.json, commands.sha256) and
# DIR/mapper.txt from DIR/export.ndjson and DIR/src-*.json; CURRENT_DIR/CELL.json for a recompile
map_compile() {
  local d=$1 cells=$2 curdir=${3:-} cur=()
  if [ -n "$curdir" ]; then
    for c in $(jq -r '.[].cell' "$d/plan.json"); do cur+=(--current "$c=$curdir/$c.json"); done
  fi
  rm -rf "$d/req"
  "$MAP" compile --export "$d/export.ndjson" --source shop="$d/src-shop.json" --source legacy="$d/src-legacy.json" \
    --cells "$cells" --ekos-version "$(cat "$d/ekos-version.txt")" --out "$d/req" ${cur[@]+"${cur[@]}"} >"$d/mapper.txt"
}
# map_runrec DIR [BEFORE] : DIR/compile-run.req.json and DIR/runrec.txt (BEFORE: the cell's current read)
map_runrec() {
  local d=$1 rd=()
  [ -n "${2:-}" ] && rd=(--read "$2")
  "$MAP" runrec --dir "$d/req" --source shop="$d/src-shop.json" --source legacy="$d/src-legacy.json" \
    --cell compile-run --ekos-version "$(cat "$d/ekos-version.txt")" --out "$d/compile-run.req.json" ${rd[@]+"${rd[@]}"} >"$d/runrec.txt"
}
