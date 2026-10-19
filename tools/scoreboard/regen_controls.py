#!/usr/bin/env python3
"""Regenerate the controls (exploration 03 §5.2) — the one command that

  1. requires a clean EKOS tree and records its commit and tree hash;
  2. rebuilds control-dump when its sources moved (nice -n 10 cargo build,
     logged under var/w9/);
  3. runs every dump twice (the §3.5-3 reproducibility self-check) with
     `--expected`, so every transcribed assertion must reproduce;
  4. compares each run against the committed control file: byte-identical,
     or a report of exactly which items moved — a differing control is only
     overwritten with --accept;
  5. runs every drift checker (transcribed tests unchanged in the pin, and
     every test a panel cites is pinned);
  0. before the ledger versions dumps, rebuilds a missing var/w18/<fixture>
     workspace with run_fixture.py (so a fresh clone can regenerate), and
     compares those controls without the fields that carry EKOS#10's random
     evidence ids (LEDGER_VOLATILE);
  6. rewrites controls/MANIFEST.json: EKOS commit + tree hash, dump binary
     sha256 + source tree hash, panel and control file sha256s, the drift
     records, and the reproducibility result, with a UTC timestamp.

Run with python3 -I; every path is an argument or repo-relative:

    python3 -I tools/scoreboard/regen_controls.py --ekos /Users/ember/dev/EKOS [--accept]

PANELS below names every dump; adding a panel means adding one row and
putting its four files at the paths the panel name implies.
"""

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
DUMP = HERE / "control-dump"

# One row per panel: (panel name, control-dump subcommand, extra args). Every
# path follows from the name a.b (the lane C layout, CLAUDE.md "Panel
# conventions"): inputs panels/a/b.jsonl, the transcribed assertions
# controls/a.b.expected.jsonl, EKOS's answers controls/a.b.control.jsonl, the
# drift record panels/a/b.drift.json, checked by tools/scoreboard/drift_check.py.
PANELS = [
    ("scope.decision", "scope", []),
    ("conflicts.unit", "conflicts", []),
    ("scope.store", "store", []),
    ("identity.unit", "identity", []),
    ("branch.unit", "branch", []),
    ("impact.unit", "impact", []),
    ("redact.unit", "redact", []),
    ("ekl.parser", "ekl", ["--which", "ekl.parser"]),
    ("ekl.interpreter", "ekl", ["--which", "ekl.interpreter"]),
]


def panel_entry(name: str, sub: str, extra: list[str]) -> dict:
    family, variant = name.split(".", 1)
    return {"name": name, "sub": sub, "args": extra,
            "panel": f"panels/{family}/{variant}.jsonl",
            "expected": f"controls/{name}.expected.jsonl",
            "control": f"controls/{name}.control.jsonl",
            "drift": ["python3", "-I", "tools/scoreboard/drift_check.py", "--ekos", "{ekos}",
                      "--record", f"panels/{family}/{variant}.drift.json",
                      "--panel", f"panels/{family}/{variant}.jsonl"]}


REGISTRY = [panel_entry(*row) for row in PANELS]

# The ledger versions controls (W20) take a WORKSPACE DIRECTORY, a real
# fixture build whose .ekos/ledger/facts is opened read-only, not a
# panel+expected pair. The workspace lives in git-ignored var/w18/<name>/ws;
# when it is missing (a fresh clone, or var/ cleared) regen rebuilds it with
# run_fixture.py from the fixture the panel names, checking its sha256 first
# (R1 finding S3). A rebuilt workspace has fresh v4 evidence ids (EKOS#10), so
# the committed control is compared on a projection without the fields that
# carry them (LEDGER_VOLATILE, recorded in MANIFEST); the two runs on one
# workspace must still be byte-identical.
LEDGER_REGISTRY = [
    {"run": "ledger", "name": n, "workspace": f"var/w18/{n.split('.')[1]}/ws",
     "panel": f"panels/ledger/{n.split('.')[1]}.jsonl",
     "control": f"controls/{n}.versions.control.jsonl"}
    for n in ("ledger.ecommerce", "ledger.northwind")
]

