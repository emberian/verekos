#!/usr/bin/env python3 -I
"""Render the four VerEKOS laws (verekos/laws/L-*.json) with real subject ids.

usage: laws.py LAWDIR OUTDIR owner=S importer=S compiler=S reviewer=S verifier=S
Placeholders (laws/L-*.md): 91001 importer, 91002 owner set, 91003 compiler, 91004 reviewer.
L-run is written twice: L-run-compiler.json (compile-run cells) and L-run-verifier.json
(attestation cells, 91003 replaced by the verifier).
"""
import json, pathlib, sys

def subst(node, table):
    if isinstance(node, dict):
        return {k: subst(v, table) for k, v in node.items()}
    if isinstance(node, list):
        return [subst(v, table) for v in node]
    if isinstance(node, str) and node in table:
        return table[node]
    return node

def main():
    lawdir, outdir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    who = dict(a.split("=", 1) for a in sys.argv[3:])
    base = {"91001": who["importer"], "91002": who["owner"], "91004": who["reviewer"]}
    outdir.mkdir(parents=True, exist_ok=True)
    plan = {"L-src": {"91003": who["compiler"]}, "L-obj": {"91003": who["compiler"]},
            "L-rev": {"91003": who["compiler"]}}
    for name, extra in plan.items():
        law = subst(json.loads((lawdir / f"{name}.json").read_text()), {**base, **extra})
        (outdir / f"{name}.json").write_text(json.dumps(law, sort_keys=True) + "\n")
    run = json.loads((lawdir / "L-run.json").read_text())
    for role in ("compiler", "verifier"):
        law = subst(run, {**base, "91003": who[role]})
        (outdir / f"L-run-{role}.json").write_text(json.dumps(law, sort_keys=True) + "\n")
    for f in sorted(outdir.glob("L-*.json")):
        left = [p for p in ("91001", "91002", "91003", "91004") if p in f.read_text()]
        if left:
            sys.exit(f"{f}: placeholder(s) {left} not substituted")
        print(f"{f.name}\t{f.read_text().strip()}")

if __name__ == "__main__":
    main()
