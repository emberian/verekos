#!/usr/bin/env python3
"""Drift checker for the hand-transcribed identity tests (03-scoreboard.md §5.4, option 1).

The transcription in identity.unit.jsonl is a copy of Rust test bodies, and a copy
can rot. This checker (a) collects every cited test function name from the panel's
`source` fields, (b) locates each function in the pinned EKOS checkout — from its
`#[test]` line to the closing brace at the same indentation — and (c) compares the
SHA-256 of that source text against drift.json. It does not prove the transcription
equals the test, only that the test has not changed since the transcription was made.

Run:  python3 -I drift.py            # check; populates drift.json on first run
      python3 -I drift.py --update   # re-record hashes after an intentional EKOS bump

Exits non-zero, naming the function, when a hash changed or a function disappeared.
Stdlib only; no EKOS code is imported or executed.
"""

import hashlib
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PANEL = HERE / "identity.unit.jsonl"
DRIFT = HERE / "drift.json"
EKOS_LIB = Path("/Users/ember/dev/EKOS/ekos/crates/identity/src/lib.rs")
SOURCE_LABEL = "ekos/crates/identity/src/lib.rs"


def cited_functions():
    """Test function names cited by the panel items, in first-appearance order."""
    seen = []
    for line in PANEL.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        item = json.loads(line)
        label = item["source"]
        if not label.startswith(SOURCE_LABEL + ":"):
            sys.exit(f"error: item {item['item']!r} cites unknown source {label!r}")
        fn = label[len(SOURCE_LABEL) + 1:]
        if fn not in seen:
            seen.append(fn)
    return seen


def function_text(lines, fn):
    """Source text of `fn` from its #[test] line to the closing brace at the same
    indentation, or None when the function does not exist in the file."""
    fn_line = None
    for i, line in enumerate(lines):
        if line.rstrip("\n") == f"    fn {fn}() {{":
            fn_line = i
            break
    if fn_line is None:
        return None
    start = fn_line
    while start > 0 and lines[start - 1].rstrip("\n") == "#[test]":
        start -= 1
    for j in range(fn_line + 1, len(lines)):
        if lines[j].rstrip("\n") == "    }":
            return "".join(lines[start:j + 1])
    return None


def ekos_commit():
    try:
        out = subprocess.run(
            ["git", "-C", str(EKOS_LIB.parents[3]), "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        )
        return out.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def record():
    functions = cited_functions()
    lines = EKOS_LIB.read_text(encoding="utf-8").splitlines(keepends=True)
    hashes = {}
    for fn in functions:
        text = function_text(lines, fn)
        if text is None:
            sys.exit(f"error: test function {fn!r} not found in {EKOS_LIB}")
        hashes[fn] = hashlib.sha256(text.encode("utf-8")).hexdigest()
    payload = {
        "ekos_commit": ekos_commit(),
        "source_file": SOURCE_LABEL,
        "functions": dict(sorted(hashes.items())),
    }
    DRIFT.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"populated {DRIFT.name}: {len(hashes)} functions "
          f"(ekos {payload['ekos_commit'][:12]})")


def check():
    stored = json.loads(DRIFT.read_text(encoding="utf-8"))
    known = stored["functions"]
    functions = cited_functions()
    lines = EKOS_LIB.read_text(encoding="utf-8").splitlines(keepends=True)

    failures = []
    for fn in functions:
        text = function_text(lines, fn)
        if text is None:
            failures.append(f"DISAPPEARED: {fn} (not found in {EKOS_LIB})")
            continue
        digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
        if fn not in known:
            failures.append(f"UNRECORDED: {fn} (add it with --update)")
        elif known[fn] != digest:
            failures.append(f"DRIFTED: {fn} (source hash changed since transcription)")

    stale = sorted(set(known) - set(functions))
    for fn in stale:
        print(f"note: stale drift entry for {fn} (no panel item cites it)")

    if failures:
        for f in failures:
            print(f, file=sys.stderr)
        sys.exit(f"error: {len(failures)} drifted/missing function(s)")
    commit = ekos_commit()
    note = "" if commit == stored["ekos_commit"] else \
        f" (warning: EKOS HEAD {commit[:12]} != pinned {stored['ekos_commit'][:12]})"
    print(f"drift check passed: {len(functions)} functions unchanged "
          f"(ekos {stored['ekos_commit'][:12]}){note}")


def main():
    if "--update" in sys.argv[1:]:
        record()
    elif DRIFT.exists():
        check()
    else:
        record()


if __name__ == "__main__":
    main()
