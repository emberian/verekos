#!/usr/bin/env python3
"""Project the conflicts control to the join view (design §6).

The model's `World.detect` returns (schema, subject, attribute) keys and
nothing else: no conflict ids, no claims, no `chosen`, no signatures, no
surviving objects. EKOS's control (`controls/conflicts.unit.control.jsonl`)
records all of those. This projection keeps only what the model answers, so a
candidate is scored on the join view, and the control file is never edited.

Per control line:

- a line with `same` (a `normalize_type_pair` item) keeps `{"same": ...}`;
- any other line becomes `{"keys": [[subject key, attribute], ...]}`, sorted
  and duplicate-free, plus `permuted_stable` when the control has it. The
  subject key is the panel's own key for the object, recovered from the
  conflict's `subject_id`: EKOS derives every id as UUIDv5 over the URL
  namespace of the key (conflicts.rs:50 `kid`), so the key is found by hashing
  each key the item's input names. A `subject_id` no key hashes to is fatal.
- a line with `error` keeps `{"error": ...}`.

    python3 -I tools/scoreboard/project_conflict_keys.py \\
        --panel panels/conflicts/unit.jsonl \\
        --control controls/conflicts.unit.control.jsonl \\
        --out controls/check/conflicts.unit.keys.control.jsonl

Tests: `python3 -I tools/scoreboard/test_project_conflict_keys.py`.
"""

import argparse
import json
import sys
import uuid
from pathlib import Path


def kid(key: str) -> str:
    """EKOS's private `kid()`: UUIDv5 over the URL namespace."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL, key))


def keys_named(inp: dict) -> list[str]:
    """Every key an item's input names (objects, proposals, enums)."""
    out = []
    for o in inp.get("objects") or []:
        if isinstance(o, dict) and isinstance(o.get("key"), str):
            out.append(o["key"])
    for p in inp.get("proposals") or []:
        if isinstance(p, dict):
            if isinstance(p.get("canonical_key"), str):
                out.append(p["canonical_key"])
            out.extend(k for k in p.get("source_keys") or [] if isinstance(k, str))
    for e in inp.get("enums") or []:
        if isinstance(e, dict) and isinstance(e.get("key"), str):
            out.append(e["key"])
    return out


def project_line(control: dict, inp: dict) -> dict:
    """One control line (with `item`) → its join-view line."""
    item = control["item"]
    if "error" in control:
        return {"item": item, "error": control["error"]}
    if "same" in control:
        return {"item": item, "same": control["same"]}
    by_id = {}
    for k in keys_named(inp):
        by_id.setdefault(kid(k), k)
    pairs = set()
    for c in control.get("conflicts", []):
        sid = c.get("subject_id")
        if sid not in by_id:
            raise ValueError(f"{item}: subject_id {sid} is not the kid() of any key in the input")
        pairs.add((by_id[sid], c["attribute"]))
    out = {"item": item, "keys": [list(p) for p in sorted(pairs)]}
    if "permuted_stable" in control:
        out["permuted_stable"] = control["permuted_stable"]
    return out


def project(panel_lines: list[dict], control_lines: list[dict]) -> list[dict]:
    inputs = {p["item"]: p.get("input", {}) for p in panel_lines}
    out = []
    for c in control_lines:
        if c["item"] not in inputs:
            raise ValueError(f"control item {c['item']} is not in the panel")
        out.append(project_line(c, inputs[c["item"]]))
    return out


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(l) for l in path.read_text().splitlines() if l.strip()]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--panel", required=True, type=Path)
    ap.add_argument("--control", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    a = ap.parse_args()
    try:
        lines = project(read_jsonl(a.panel), read_jsonl(a.control))
    except ValueError as e:
        print(f"project_conflict_keys: {e}", file=sys.stderr)
        return 2
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text("".join(json.dumps(l, sort_keys=True, separators=(",", ":")) + "\n"
                             for l in lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