# Per object: the evidence id lists, and the two signatures computed over
# the object payload including those lists. The no-evidence signatures stay
# compared, so a real content change still moves the control. `workspace` is
# the absolute path the dump was run on.
LEDGER_VOLATILE = {"top": ["workspace"],
                   "objects": ["evidence", "signature", "version_evidence", "version_signatures"]}


def ledger_projection(line: str) -> str:
    v = json.loads(line)
    for k in LEDGER_VOLATILE["top"]:
        v.pop(k, None)
    for obj in v.get("objects", []):
        for k in LEDGER_VOLATILE["objects"]:
            obj.pop(k, None)
    return json.dumps(v, sort_keys=True)


def ensure_workspace(entry: dict, ekos_binary: Path) -> dict:
    """Rebuild var/w18/<name> through run_fixture.py when its ws is missing."""
    ws = ROOT / entry["workspace"]
    if (ws / ".ekos").is_dir():
        return {"rebuilt": False, **sidecar_of(ws.parent)}
    item = json.loads((ROOT / entry["panel"]).read_text().splitlines()[0])
    fixture = Path(item["input"]["fixture"])
    if sha256_of(fixture.read_bytes()) != item["input"]["fixture_sha256"]:
        sys.exit(f"{fixture} no longer hashes to the panel's fixture_sha256; refusing to rebuild")
    out = ws.parent
    if out.exists() and any(out.iterdir()):
        sys.exit(f"{out} exists without a compiled ws; move it aside and re-run")
    p = subprocess.run(["python3", "-I", str(HERE / "run_fixture.py"), "run",
                        "--fixture", str(fixture), "--out", str(out), "--ekos", str(ekos_binary)],
                       capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"run_fixture.py failed for {entry['name']}:\n{p.stdout}{p.stderr}")
    print(json.dumps({"rebuilt_workspace": entry["workspace"]}))
    return {"rebuilt": True, **sidecar_of(out)}


def sidecar_of(run_dir: Path) -> dict:
    """The binary and fixture run_fixture.py recorded for this workspace."""
    path = run_dir / "sidecar.json"
    if not path.is_file():
        return {"sidecar": None}
    sidecar = json.loads(path.read_text())
    return {"ekos_binary_sha256": sidecar["ekos_binary"]["sha256"],
            "fixture_sha256": sidecar["fixture"]["sha256"]}


def sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(cmd, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=True, **kw)


def git(ekos: Path, *args) -> str:
    return run(["git", "-C", str(ekos), *args]).stdout.strip()


def build_if_needed(force: bool, log_dir: Path, pin_moved: bool) -> dict:
    binary = DUMP / "target/debug/control-dump"
    sources = sorted((DUMP / "src").glob("*.rs")) + [DUMP / "Cargo.toml", DUMP / "Cargo.lock"]
    newest = max(p.stat().st_mtime_ns for p in sources)
    needed = (force or pin_moved or not binary.is_file()
              or binary.stat().st_mtime_ns < newest)
    if not needed:
        return {"built": False, "log": None}
    log_dir.mkdir(parents=True, exist_ok=True)
    log = log_dir / f"build-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.log"
    with log.open("w") as fh:
        p = subprocess.run(["nice", "-n", "10", "cargo", "build"], cwd=DUMP,
                           stdout=fh, stderr=subprocess.STDOUT)
    if p.returncode != 0:
        sys.exit(f"cargo build failed, log: {log}")
    return {"built": True, "log": str(log.relative_to(ROOT))}


def source_tree_sha() -> str:
    """sha256 over each source file's own sha256, in sorted path order."""
    sources = sorted((DUMP / "src").glob("*.rs")) + [DUMP / "Cargo.toml", DUMP / "Cargo.lock"]
    return sha256_of("".join(sha256_of(p.read_bytes()) + "  " + p.name + "\n"
                             for p in sorted(sources)).encode())


