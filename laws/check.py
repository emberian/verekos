#!/usr/bin/env python3 -I
"""Check the four VerEKOS law drafts against minidregg's real Pred JSON spelling and slot names.

Constructor names and field names are those the client serializer emits
(/Users/ember/dev/minidregg/native/resource-client/src/shell/law.rs lines 211-430).
Content slots are the ones ContentResource.project writes
(/Users/ember/dev/minidregg/Kernel/ContentResource.lean lines 1788-1819); request slots are
ObjectRecord.Facts.slots (/Users/ember/dev/minidregg/Kernel/ObjectRecord.lean lines 449-455)
plus request/verb, which the shell's own templates test (shell.rs lines 142-162).
Values are strings in the client JSON ("value": "0"), as law.rs:439 shows.
"""
import json, sys, pathlib

CONSTRUCTORS = {
    "eq": {"slot", "value"}, "le": {"slot", "value"}, "memberOf": {"slot", "values"},
    "writeOnce": {"slot"}, "monotone": {"slot"},
    "eqSlots": {"left", "right"}, "leSlots": {"left", "right"}, "leSlotsOff": {"left", "right", "offset"},
    "hashEq": {"values", "blinder", "commit"}, "ran": {"program"},
    "not": {"predicate"}, "all": {"predicates"}, "any": {"predicates"},
}
CONTENT_SLOTS = {
    "content/names/unique", "content/bytes/before", "content/bytes/after", "content/bytes/delta",
    "content/entries/before", "content/entries/after", "content/operations",
    "content/payload-bytes/before", "content/payload-bytes/after",
    "content/document-creates", "content/atom-creates", "content/atom-edits", "content/links",
    "content/run-creates", "content/annotations", "content/transclusions", "content/element-edits",
    "content/container-creates", "content/unlinks", "content/marks", "content/unmarks",
    "content/run-inserts", "content/writes/body", "content/writes/annotations", "content/tombstones",
    "content/atoms/high-min", "content/atoms/high-max", "content/atoms/low-min", "content/atoms/low-max",
}
REQUEST_SLOTS = {"request/subject", "request/height", "request/target", "request/turn", "request/caller", "request/verb"}
SLOTS = CONTENT_SLOTS | REQUEST_SLOTS
VERBS = {"1", "2", "3", "4", "5"}  # observe, mutate, delegate, installPolicy, revoke (shell templates)

def walk(p, path, errs, stats):
    t = p.get("type")
    if t not in CONSTRUCTORS:
        errs.append(f"{path}: unknown constructor {t!r}"); return
    stats[t] = stats.get(t, 0) + 1
    extra = set(p) - CONSTRUCTORS[t] - {"type"}
    missing = CONSTRUCTORS[t] - set(p)
    if extra: errs.append(f"{path}: unexpected fields {sorted(extra)} on {t}")
    if missing: errs.append(f"{path}: missing fields {sorted(missing)} on {t}")
    for k in ("slot", "left", "right"):
        if k in p and p[k] not in SLOTS:
            errs.append(f"{path}: slot {p[k]!r} is not a projected slot")
    if "value" in p and not isinstance(p["value"], str):
        errs.append(f"{path}: value must be a string, got {type(p['value']).__name__}")
    if "values" in p and t == "memberOf" and not all(isinstance(v, str) for v in p["values"]):
        errs.append(f"{path}: memberOf values must be strings")
    if p.get("slot") == "request/verb":
        vals = {p["value"]} if "value" in p else set(p.get("values", []))
        bad = vals - VERBS
        if bad: errs.append(f"{path}: verb codes {sorted(bad)} outside 1-5")
    if t == "not": walk(p["predicate"], path + "/not", errs, stats)
    for i, c in enumerate(p.get("predicates", [])): walk(c, f"{path}/{t}[{i}]", errs, stats)

def main():
    here = pathlib.Path(__file__).resolve().parent
    ok = True
    print(f"{'law':8} {'nodes':>5} {'errors':>6}  constructors")
    for f in sorted(here.glob("L-*.json")):
        errs, stats = [], {}
        walk(json.loads(f.read_text()), f.stem, errs, stats)
        print(f"{f.stem:8} {sum(stats.values()):5} {len(errs):6}  {', '.join(f'{k}:{v}' for k, v in sorted(stats.items()))}")
        for e in errs: print("   ", e); ok = False
    sys.exit(0 if ok else 1)

if __name__ == "__main__": main()
