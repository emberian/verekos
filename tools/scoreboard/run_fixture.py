#!/usr/bin/env python3
"""Run one EKOS fixture through the real pipeline and write the ledger controls.

Exploration 03 §1.3, route (a): a fixture (a .sql schema) is copied into a
scratch workspace, the six-stage pipeline (`ekos init && ekos build && ekos
recover && ekos resolve && ekos compile && ekos commit --yes`) runs with the
release binary under `nice -n 10`, and the controls are written out: the graph
export ndjson (nodes + edges only), the EKL object and relationship rows
sorted by id, and `ekos status --json` (plus `ekos conflicts list --json` for
the counts panel). A sidecar records the binary sha256, the EKOS commit, the
fixture sha256 and the wall-clock time of every stage.

The workspace ekos.toml is byte-for-byte `ekos init`'s generated default
(`[observe] paths = ["."]`), which observes the fixture copy and nothing else:
the ws holds only `schemas/<fixture>.sql`, and `.ekos` is in the default
ignore-patterns. Sources are never written to — the fixture itself is only
ever read; the copy exists so the pipeline cannot touch the EKOS checkout even
by accident.

EKOS_HOME points at a fresh scratch home (never ~/.ekos) and the five
selectors the leak suite scrubs (EKOS_PROJECT, EKOS_TENANT, EKOS_CONFIG,
EKOS_WORKSPACE, EKOS_READ_SCOPE) are removed from every invocation, so a run
cannot land in some other workspace.

    python3 -I tools/scoreboard/run_fixture.py run \
        --fixture /Users/ember/dev/EKOS/tests/fixtures/ecommerce.sql \
        --out var/w18/ecommerce \
        [--ekos /path/to/ekos] [--controls-dir controls] \
        [--panel-file panels/ledger/items.jsonl]

`--controls-dir` copies the five control files + sidecar to
`<dir>/ledger.<name>.<suffix>` (the committed control). `--panel-file`
upserts the panel item — inputs only, never EKOS's answers (§1.1):
`{"panel":"ledger.<name>","item":"<name>","origin":"fixture",
  "source":"<fixture path>@sha256:<sha>","input":{fixture, fixture_sha256}}`.

    python3 -I tools/scoreboard/run_fixture.py compare \
        --a var/w18/ecommerce --b var/w18/ecommerce-rerun [--report FILE]

`compare` (the §3.5-3 control-reproducibility check) diffs two run
directories field by field — graph header, nodes keyed by id, edges mapped to
(source id, target id, kind name), EKL rows keyed by id, status, conflicts —
and reports exactly which fields differ, split into volatile (timestamps,
workspace paths, state-file sizes: `generated_at`, `workspace`, `as_of`,
node/edge `fs`, `last_write`, `storage`, `freshness`) and content. Exit 1
when anything non-volatile differs, 0 when the two runs agree modulo the
named volatile fields. The report names every field that moved, so a field
that diverges can never silently become a compared field later.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

# read_scope.rs:40-52 scrubs these; so does this driver.
SCRUB_ENV = ("EKOS_PROJECT", "EKOS_TENANT", "EKOS_CONFIG", "EKOS_WORKSPACE", "EKOS_READ_SCOPE")

# Exactly `ekos init`'s DEFAULT_CONFIG (commands/init.rs): the ws contains
# only schemas/<fixture>.sql, so paths = ["."] observes the fixture alone.
EKOS_TOML = """[workspace]
root = "."
log-level = "info"
log-format = "pretty"

