#!/usr/bin/env python3 -I
"""reader/sync.py: read everything the reader can read, then compile it here.

    python3 -I reader/sync.py [--force] [--who reader-shop]

As the reader principal: one signed read of every cell the reader's workspace names (a refused
read is a row, not an error); record every atom's (document, atom id, revision); render the
source documents into a scratch folder on this machine; run the unchanged EKOS pipeline there.
Nothing is written to the node: every call is a `mini workspace --action read` (and, when a
previous sync exists, a one-cell probe first).

Re-sync: a read of one small cell tells the reader the world's root (`judgedAt.worldRoot`).
If it is the root the last sync saw, nothing anywhere has changed, so the sync stops after
that one read. If it moved, every cell is read again: the node has no call that returns a
cell's revision without reading the cell (see notes/A-reader-local.md).
"""
import argparse
import json
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import lib  # noqa: E402


def list_refs():
    r = lib.ssh(f"{lib.CONF['mini']} workspace --action list --dir {lib.CONF['reader_workspace']} | jq -r '.references[].name'")
    return r.stdout.decode().split()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="read every cell even if the world root has not moved")
    ap.add_argument("--who", default=lib.CONF["who"])
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    who = a.who
    t_all = time.time()
    st = lib.stamp()
    root = lib.STATE / who / st
    cells_dir = root / "cells"
    prev = None
    try:
        prev = lib.load_sync(who)
    except SystemExit:
        pass
    names = list_refs()
    probe = lib.CONF["probe_cell"]
    rows, reads = [], 0
    if prev and not a.force and probe in names:
        t0 = time.time()
        prow = lib.read_cells([probe], root / "probe", f"{who}-{st}-probe")
        reads += 1
        pj = json.loads((root / "probe" / f"{probe}.json").read_text())["judgedAt"]
        if pj["worldRoot"] == prev["world"]["worldRoot"]:
            msg = (f"sync as {who}: the world has not moved since sync {prev['stamp']} "
                   f"(height {pj['height']}, root {lib.short(pj['worldRoot'], 14)}). {reads} signed read ({time.time() - t0:.1f} s); "
                   f"nothing re-read, nothing recompiled.")
            print(msg)
            (root / "skipped.txt").write_text(msg + "\n")
            return 0
        rows += prow
        (cells_dir).mkdir(parents=True, exist_ok=True)
        (cells_dir / f"{probe}.json").write_text((root / "probe" / f"{probe}.json").read_text())
        names_to_read = [n for n in names if n != probe]
        print(f"sync as {who}: the world moved (height {prev['world']['height']} -> {pj['height']}); reading all {len(names)} cells again "
              f"(the node has no cheaper way to ask which cell changed).")
    else:
        names_to_read = names
    t0 = time.time()
    got = lib.read_cells(names_to_read, cells_dir, f"{who}-{st}")
    reads += len(names_to_read)
    rows += got
    read_secs = sum(r["seconds"] for r in rows)

    cells, unreadable, empty = {}, [], []
    for r in sorted(rows, key=lambda r: r["name"]):
        if r["rc"] != 0:
            unreadable.append({"cell": r["name"], "refusal": r["refusal"]})
            continue
        s = lib.doc_summary(r["name"], cells_dir / f"{r['name']}.json")
        if s["role"] == "empty":
            empty.append(r["name"])
        cells[r["name"]] = s
    docs = {n: c for n, c in cells.items() if c["role"] != "empty"}
    atoms = sum(len(c["atoms"]) for c in docs.values())
    any_cell = next(iter(cells.values()), None)
    world = {"height": any_cell["height"], "worldRoot": any_cell["worldRoot"]} if any_cell else {}

    # render the source documents the reader can read
    ws = root / "ws"
    files, toml = {}, ['[workspace]', 'root = "."', 'log-level = "info"', 'log-format = "pretty"', '',
                       '[observe]', 'paths = ["."]', 'ignore-patterns = [".ekos", ".git", "target", "node_modules"]', '']
    for n, c in sorted(docs.items()):
        if c["role"] != "source":
            continue
        src, hdr = lib.source_of(cells_dir / f"{n}.json")
        rel = f"src/{src.key}/{src.path}"
        out = ws / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(src.text().encode())
        st_list = lib.statements(src)
        files[rel] = {"cell": n, "key": src.key, "path": src.path, "statements": st_list, "digest": lib.file_digest(st_list)}
        toml += ['[[sources]]', f'name = "{src.key}"', f'path = "src/{src.key}"', '']
    (ws / "ekos.toml").write_text("\n".join(toml))

    secs = lib.run_pipeline(ws, root / "ekos")
    nodes, edges = lib.load_export(root / "ekos" / "export.ndjson")
    conflicts = json.loads((root / "ekos" / "conflicts.json").read_text())
    kinds = {}
    for nd in nodes:
        kinds[nd["kind"]] = kinds.get(nd["kind"], 0) + 1

    # does the local compile agree with the compiled cells the reader can read? (EKOS vs the
    # compiler's EKOS run, on the columns of each table; not a check of EKOS itself)
    agree, differ = [], []
    local_cols = {nd["n"]: nd.get("p", {}).get("columns") for nd in nodes if nd["kind"] == "Table"}
    for n, c in docs.items():
        if c["role"] != "compiled":
            continue
        d = lib.M.Doc(cells_dir / f"{n}.json")
        name, props = None, None
        for a_ in d.atoms.values():
            kind = lib.SCHEMAS.get(a_.get("kind", {}).get("schema"))
            if kind == "ekos/header/v1":
                name = json.loads(bytes.fromhex(a_["payload"])).get("name")
            elif kind == "ekos/properties/v1":
                props = json.loads(bytes.fromhex(a_["payload"]))
        if name in local_cols:
            (agree if props and props.get("columns") == local_cols[name] else differ).append(name)

    changed = {}
    if prev:
        for n, c in cells.items():
            old = {x["id"]: x["rev"] for x in prev["cells"].get(n, {}).get("atoms", [])}
            new = {x["id"]: x["rev"] for x in c["atoms"]}
            ed = [i for i in new if i in old and old[i] != new[i]]
            ad = [i for i in new if i not in old]
            rm = [i for i in old if i not in new]
            if ed or ad or rm:
                keymap = {s["atom"]: s["key"] for f in files.values() if f["cell"] == n for s in f["statements"]}
                changed[n] = {"edited": [keymap.get(i, i) for i in ed], "added": [keymap.get(i, i) for i in ad], "removed": len(rm)}
        for n in prev["cells"]:
            if n not in cells:
                changed.setdefault(n, {"edited": [], "added": [], "removed": "cell now unreadable"})

    summary = {
        "who": who, "stamp": st, "world": world, "reads": reads, "read_seconds": round(read_secs, 1),
        "wall_seconds": round(time.time() - t_all, 1), "rows": rows, "cells": cells, "unreadable": unreadable,
        "empty": empty, "files": files, "documents": len(docs), "atoms": atoms,
        "objects": len(nodes), "kinds": kinds, "edges": len(edges), "conflicts": len(conflicts),
        "ekos_seconds": secs, "ekos_version": (root / "ekos" / "ekos-version.txt").read_text().strip(),
        "crosscheck": {"agree": sorted(agree), "differ": sorted(differ)},
        "changed_since": {"stamp": prev["stamp"] if prev else None, "cells": changed},
    }
    (root / "sync.json").write_text(json.dumps(summary, indent=1))
    (lib.STATE / who / "LATEST").write_text(st + "\n")

    if not a.quiet:
        for r in sorted(rows, key=lambda r: r["name"]):
            if r["rc"] == 0:
                c = cells[r["name"]]
                what = {"source": "source document", "compiled": "compiled document", "empty": "readable, no document in it"}[c["role"]]
                print(f"  read     {r['name']:<38} {len(c['atoms']):>3} atoms  {what}  ({r['seconds']:.1f} s)")
            else:
                print(f"  refused  {r['name']:<38} {r['refusal'][:110]}")
        if changed:
            print(f"  changed since sync {prev['stamp']}:")
            for n, ch in changed.items():
                print(f"    {n}: edited {ch['edited']} added {ch['added']} removed {ch['removed']}")
        print(f"  local compile: {kinds.get('Table', 0)} tables, {len(edges)} foreign keys, {len(conflicts)} conflicts "
              f"({summary['ekos_version']}; pipeline {sum(secs.values()):.1f} s)")
        if agree or differ:
            print(f"  against the compiled documents I can read: columns agree on {len(agree)} of {len(agree) + len(differ)} tables"
                  + (f" (differ: {', '.join(differ)})" if differ else ""))
    print(f"{len(docs)} documents, {atoms} atoms, {len(nodes)} objects, {len(unreadable)} I could not read."
          f"  [{reads} signed reads, {summary['wall_seconds']} s; nothing was written to the node]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