def run_dump(entry: dict, out: Path) -> dict:
    """One dump run with --expected; returns its stderr report (parsed)."""
    with out.open("w") as fh:
        p = subprocess.run(
            [str(DUMP / "target/debug/control-dump"), entry["sub"],
             str(ROOT / entry["panel"]), "--expected", str(ROOT / entry["expected"]),
             *entry["args"]],
            stdout=fh, stderr=subprocess.PIPE, text=True)
    report = {}
    for line in p.stderr.splitlines():
        try:
            v = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(v, dict) and "panel" in v:
            report = v
    if p.returncode != 0:
        sys.exit(f"dump {entry['name']} failed (exit {p.returncode}):\n{p.stderr}")
    if not report or "items" not in report:
        sys.exit(f"dump {entry['sub']}: no panel summary on stderr:\n{p.stderr}")
    if report["agree"] != report["items"] or report["mismatch"] or report["missing"]:
        sys.exit(f"dump {entry['sub']}: transcribed assertions did not all reproduce: {report}\n{p.stderr}")
    return report


def run_ledger_dump(entry: dict, out: Path) -> dict:
    """One ledger-versions dump run (workspace input, no expected file);
    returns its stderr report (parsed). Same contract as run_dump."""
    with out.open("w") as fh:
        p = subprocess.run(
            [str(DUMP / "target/debug/control-dump"), entry["run"],
             str(ROOT / entry["workspace"]), "--panel", str(ROOT / entry["panel"])],
            stdout=fh, stderr=subprocess.PIPE, text=True)
    report = {}
    for line in p.stderr.splitlines():
        try:
            v = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(v, dict) and "panel" in v:
            report = v
    if p.returncode != 0:
        sys.exit(f"ledger dump {entry['workspace']} failed (exit {p.returncode}):\n{p.stderr}")
    if not report or "items" not in report:
        sys.exit(f"ledger dump {entry['workspace']}: no panel summary on stderr:\n{p.stderr}")
    return report


