#!/usr/bin/env bash
# reader/remote/read-cells.sh MINI WS OUT NAME...   (runs on the node's machine, fed over ssh stdin)
# One signed read per NAME as the principal whose workspace is WS (`mini workspace --action read`).
# NAME `@all` means every reference WS names (`mini workspace --action list`, which is local).
# A refused read is a row, not an error. Writes only under OUT:
#   NAME.json         the view, with the reference's target added (slice1/world-lib.sh read_to)
#   NAME.refused.txt  stderr of a refused read
#   reads.tsv         name <TAB> rc <TAB> seconds <TAB> bytes <TAB> first refusal line
# Nothing is submitted to the node.
set -uo pipefail
umask 077
MINI=$1; WS=$2; OUT=$3; shift 3
mkdir -p "$OUT"; : >"$OUT/reads.tsv"
if [ "${1:-}" = "@all" ]; then
  set -- $(nice -n 10 "$MINI" workspace --action list --dir "$WS" 2>/dev/null | jq -r '.references[].name')
fi
for n in "$@"; do
  t0=$(date +%s.%N)
  nice -n 10 "$MINI" workspace --action read --dir "$WS" --name "$n" >"$OUT/$n.raw" 2>"$OUT/$n.err"; rc=$?
  secs=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.2f", b-a}')
  if [ $rc = 0 ]; then
    jq --arg t "$(jq -r .target "$WS/refs/$n.json")" '. + {target:$t}' "$OUT/$n.raw" >"$OUT/$n.json"
    bytes=$(wc -c <"$OUT/$n.json"); why=""
  else
    grep -E 'refused|error|mini:' "$OUT/$n.err" | head -3 >"$OUT/$n.refused.txt"; bytes=0
    why=$(head -1 "$OUT/$n.refused.txt" | tr '\t' ' ')
  fi
  rm -f "$OUT/$n.raw" "$OUT/$n.err"
  printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$rc" "$secs" "$bytes" "$why" >>"$OUT/reads.tsv"
done
