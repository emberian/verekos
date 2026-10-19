#!/usr/bin/env python3
"""Score a candidate against the control (exploration 03 §3, §5.3).

The law: zero *unexplained* differences per panel. This script diffs a
candidate output file (one JSON line per panel item, the same shape the
control-dump writes: `{"item": ..., <answer fields>}`) against the committed
control, classifies every difference against `controls/classified.jsonl`, and
prints the counts plus the UNEXPLAINED list. Exit status is 1 when anything is
unexplained or classified as `verekos_defect`, 2 on malformed input.

A classification is keyed by the sha256 of the canonical
(panel, item, control, candidate) tuple — the whole answer values, not a field
path — so changing the control, the candidate or the item id changes the hash
and the difference counts as unexplained again until re-classified
(exploration 03 §3.4). Classes: `ekos_defect`, `verekos_defect`, `non_goal`.

Only `ekos_defect` and `non_goal` explain a difference. A `verekos_defect`
entry names a known fault in our own candidate: it is reported and counted,
but it stays red (exit 1) until the candidate is fixed (exploration 03 §3.3,
docs/parity/README.md).

Run with python3 -I; every path is an argument:

    python3 -I score.py --kernel scope --panel panels/scope/decision.jsonl \
        --control controls/scope.decision.control.jsonl --candidate <file> \
        [--classified controls/classified.jsonl] [--out var/w9/<verdict>.json]

Differences:
  mismatch  item in both, answers differ
  missing   item in the control, absent from the candidate
  extra     item in the candidate only (the control value hashes as null)
"""

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

CLASSES = ("ekos_defect", "verekos_defect", "non_goal")


def canonical(value) -> str:
    """The stable text a value is compared and hashed as."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_of(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def read_lines(path: Path, what: str) -> list[tuple[str, dict]]:
    """(item id, answer object) per non-empty line; duplicate ids are fatal."""
    out = []
    seen = set()
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            v = json.loads(line)
        except json.JSONDecodeError as e:
            sys.exit(f"{path}:{number}: not JSON: {e}")
        if not isinstance(v, dict) or not isinstance(v.get("item"), str):
            sys.exit(f"{path}:{number}: {what} line needs a string 'item'")
        if v["item"] in seen:
            sys.exit(f"{path}:{number}: duplicate item {v['item']!r}")
        seen.add(v["item"])
        answer = {k: w for k, w in v.items() if k != "item"}
        out.append((v["item"], answer))
    return out


def panel_names(panel_path: Path) -> dict[str, str]:
    """item id -> panel name, from the panel file's own envelope (§1.2)."""
    out = {}
    fallback = panel_path.stem
    for number, line in enumerate(panel_path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            v = json.loads(line)
        except json.JSONDecodeError as e:
            sys.exit(f"{panel_path}:{number}: not JSON: {e}")
        name = v.get("panel") if isinstance(v, dict) else None
        out[v.get("item", f"?{number}")] = name if isinstance(name, str) else fallback
    return out


def read_classified(path: Path | None) -> dict[str, dict]:
    """diff_id -> entry, from the append-only classification manifest."""
    if path is None or not path.is_file():
        return {}
    entries = {}
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            v = json.loads(line)
        except json.JSONDecodeError as e:
            sys.exit(f"{path}:{number}: not JSON: {e}")
        missing = [k for k in ("diff_id", "panel", "item", "class", "reason") if k not in v]
        if missing:
            sys.exit(f"{path}:{number}: classified line missing {missing}")
        if v["class"] not in CLASSES:
            sys.exit(f"{path}:{number}: class {v['class']!r} not one of {CLASSES}")
        if v["diff_id"] in entries:
            sys.exit(f"{path}:{number}: duplicate diff_id {v['diff_id'][:12]}")
        entries[v["diff_id"]] = v
    return entries


def diff_id_for(panel: str, item: str, control, candidate) -> str:
    return sha256_of(canonical(
        {"panel": panel, "item": item, "control": control, "candidate": candidate}))


def score(kernel, panel_path, control_path, candidate_path, classified):
    control = read_lines(control_path, "control")
    candidate = dict(read_lines(candidate_path, "candidate"))
    names = panel_names(panel_path)

    rows = []  # (item, kind, control answer, candidate answer)
    agree = 0
    for item, answer in control:
        got = candidate.pop(item, None)
        if got is None:
            rows.append((item, "missing", answer, None))
        elif canonical(got) == canonical(answer):
            agree += 1
        else:
            rows.append((item, "mismatch", answer, got))
    for item, answer in sorted(candidate.items()):
        rows.append((item, "extra", None, answer))

    out = []
    unexplained = []
    for item, kind, want, got in rows:
        panel = names.get(item, panel_path.stem)
        did = diff_id_for(panel, item, want, got)
        entry = classified.get(did)
        if entry is None:
            unexplained.append((item, kind, want, got, did))
        else:
            out.append((item, kind, entry, did))
    red = [r for r in out if r[2]["class"] == "verekos_defect"]

    return {
        "kernel": kernel,
        # the envelope's panel name(s), not the file stem: several panels
        # keep their inputs in a file called items.jsonl
        "panel": ",".join(sorted(set(names.values()))) or panel_path.stem,
        "items": len(control),
        "agree": agree,
        "mismatch": sum(1 for r in rows if r[1] == "mismatch"),
        "missing": sum(1 for r in rows if r[1] == "missing"),
        "extra": sum(1 for r in rows if r[1] == "extra"),
        "classified": len(out),
        "verekos_defect": len(red),
        "unexplained": len(unexplained),
        "_rows": rows,
        "_classified": out,
        "_unexplained": unexplained,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--kernel", required=True, help="kernel name, e.g. scope")
    ap.add_argument("--panel", required=True, type=Path, help="the panel JSONL (inputs only)")
    ap.add_argument("--control", required=True, type=Path, help="the committed control JSONL")
    ap.add_argument("--candidate", required=True, type=Path,
                    help="the candidate output, same JSONL shape as the control")
    ap.add_argument("--classified", type=Path, default=None,
                    help="controls/classified.jsonl (default: nothing is classified)")
    ap.add_argument("--out", type=Path, default=None,
                    help="write a verdict json here (created last, §5.3)")
    args = ap.parse_args()

    classified = read_classified(args.classified)
    r = score(args.kernel, args.panel, args.control, args.candidate, classified)

    print(json.dumps({k: v for k, v in r.items() if not k.startswith("_")}))
    if r["_unexplained"]:
        print("UNEXPLAINED:")
        for item, kind, want, got, did in r["_unexplained"]:
            print(f"  {item} [{kind}] diff_id={did}")
            print(f"    control   {canonical(want)}")
            print(f"    candidate {canonical(got)}")
    if r["_classified"]:
        print("CLASSIFIED:")
        for item, kind, entry, did in r["_classified"]:
            print(f"  {item} [{kind}] {entry['class']}: {entry['reason']}")

    if args.out:
        verdict = {k: v for k, v in r.items() if not k.startswith("_")}
        verdict.update({
            "panel_sha256": sha256_of(args.panel.read_text()),
            "control_sha256": sha256_of(args.control.read_text()),
            "candidate_sha256": sha256_of(args.candidate.read_text()),
            "classified_sha256": (sha256_of(args.classified.read_text())
                                  if args.classified and args.classified.is_file() else None),
            "recorded": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        })
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(verdict, indent=2) + "\n")

    return 1 if (r["unexplained"] or r["verekos_defect"]) else 0


if __name__ == "__main__":
    sys.exit(main())
