#!/usr/bin/env python3
"""`verekos check` for the scored panels: run the Lean model, score it, write receipts.

For each panel this runs `check/.lake/build/bin/verekos-check` on the panel
inputs, scores the candidate with `tools/scoreboard/score.py` against EKOS's
control (for `conflicts.unit`, against the join-view projection made by
`tools/scoreboard/project_conflict_keys.py`), and writes, under
`controls/check/` (committed, so the board renders from a clean clone):

    <panel>.candidate.jsonl   the model's answers
    <panel>.verdict.json      score.py's verdict plus `check_build`

It runs `verekos-check laws` on the synthetic run roots in
`check/fixtures/` (expected exit 0 for `synthetic-run`, 1 for
`synthetic-run-bad` and for the `author-from-payload` mutant), on slice 1's
run-2 as converted by `check/slice1_log.py` into `check/fixtures/slice1-run-2`
(expected 0), and on a copy of that log with the review re-signed by the
compiler (expected 1), and writes `laws.<root>[.<mutant>].json`.

It also runs the planted mutant (`scope --mutant deny-ignored`) and writes
`scope.decision.mutant-deny-ignored.verdict.json`; the run fails if the
mutant does not score worse than the faithful mapping.

`check_build` names what produced the candidate: the executable's sha256,
the git tree of `check/` (and whether the working tree differs from it), the
`world` commit `check/lakefile.toml` pins, and the Lean toolchain.

Build first (`cd check && nice -n 10 lake build`); this script never builds.

    python3 -I check/run.py [--classified controls/classified.jsonl]
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXE = ROOT / "check/.lake/build/bin/verekos-check"
OUT = ROOT / "controls/check"
SCORE = ROOT / "tools/scoreboard/score.py"
PROJECT = ROOT / "tools/scoreboard/project_conflict_keys.py"

# Panel and control paths come from panels/LABELS.json, the board's own source.
LABELS = json.loads((ROOT / "panels/LABELS.json").read_text())["panels"]
SCOPE_PANEL = LABELS["scope.decision"]["panel_file"]
SCOPE_CONTROL = LABELS["scope.decision"]["control_file"]
CONFLICTS_PANEL = LABELS["conflicts.unit"]["panel_file"]
CONFLICTS_CONTROL = LABELS["conflicts.unit"]["control_file"]
PANELS = [
    # panel, kernel, runner args, panel inputs, control the candidate is scored against
    ("scope.decision", "scope", ["scope"], SCOPE_PANEL, SCOPE_CONTROL),
    ("conflicts.unit", "conflicts", ["conflicts"], CONFLICTS_PANEL,
     "controls/check/conflicts.unit.keys.control.jsonl"),
]
MUTANT = ("scope.decision.mutant-deny-ignored", "scope", ["scope", "--mutant", "deny-ignored"],
          SCOPE_PANEL, SCOPE_CONTROL)


def sha256_file(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True,
                          capture_output=True, text=True).stdout.strip()


def build_info() -> dict:
    lakefile = (ROOT / "check/lakefile.toml").read_text()
    m = re.search(r'name = "world"\s*\ngit = "[^"]*"\s*\nrev = "([0-9a-f]+)"', lakefile)
    dirty = git("status", "--porcelain", "--", "check/") != ""
    return {
        "exe_sha256": sha256_file(EXE),
        "check_tree": git("rev-parse", "HEAD:check"),
        "check_dirty": dirty,
        "world_rev": m.group(1) if m else None,
        "toolchain": (ROOT / "check/lean-toolchain").read_text().strip(),
    }


def run_one(name, kernel, args, panel, control, classified, info):
    cand = OUT / f"{name}.candidate.jsonl"
    with open(ROOT / panel) as stdin:
        r = subprocess.run([str(EXE), *args], stdin=stdin, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"verekos-check {' '.join(args)} failed ({r.returncode}): {r.stderr}")
    cand.write_text(r.stdout)
    verdict = OUT / f"{name}.verdict.json"
    cmd = [sys.executable, "-I", str(SCORE), "--kernel", kernel, "--panel", str(ROOT / panel),
           "--control", str(ROOT / control), "--candidate", str(cand), "--out", str(verdict)]
    if classified:
        cmd += ["--classified", str(ROOT / classified)]
    s = subprocess.run(cmd, capture_output=True, text=True)
    print(f"== {name}")
    print(s.stdout.rstrip())
    v = json.loads(verdict.read_text())
    v["control"] = control
    v["candidate"] = str(cand.relative_to(ROOT))
    v["score_exit"] = s.returncode
    v["check_build"] = info
    verdict.write_text(json.dumps(v, indent=2) + "\n")
    return v


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--classified", default="controls/classified.jsonl")
    a = ap.parse_args()
    if not EXE.is_file():
        sys.exit(f"{EXE} is missing: cd check && nice -n 10 lake build")
    OUT.mkdir(parents=True, exist_ok=True)
    p = subprocess.run([sys.executable, "-I", str(PROJECT), "--panel",
                        str(ROOT / CONFLICTS_PANEL), "--control",
                        str(ROOT / CONFLICTS_CONTROL), "--out",
                        str(OUT / "conflicts.unit.keys.control.jsonl")])
    if p.returncode != 0:
        sys.exit("key projection failed")
    info = build_info()
    print(json.dumps({"check_build": info}))
    worst = 0
    faithful = {}
    for row in PANELS:
        v = run_one(*row, a.classified, info)
        faithful[row[0]] = v
        worst = max(worst, v["score_exit"])
    # slice 1's real run, converted by check/slice1_log.py, and the same log
    # with the review re-signed by the compiler (a planted change to real data)
    real = ROOT / "check/fixtures/slice1-run-2"
    resigned = ROOT / "var/check/slice1-run-2.review-signed-by-compiler"
    resigned.mkdir(parents=True, exist_ok=True)
    principals = json.loads((real / "principals.json").read_text())
    for f in ("principals.json", "expect.json"):
        (resigned / f).write_text((real / f).read_text())
    (resigned / "log.jsonl").write_text("".join(
        json.dumps({**l, "signer": principals["compiler"]} if l["stage"] == "review" else l) + "\n"
        for l in map(json.loads, (real / "log.jsonl").read_text().splitlines())))
    for root, mutant, want in [("synthetic-run", None, 0), ("synthetic-run-bad", None, 1),
                               ("synthetic-run", "author-from-payload", 1),
                               ("slice1-run-2", None, 0),
                               (resigned, None, 1)]:
        path = root if isinstance(root, Path) else ROOT / "check/fixtures" / root
        root = path.name
        args = ["laws"] + (["--mutant", mutant] if mutant else []) + [str(path)]
        r = subprocess.run([str(EXE), *args], capture_output=True, text=True)
        name = f"laws.{root}.{mutant}" if mutant else f"laws.{root}"
        out = {"root": str(path.relative_to(ROOT)), "synthetic": root.startswith("synthetic"),
               "mutant": mutant,
               "exit": r.returncode, "expected_exit": want,
               "report": json.loads(r.stdout) if r.stdout.strip() else None,
               "stderr": r.stderr.strip(), "check_build": info}
        (OUT / f"{name}.json").write_text(json.dumps(out, indent=2) + "\n")
        print(f"== {name}: exit {r.returncode} (expected {want})")
        if r.returncode != want:
            worst = max(worst, 1)
    m = run_one(*MUTANT, a.classified, info)
    if m["agree"] >= faithful["scope.decision"]["agree"]:
        print("the deny-ignored mutant does not score worse: the panel cannot see deny")
        return 1
    print(f"mutant: {m['agree']}/{m['items']} agree, faithful "
          f"{faithful['scope.decision']['agree']}/{faithful['scope.decision']['items']}")
    return worst


if __name__ == "__main__":
    sys.exit(main())