def moved_items(committed: Path, fresh: Path) -> list[str]:
    def by_item(path):
        out = {}
        for line in path.read_text().splitlines():
            if line.strip():
                v = json.loads(line)
                out[v.get("item", "?")] = line
        return out
    old, new = by_item(committed), by_item(fresh)
    moved = [k for k in sorted(set(old) | set(new)) if old.get(k) != new.get(k)]
    return moved


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ekos", required=True, type=Path, help="the pinned EKOS checkout")
    ap.add_argument("--accept", action="store_true",
                    help="overwrite committed controls whose bytes moved (reported first)")
    ap.add_argument("--force-build", action="store_true", help="cargo build even if nothing moved")
    ap.add_argument("--ekos-binary", type=Path,
                    default=Path("/Users/ember/dev/EKOS/ekos/target/release/ekos"),
                    help="the release binary run_fixture.py uses to rebuild a missing workspace")
    args = ap.parse_args()

    dirty = git(args.ekos, "status", "--porcelain")
    if dirty:
        sys.exit(f"EKOS tree is dirty:\n{dirty}\n(refusing; the control must name a clean pin)")
    commit = git(args.ekos, "rev-parse", "HEAD")
    tree = git(args.ekos, "rev-parse", "HEAD^{tree}")
    print(json.dumps({"ekos_commit": commit, "ekos_tree": tree, "dirty": False}))

    old = {}
    if (ROOT / "controls/MANIFEST.json").is_file():
        old = json.loads((ROOT / "controls/MANIFEST.json").read_text())
        if old.get("ekos", {}).get("commit") not in (None, commit):
            print(json.dumps({"warning": "EKOS pin moved since the last manifest",
                              "was": old["ekos"]["commit"], "now": commit}))
    # EKOS crates are path dependencies: a moved pin must rebuild even when
    # this workspace's own sources did not change.
    pin_moved = bool(old) and old.get("ekos", {}).get("commit") != commit

    build = build_if_needed(args.force_build, ROOT / "var/w9", pin_moved)
    binary = DUMP / "target/debug/control-dump"
    print(json.dumps({"build": build, "binary_sha256": sha256_of(binary.read_bytes())}))

    results = []

    def drive(entry: dict, runner) -> None:
        """Double-run one entry, byte-compare, compare the committed control."""
        run1, run2 = tmp / "run1.jsonl", tmp / "run2.jsonl"
        report = runner(entry, run1)
        runner(entry, run2)
        repro = run1.read_bytes() == run2.read_bytes()
        committed = ROOT / entry["control"]
        if committed.is_file():
            same = run1.read_bytes() == committed.read_bytes()
            status = "identical" if same else "moved"
            if not same and entry.get("run") == "ledger" and (
                    ledger_projection(run1.read_text()) == ledger_projection(committed.read_text())):
                same, status = True, "identical_modulo_volatile"
            moved = [] if same else moved_items(committed, run1)
            if not same and args.accept:
                committed.write_bytes(run1.read_bytes())
                same, status = True, "accepted"
        else:
            committed.write_bytes(run1.read_bytes())
            moved, same, status = [], True, "written_new"
        results.append({
            "control": entry["control"], "panel": entry["panel"],
            "items": report.get("items"), "agree": report.get("agree"),
            "reproducible": repro, "committed_control": status, "moved_items": moved,
        } | ({"workspace": entry["workspace"], **entry.get("_ws", {})}
             if entry.get("run") == "ledger" else {}))
        print(json.dumps(results[-1]))
        if not repro:
            sys.exit(f"{entry['control']}: two runs differ — the volatile-field list must grow "
                     "before this control can be trusted")

    with tempfile.TemporaryDirectory(prefix="verekos-regen-", dir=str(ROOT / "var/w9")) as td:
        tmp = Path(td)
        for entry in REGISTRY:
            drive(entry, run_dump)
        for entry in LEDGER_REGISTRY:
            entry["_ws"] = ensure_workspace(entry, args.ekos_binary)
            drive(entry, run_ledger_dump)

    drift_results = []
    for entry in REGISTRY:
        cmd = [c.replace("{ekos}", str(args.ekos)) for c in entry["drift"]]
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        drift_results.append({"cmd": " ".join(cmd), "exit": p.returncode,
                              "out": (p.stdout or p.stderr).strip().splitlines()[-1] if (p.stdout or p.stderr).strip() else ""})
        if p.returncode != 0:
            sys.exit(f"drift check failed: {' '.join(cmd)}\n{p.stdout}{p.stderr}")
    for d in drift_results:
        print(json.dumps({"drift": d["cmd"], "exit": d["exit"], "out": d["out"]}))

    if any(r["committed_control"] == "moved" for r in results):
        sys.exit("committed controls moved; re-run with --accept after reviewing the moved_items lists")

    manifest = {
        "ekos": {"repo": str(args.ekos), "commit": commit, "tree": tree, "dirty": False},
        "dump_binary": {
            "path": "tools/scoreboard/control-dump/target/debug/control-dump",
            "sha256": sha256_of(binary.read_bytes()),
            "source_tree_sha256": source_tree_sha(),
            "source_files": sorted(str(p.relative_to(ROOT)) for p in (DUMP / "src").glob("*.rs")),
            "build_log": build["log"],
        },
        "panels": {e["panel"]: sha256_of((ROOT / e["panel"]).read_bytes())
                   for e in REGISTRY + LEDGER_REGISTRY},
        "controls": {f: sha256_of((ROOT / f).read_bytes())
                     for e in REGISTRY for f in (e["expected"], e["control"])}
                   | {e["control"]: sha256_of((ROOT / e["control"]).read_bytes())
                      for e in LEDGER_REGISTRY},
        "runs": results,
        "drift_checks": drift_results,
        "volatile_fields_stripped": ["created_at"],
        "ledger_versions_compared_without": LEDGER_VOLATILE,
        "recorded": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    (ROOT / "controls/MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"manifest": "controls/MANIFEST.json",
                      "sha256": sha256_of((ROOT / "controls/MANIFEST.json").read_bytes())}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
