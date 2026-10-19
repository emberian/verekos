#!/usr/bin/env python3
"""Drift checker for the branch panel (exploration 03 §5.4).

Hashes the source of each transcribed merge_branch_* test, from its #[test]
line through the closing brace at the same indentation, into drift.json beside
this file. A later run exits non-zero and names the function when that hash
changes or the function can no longer be found.

python3 -I drift.py --ekos /Users/ember/dev/EKOS --populate
python3 -I drift.py --ekos /Users/ember/dev/EKOS

The hash does not prove the panel equals the test. It only says the test a
human transcribed has not moved. These bodies never put a brace alone at the
function's indentation, so the first such line is the close.
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

REL = "ekos/crates/ledger/src/lib.rs"
FUNCTIONS = (
    "merge_branch_adds_new_objects_from_branch",
    "merge_branch_flags_diverged_objects_as_conflicts",
    "merge_branch_is_noop_for_identical_objects",
)
RECORD = Path(__file__).with_name("drift.json")


def extract(text: str, fn: str) -> str | None:
    """Source from the #[test] line through the closing brace, or None."""
    lines = text.splitlines(keepends=True)
    fn_re = re.compile(rf"^(\s*)fn {re.escape(fn)}\(")
    for i, line in enumerate(lines):
        body = line.rstrip("\r\n")
        m = fn_re.match(body)
        if not m:
            continue
        indent = m.group(1)
        start = None
        j = i - 1
        while j >= 0:
            prev = lines[j].rstrip("\r\n")
            if not prev.startswith(indent):
                break
            rest = prev[len(indent):]
            if not rest.startswith("#["):
                break
            if rest.startswith("#[test]"):
                start = j
                break
            j -= 1
        if start is None:
            return None
        end = None
        for k in range(i + 1, len(lines)):
            if lines[k].rstrip("\r\n") == indent + "}":
                end = k
                break
        if end is None:
            return None
        return "".join(lines[start:end + 1])
    return None


def ekos_commit(ekos: Path) -> str | None:
    try:
        out = subprocess.run(
            ["git", "-C", str(ekos), "rev-parse", "HEAD"],
            capture_output=True, text=True, timeout=30, check=True,
        )
        return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None


def hashes(ekos: Path) -> tuple[dict[str, str], list[str]]:
    path = ekos / REL
    if not path.is_file():
        return {}, [f"{name}: disappeared" for name in FUNCTIONS]
    text = path.read_text(encoding="utf-8")
    found: dict[str, str] = {}
    failures: list[str] = []
    for name in FUNCTIONS:
        src = extract(text, name)
        if src is None:
            failures.append(f"{name}: disappeared")
            continue
        found[name] = hashlib.sha256(src.encode("utf-8")).hexdigest()
    return found, failures


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ekos", required=True, type=Path, help="pinned EKOS checkout")
    ap.add_argument("--populate", action="store_true",
                    help="write drift.json from the checkout (first run)")
    args = ap.parse_args()

    found, failures = hashes(args.ekos)
    commit = ekos_commit(args.ekos)

    if args.populate:
        if failures:
            for failure in failures:
                print(failure, file=sys.stderr)
            return 1
        record = {
            "ekos_commit": commit,
            "recorded": date.today().isoformat(),
            "file": REL,
            "span": "#[test] through the closing brace at the same indentation",
            "functions": {
                name: {"file": REL, "sha256": found[name]} for name in FUNCTIONS
            },
        }
        RECORD.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"populated": len(found), "record": str(RECORD),
                          "ekos_commit": commit}))
        return 0

    if not RECORD.is_file():
        print("drift.json: disappeared", file=sys.stderr)
        return 1
    record = json.loads(RECORD.read_text(encoding="utf-8"))
    recorded = record.get("functions", {})
    for name in FUNCTIONS:
        if name not in recorded:
            failures.append(f"{name}: disappeared")
            continue
        if name not in found:
            continue
        got = found[name]
        want = recorded[name]["sha256"]
        if got != want:
            failures.append(f"{name}: hash changed")
    if commit and record.get("ekos_commit") and commit != record["ekos_commit"]:
        print(f"warning: EKOS is at {commit}, record was taken at {record['ekos_commit']}",
              file=sys.stderr)
    print(json.dumps({
        "record": str(RECORD),
        "functions": len(FUNCTIONS),
        "drifted": len(failures),
        "failures": failures,
    }))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
