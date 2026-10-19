#!/bin/sh
# Fails unless every WorldCore module imports only WorldCore modules.
#
# The WorldCore modules are WorldCore.lean and exactly the modules it imports.
# Each of those files may import only modules in that same set (no Mathlib,
# no minidregg, no Batteries, nothing else). Run from anywhere:
#   world/check-core-imports.sh
set -eu
cd "$(dirname "$0")"

imports_of() {
  # the module names a file imports, one per line
  # (an import line is `import A.B.C` alone on its line; prose is skipped)
  sed -n 's/^import[[:space:]]\{1,\}\([A-Z][A-Za-z0-9_.]*\)[[:space:]]*$/\1/p' "$1"
}

core=$(printf 'WorldCore\n'; imports_of WorldCore.lean)
status=0
for m in $core; do
  f="$(printf '%s' "$m" | tr '.' '/').lean"
  if [ ! -f "$f" ]; then
    echo "check-core-imports: $m: no file $f" >&2
    status=1
    continue
  fi
  for i in $(imports_of "$f"); do
    if ! printf '%s\n' "$core" | grep -qxF "$i"; then
      echo "check-core-imports: $f imports $i, which is not a WorldCore module" >&2
      status=1
    fi
  done
done
if [ "$status" -eq 0 ]; then
  echo "check-core-imports: ok ($(printf '%s\n' "$core" | wc -l | tr -d ' ') modules, all imports inside WorldCore)"
fi
exit "$status"
