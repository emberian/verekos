#!/usr/bin/env python3 -I
"""reader/disagree.py: where the documents the reader can read disagree, and what it cannot see.

    python3 -I reader/disagree.py

Disagreements are `ekos conflicts list --json` over the reader's own ledger. A conflict's claims
carry a path and a value, no line (EKOS evidence names the file), so each claim's pin is a GUESS:
the subject table's statement(s) in that file; when a file holds several, every candidate is listed.

It also says what it cannot see. A zero from a reader who was refused a document is not "no
disagreement"; and a compiled document the reader CAN read may name a source the reader cannot.
That second part reads the compiled documents' own header atoms, pinned like any other answer.
"""
import json
import pathlib
import re
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import lib  # noqa: E402


def claim_pins(sync, conflict, claim):
    f = sync["files"].get(claim["path"])
    if not f:
        return [], "no such file in the ledger"
    base = f"create-table:{conflict['subject']['name'].lower()}#"
    cands = [s for s in f["statements"] if s["key"].startswith(base)]
    col = conflict["attribute"].split(".")[1] if conflict["attribute"].count(".") >= 1 and conflict["attribute"].startswith("columns.") else None
    text = (pathlib.Path(sync["dir"]) / "ws" / claim["path"]).read_text().splitlines()
    if len(cands) > 1 and col:
        val = str(claim["value"]).lower()
        hit = []
        for s in cands:
            body = "\n".join(text[s["lines"][0] - 1:s["lines"][1]]).lower()
            if any(col in ln and val.split("(")[0] in ln for ln in body.splitlines()):
                hit.append(s)
        if len(hit) == 1:
            cands, why = hit, "matched by the value in the statement text"
        else:
            why = f"ambiguous: {len(cands)} statements define it in this file"
    else:
        why = lib.GUESS
    pins = [{"kind": "atom", "cell": f["cell"], "atom": s["atom"], "rev": s["rev"], "sha": s["sha"], "file": claim["path"],
             "stmt": s["key"], "lines": s["lines"], "by": why} for s in cands]
    return pins, why


def named_sources(sync):
    """Compiled documents that name a source the reader has no document for."""
    have = {f["key"] for f in sync["files"].values()}
    out = []
    for n, c in sorted(sync["cells"].items()):
        if c["role"] != "compiled":
            continue
        d = lib.M.Doc(pathlib.Path(sync["dir"]) / "cells" / f"{n}.json")
        for aid, a in d.atoms.items():
            if lib.SCHEMAS.get(a.get("kind", {}).get("schema")) == "ekos/header/v1" and a.get("tombstonedAt") in (None, "null"):
                h = json.loads(bytes.fromhex(a["payload"]))
                missing = [s for s in h.get("sources", []) if s not in have]
                if missing:
                    out.append({"cell": n, "name": h.get("name"), "sources": h.get("sources"), "missing": missing,
                                "pin": lib.cell_atom_pin(sync, n, aid)})
    return out


def main():
    t0 = time.time()
    sync = lib.load_sync()
    ws = lib.ekos_dir(sync)
    conflicts = json.loads(lib.ekos(ws, "conflicts", "list", "--json").stdout)
    ns = named_sources(sync)
    items = []
    for c in conflicts:
        items.append((c, [(cl, *claim_pins(sync, c, cl)) for cl in c["claims"]]))
    pins = [p for _, cls in items for _, ps, _ in cls for p in ps] + [x["pin"] for x in ns if x["pin"]]
    secs, verdicts = lib.recheck(pins, sync)
    vs = iter(verdicts)
    print(f"disagree (ledger of sync {sync['stamp']}; {sync['documents']} documents I could read, {len(sync['unreadable'])} I could not)")
    print(f"  disagreements among the documents I can read: {len(conflicts)}")
    for c, cls in items:
        print(f"  - {c['name']}: {c['conflict_type']}, {c['status']}; EKOS does not say which is right (it picked {c['chosen_by_ekos']!r} by input order)")
        for cl, ps, why in cls:
            print(f"      says {cl['value']!r} in {cl['path']}:")
            for p in ps:
                v = next(vs)
                print(f"        pin: {lib.pin_label(p)} lines {p['lines'][0]}-{p['lines'][1]} [{p['by']}]   {lib.verdict_line(v)}")
                for l in lib.show_moved(v, "          "):
                    print(l)
    if sync["unreadable"]:
        print("  what this count cannot mean: I was refused " + ", ".join(u["cell"] for u in sync["unreadable"]) +
              f" ({sync['unreadable'][0]['refusal'][:70]}). A zero over what I can read is not a zero over the world.")
    for x in ns:
        v = next(vs)
        print(f"  a second definition I cannot compare: {x['cell']} says {x['name']!r} is defined in {' and '.join(x['sources'])}; "
              f"I can read {' and '.join(sorted(set(x['sources']) - set(x['missing'])))} only. I do not know whether they disagree.")
        print(f"      pin: {lib.pin_label(x['pin'])} [{x['pin']['by']}]   {lib.verdict_line(v)}")
    print(f"  (pins re-read just now: {len(secs)} cell(s), {len(secs)} signed read(s), {time.time() - t0:.1f} s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
