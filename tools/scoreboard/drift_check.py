#!/usr/bin/env python3
"""The transcription drift checker (exploration 03 §5.4, option 1).

The panels under panels/ are hand transcriptions of Rust test
functions in the pinned EKOS checkout. A transcription can rot: EKOS can edit a
test and the panel would silently keep feeding the old shape. This checker
hashes the source text of every transcribed test function — located by name,
in the recorded file, inside `mod tests` — and fails when the hash changes.

It does not prove the transcription equals the test; only that the test a human
transcribed has not moved since. The transcription itself is proven the other
way, by the dump's `--expected` run: EKOS's own function must reproduce every
assertion the test makes.

Run with python3 -I; every path is an argument:

    python3 -I tools/scoreboard/drift_check.py --ekos /Users/ember/dev/EKOS \
        --record panels/scope/decision.drift.json --panel panels/scope/decision.jsonl
    python3 -I drift_check.py ... --update     # re-record after a reviewed change

Extraction: a test function starts at a line `    fn <name>(` (mod tests nests
at one indent) and ends at the first following line that is exactly `    }`.
Strings inside these test bodies never sit alone at that indent, so the cut is
unambiguous; if it ever were not, the hash would move and the checker would
say so.

This is the one drift checker; every panel's record is
`panels/<a>/<b>.drift.json`, `{"functions": {name: {"file", "sha256"}}}`.
The span starts at the `fn` line, or, when the record says
`"span": "#[test] through …"` (the branch record, W6), at the `#[test]`
attribute above it.

`--panel PANEL.jsonl` also checks coverage, which the per-lane checkers did
only for identity: every test a panel item cites in its `source`
(`path:LINE name` or `path:name`) must be in the record, so a new item cannot
cite a test nobody pinned.
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


def extract(path: Path, fn: str, from_attr: bool = False) -> str | None:
    """The source text of `fn`, or None when it is not in the file. With
    `from_attr`, the span starts at the `    #[test]` line above `fn`, stepping
    over other attribute lines between them."""
    start = re.compile(rf"^    fn {re.escape(fn)}\(")
    lines = path.read_text().splitlines()
    for i, line in enumerate(lines):
        if start.match(line):
            head = []
            if from_attr:
                j = i - 1
                while j >= 0 and lines[j].startswith("    #["):
                    if lines[j].startswith("    #[test]"):
                        head = lines[j:i]
                        break
                    j -= 1
                else:
                    return None
                if not head:
                    return None
            block = head + [line]
            for j in range(i + 1, len(lines)):
                if lines[j] == "    }":
                    block.append(lines[j])
                    while block and not block[-1].strip():
                        block.pop()
                    return "\n".join(block) + "\n"
                block.append(lines[j])
            return None  # ran off the file: no closing brace at indent 4
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


def normalized(record: dict) -> tuple[dict[str, dict], bool]:
    """(name -> {file, sha256}, span-from-attribute)."""
    from_attr = str(record.get("span", "")).startswith("#[test]")
    return dict(record["functions"]), from_attr


def cited(panel: Path) -> set[tuple[str, str]]:
    """(file, test name) for every panel item whose source cites a test."""
    out = set()
    for line in panel.read_text().splitlines():
        if not line.strip():
            continue
        source = json.loads(line).get("source", "")
        if ":" not in source or "@sha256" in source:
            continue  # a fixture, not a test
        path, rest = source.rsplit(":", 1)
        out.add((path, rest.split()[-1]))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ekos", required=True, type=Path, help="the pinned EKOS checkout")
    ap.add_argument("--record", required=True, type=Path, help="the drift record json")
    ap.add_argument("--panel", type=Path, action="append", default=[],
                    help="a panel JSONL whose cited tests must all be in the record (repeatable)")
    ap.add_argument("--update", action="store_true",
                    help="re-record the hashes (only after a human reviewed the change)")
    args = ap.parse_args()

    record = json.loads(args.record.read_text())
    commit = ekos_commit(args.ekos)
    failures = []
    functions_in, from_attr = normalized(record)

    if args.update:
        functions = {}
        for name, entry in functions_in.items():
            path = args.ekos / entry["file"]
            text = extract(path, name, from_attr)
            if text is None:
                failures.append(f"{name}: not found in {entry['file']}")
                continue
            functions[name] = {
                "file": entry["file"],
                "sha256": hashlib.sha256(text.encode()).hexdigest(),
            }
        out = {"ekos_commit": commit, "recorded": record.get("recorded"), "functions": functions}
        if record.get("span"):
            out["span"] = record["span"]
        args.record.write_text(json.dumps(out, indent=2) + "\n")
        print(json.dumps({"updated": len(functions), "failures": failures}))
        return 1 if failures else 0

    for name, entry in sorted(functions_in.items()):
        path = args.ekos / entry["file"]
        if not path.is_file():
            failures.append(f"{name}: {entry['file']} is gone")
            continue
        text = extract(path, name, from_attr)
        if text is None:
            failures.append(f"{name}: no longer in {entry['file']}")
            continue
        got = hashlib.sha256(text.encode()).hexdigest()
        if got != entry["sha256"]:
            failures.append(f"{name}: hash changed (recorded {entry['sha256'][:12]}, now {got[:12]})")

    pinned = {(e["file"], n) for n, e in functions_in.items()}
    for panel in args.panel:
        for path, name in sorted(cited(panel) - pinned):
            failures.append(f"{name}: cited by {panel} ({path}) but not in the record")

    if commit and record.get("ekos_commit") and commit != record["ekos_commit"]:
        print(f"warning: EKOS is at {commit}, record was taken at {record['ekos_commit']}; "
              "hashes still match, so the transcribed functions are unchanged", file=sys.stderr)

    print(json.dumps({
        "record": str(args.record),
        "functions": len(functions_in),
        "drifted": len(failures),
        "failures": failures,
    }))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