[observe]
paths = ["."]
ignore-patterns = [".ekos", ".git", "target", "node_modules"]
"""

# Run-volatile: expected to differ between two runs on the same fixture and
# never a compared field (§3.5-3 names them; the report records what moved).
VOLATILE_HEADER = {"generated_at", "workspace", "as_of"}
VOLATILE_NODE_EDGE = {"fs"}
VOLATILE_STATUS_PREFIXES = ("workspace", "last_write", "storage", "freshness")

CONTROL_FILES = ("graph.ndjson", "objects.jsonl", "relationships.jsonl",
                 "status.json", "conflicts.json", "sidecar.json")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def stage_env(home: Path) -> dict:
    env = {k: v for k, v in os.environ.items() if k not in SCRUB_ENV}
    env["EKOS_HOME"] = str(home)
    return env


def git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True,
                          text=True, check=True).stdout.strip()


class Runner:
    """Every ekos invocation: nice -n 10, clean env, logged, timed."""

    def __init__(self, ekos: Path, ws: Path, home: Path, log_dir: Path):
        self.ekos = ekos
        self.ws = ws
        self.home = home
        self.log_dir = log_dir

    def _run(self, name: str, args: list[str]) -> tuple[subprocess.CompletedProcess, float]:
        log = self.log_dir / f"{name}.log"
        t0 = time.monotonic()
        with log.open("w") as fh:
            p = subprocess.run(["nice", "-n", "10", str(self.ekos), *args],
                               cwd=self.ws, stdout=subprocess.PIPE,
                               stderr=fh, text=True)
        return p, time.monotonic() - t0

    def stage(self, name: str, args: list[str]) -> float:
        """A pipeline stage: output to its log, fatal on failure, returns seconds."""
        p, dt = self._run(name, args)
        if p.returncode != 0:
            sys.exit(f"stage {name} failed (exit {p.returncode}); log: "
                     f"{self.log_dir / (name + '.log')}")
        return dt

    def capture(self, name: str, args: list[str]) -> tuple[str, float]:
        """A control command: stdout is the artifact, fatal on failure."""
        p, dt = self._run(name, args)
        if p.returncode != 0:
            sys.exit(f"control {name} failed (exit {p.returncode}); log: "
                     f"{self.log_dir / (name + '.log')}")
        return p.stdout, dt


def load_graph(path: Path) -> dict:
    """header, nodes, edges — the ndjson records carry a `record` tag."""
    lines = [ln for ln in path.read_text().splitlines() if ln.strip()]
    header = json.loads(lines[0])
    nodes, edges = [], []
    for ln in lines[1:]:
        v = json.loads(ln)
        kind = v.get("record")
        if kind == "node" or (kind is None and "n" in v):
            nodes.append(v)
        elif kind == "edge" or (kind is None and "s" in v):
            edges.append(v)
        else:
            sys.exit(f"{path}: unrecognized record: {ln[:80]}")
    return {"header": header, "nodes": nodes, "edges": edges}


def write_jsonl(path: Path, rows: list[dict]) -> None:
    """Canonical JSONL: rows sorted by id upstream, keys sorted here — the
    EKL rows come out of a HashMap (per-row key order varies per process), so
    without this no two runs would be byte-identical."""
    path.write_text("".join(json.dumps(r, sort_keys=True, ensure_ascii=False) + "\n"
                            for r in rows))


def upsert_panel(panel_file: Path, entry: dict) -> None:
    """Replace the line with this item id, or append it (inputs only, §1.1)."""
    kept = []
    if panel_file.is_file():
        for ln in panel_file.read_text().splitlines():
            if not ln.strip():
                continue
            if json.loads(ln).get("item") != entry["item"]:
                kept.append(ln)
    kept.append(json.dumps(entry, ensure_ascii=False, sort_keys=True))
    panel_file.parent.mkdir(parents=True, exist_ok=True)
    panel_file.write_text("\n".join(kept) + "\n")


def cmd_run(args) -> int:
    fixture = args.fixture.resolve()
    if not fixture.is_file():
        sys.exit(f"fixture not found: {fixture}")
    name = fixture.stem
    out = args.out.resolve()
    if out.exists() and any(out.iterdir()):
        sys.exit(f"output dir {out} exists and is not empty; give a fresh --out")
    ws, home, logs = out / "ws", out / "home", out / "logs"
    (ws / "schemas").mkdir(parents=True)
    home.mkdir(parents=True)
    logs.mkdir(parents=True)

    fixture_sha = sha256_file(fixture)
    copy = ws / "schemas" / fixture.name
    shutil.copy2(fixture, copy)
    if sha256_file(copy) != fixture_sha:
        sys.exit("fixture copy hash mismatch (copy aborted)")

    ekos = args.ekos.resolve()
    r = Runner(ekos, ws, home, logs)

    # The six-stage pipeline (§1.3). init writes the default ekos.toml; ours
    # is byte-identical to it, written explicitly so the observe relationship
    # is pinned by this script, not by init's churn.
    timings = {"init": r.stage("init", ["init"])}
    (ws / "ekos.toml").write_text(EKOS_TOML)
    for stage in ("build", "recover", "resolve", "compile"):
        timings[stage] = r.stage(stage, [stage])
    timings["commit"] = r.stage("commit", ["commit", "--yes"])

    # Controls.
    graph_path = out / "graph.ndjson"
    timings["graph-export"] = r.stage(
        "graph-export",
        ["graph", "export", "--format", "ndjson", "--max-nodes", "1000000",
         "--max-edges", "1000000", "--first-seen", "--output", str(graph_path)])
    graph = load_graph(graph_path)
    truncated = graph["header"].get("truncated") or {}
    if truncated.get("nodes") or truncated.get("edges"):
        sys.exit(f"graph export truncated at the caps; raise them: "
                 f"{json.dumps(truncated)} {json.dumps(graph['header'].get('counts'))}")

    objects_txt, timings["ekl-objects"] = r.capture("ekl-objects", ["ekl", "FIND Object", "--json"])
    objects = json.loads(objects_txt)
    write_jsonl(out / "objects.jsonl", sorted(objects, key=lambda row: row.get("id", "")))

    rels_txt, timings["ekl-relationships"] = r.capture(
        "ekl-relationships", ["ekl", "FIND Relationship", "--json"])
    relationships = json.loads(rels_txt)
    write_jsonl(out / "relationships.jsonl",
                sorted(relationships, key=lambda row: row.get("id", "")))

    status_txt, _ = r.capture("status", ["status", "--json"])
    (out / "status.json").write_text(status_txt)

    conflicts_txt, _ = r.capture("conflicts", ["conflicts", "list", "--json"])
    (out / "conflicts.json").write_text(conflicts_txt)

    # Sidecar: everything a score line must be able to name (§2.1).
    repo = ekos.parents[3]  # <repo>/ekos/target/release/ekos
    version, _ = r.capture("version", ["--version"])
    sidecar = {
        "panel": f"ledger.{name}",
        "fixture": {"path": str(fixture), "sha256": fixture_sha,
                    "bytes": fixture.stat().st_size},
        "ekos_binary": {"path": str(ekos), "sha256": sha256_file(ekos),
                        "version": version.strip()},
        "ekos": {"repo": str(repo), "commit": git(repo, "rev-parse", "HEAD"),
                 "dirty": bool(git(repo, "status", "--porcelain"))},
        "workspace": str(ws),
        "ekos_home": str(home),
        "ekos_toml": EKOS_TOML,
        "stages_seconds": {k: round(v, 3) for k, v in timings.items()},
        "graph": {"nodes": len(graph["nodes"]), "edges": len(graph["edges"]),
                  "truncated": False,
                  "counts": graph["header"].get("counts"),
                  "kind_index": graph["header"].get("kind_index"),
                  "rel_kind_index": graph["header"].get("rel_kind_index")},
        "ekl": {"objects": len(objects), "relationships": len(relationships)},
        "controls": {f: sha256_file(out / f)
                     for f in CONTROL_FILES if f != "sidecar.json"},
        # Fields in the controls expected to differ between two runs on the
        # same fixture (§3.5-3): never compared fields until proven stable.
        "volatile_fields": {
            "graph.ndjson": ["header.generated_at", "header.workspace",
                             "header.as_of", "node.fs", "edge.fs"],
            "status.json": ["workspace", "last_write", "storage", "freshness"],
            "conflicts.json": [],
            "objects.jsonl": [],
            "relationships.jsonl": [],
        },
        "recorded": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    (out / "sidecar.json").write_text(json.dumps(sidecar, indent=2) + "\n")

    if args.controls_dir:
        cdir = args.controls_dir.resolve()
        cdir.mkdir(parents=True, exist_ok=True)
        for f in CONTROL_FILES:
            shutil.copy2(out / f, cdir / f"ledger.{name}.{f}")
    if args.panel_file:
        upsert_panel(args.panel_file.resolve(), {
            "panel": f"ledger.{name}", "item": name, "origin": "fixture",
            "source": f"{fixture}@sha256:{fixture_sha}",
            "input": {"fixture": str(fixture), "fixture_sha256": fixture_sha},
        })

    print(json.dumps({"panel": sidecar["panel"], "out": str(out),
                      "nodes": sidecar["graph"]["nodes"],
                      "edges": sidecar["graph"]["edges"],
                      "ekl_objects": len(objects),
                      "ekl_relationships": len(relationships),
                      "stages_seconds": sidecar["stages_seconds"],
                      "ekos_commit": sidecar["ekos"]["commit"]}))
    return 0


def flatten(value, prefix: str = "") -> dict[str, object]:
    """Leaf paths -> values, so nested JSON diffs name their field exactly."""
    out: dict[str, object] = {}
    if isinstance(value, dict):
        for k, v in value.items():
            out.update(flatten(v, f"{prefix}.{k}" if prefix else str(k)))
    elif isinstance(value, list):
        for i, v in enumerate(value):
            out.update(flatten(v, f"{prefix}[{i}]"))
    else:
        out[prefix] = value
    return out


def diff_flat(a: dict, b: dict, volatile: set[str]) -> dict:
    """{field: [a, b]} split into volatile and content differences."""
    vol, con = {}, {}
    for k in sorted(set(a) | set(b)):
        va, vb = a.get(k, "<absent>"), b.get(k, "<absent>")
        if va != vb:
            (vol if k in volatile else con)[k] = [va, vb]
    return {"volatile": vol, "content": con}


def diff_rows(a: list[dict], b: list[dict], volatile: set[str]) -> dict:
    """Rows keyed by id: absent ids and per-field differences."""
    da = {row.get("id", "?"): row for row in a}
    db = {row.get("id", "?"): row for row in b}
    only_a = sorted(set(da) - set(db))
    only_b = sorted(set(db) - set(da))
    field_diffs, fs_only = {}, 0
    for k in sorted(set(da) & set(db)):
        d = diff_flat(flatten(da[k]), flatten(db[k]), volatile)
        if d["content"]:
            field_diffs[k] = d["content"]
        if d["volatile"]:
            fs_only += 1
    return {"count_a": len(a), "count_b": len(b), "only_in_a": only_a,
            "only_in_b": only_b, "field_diffs": field_diffs,
            "volatile_only_rows": fs_only}


def diff_edges(ga: dict, gb: dict) -> dict:
    """Edges as a (src id, tgt id, kind name) multiset, indexes mapped per run."""
    def canon(g):
        ids = [n["id"] for n in g["nodes"]]
        kinds = g["header"].get("rel_kind_index") or []
        out = []
        for e in g["edges"]:
            kind = (kinds[e["k"]] if isinstance(kinds, list) and e["k"] < len(kinds)
                    else e["k"])
            out.append((ids[e["s"]], ids[e["t"]], kind))
        return Counter(out)
    ca, cb = canon(ga), canon(gb)
    return {"count_a": sum(ca.values()), "count_b": sum(cb.values()),
            "only_in_a": sorted(list(x) for x in (ca - cb).elements()),
            "only_in_b": sorted(list(x) for x in (cb - ca).elements())}


def cmd_compare(args) -> int:
    a, b = args.a.resolve(), args.b.resolve()
    ga, gb = load_graph(a / "graph.ndjson"), load_graph(b / "graph.ndjson")

    report = {
        "a": str(a), "b": str(b),
        "graph": {
            "header": diff_flat(flatten(ga["header"]), flatten(gb["header"]),
                                VOLATILE_HEADER),
            "nodes": diff_rows(ga["nodes"], gb["nodes"], VOLATILE_NODE_EDGE),
            "edges": diff_edges(ga, gb),
        },
    }
    for what in ("objects", "relationships"):
        ra = [json.loads(ln) for ln in (a / f"{what}.jsonl").read_text().splitlines() if ln.strip()]
        rb = [json.loads(ln) for ln in (b / f"{what}.jsonl").read_text().splitlines() if ln.strip()]
        report[what] = diff_rows(ra, rb, set())

    def load_json(path: Path):
        return flatten(json.loads(path.read_text()))

    def status_volatile():
        fa, fb = load_json(a / "status.json"), load_json(b / "status.json")
        return {k for k in set(fa) | set(fb)
                if k.split(".")[0] in VOLATILE_STATUS_PREFIXES
                or k.split("[")[0] in VOLATILE_STATUS_PREFIXES}
    report["status"] = diff_flat(load_json(a / "status.json"),
                                 load_json(b / "status.json"), status_volatile())
    report["conflicts"] = diff_flat(load_json(a / "conflicts.json"),
                                    load_json(b / "conflicts.json"), set())

    content_bad = []
    if report["graph"]["header"]["content"]:
        content_bad.append("graph.header")
    for part in ("nodes", "edges"):
        d = report["graph"][part]
        if d.get("only_in_a") or d.get("only_in_b") or d.get("field_diffs"):
            content_bad.append(f"graph.{part}")
    for what in ("objects", "relationships"):
        d = report[what]
        if d["only_in_a"] or d["only_in_b"] or d["field_diffs"]:
            content_bad.append(what)
    if report["status"]["content"]:
        content_bad.append("status")
    if report["conflicts"]["content"]:
        content_bad.append("conflicts")
    report["content_identical_modulo_volatile"] = not content_bad
    report["content_differences"] = content_bad

    text = json.dumps(report, indent=2, ensure_ascii=False)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text + "\n")
    print(text)
    return 0 if not content_bad else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("run", help="fixture -> workspace -> pipeline -> controls")
    r.add_argument("--fixture", required=True, type=Path)
    r.add_argument("--out", required=True, type=Path,
                   help="scratch run dir (var/w18/<name>); must be empty/new")
    r.add_argument("--ekos", type=Path,
                   default=Path("/Users/ember/dev/EKOS/ekos/target/release/ekos"))
    r.add_argument("--controls-dir", type=Path, default=None,
                   help="copy the controls + sidecar to <dir>/ledger.<name>.*")
    r.add_argument("--panel-file", type=Path, default=None,
                   help="upsert the fixture's panel item (inputs only)")
    r.set_defaults(fn=cmd_run)

    c = sub.add_parser("compare", help="diff two run dirs field by field")
    c.add_argument("--a", required=True, type=Path)
    c.add_argument("--b", required=True, type=Path)
    c.add_argument("--report", type=Path, default=None)
    c.set_defaults(fn=cmd_compare)

    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
