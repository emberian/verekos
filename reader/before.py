#!/usr/bin/env python3 -I
"""reader/before.py NAME: what links to NAME, one hop and two, and what a rewrite would make stale.

    python3 -I reader/before.py customers

Rings: `ekos ekl "FIND Object FROM 'NAME' DEPTH 1"` and `... DEPTH 2` over the reader's own
ledger (EKOS's walk is undirected; `VIA DependsOn` finds nothing here because foreign keys are
ForeignKey edges, not DependsOn). Control: `ekos query neighbourhood ID --depth 2`, and the
links the compiler wrote into the compiled documents the reader can read. All three are EKOS
(or EKOS's export) on the same copies, so agreement is EKOS against itself.

Stale count, per linked object: how many pins in ITS compiled document, as the reader read it,
name the statement atom of NAME. If that statement were rewritten, exactly those pins would read
`moved`. The plain-text mentions column is a grep of the rendered files, not EKOS.
"""
import argparse
import json
import pathlib
import re
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import lib  # noqa: E402


def ekl_names(ws, name, depth):
    r = lib.ekos(ws, "ekl", f"FIND Object FROM '{name}' DEPTH {depth}", "--json")
    return {x["name"]: x for x in json.loads(r.stdout)}


def neighbourhood(ws, oid, depth):
    txt = lib.ekos(ws, "query", "neighbourhood", oid, "--depth", str(depth)).stdout
    objs = {m.group(1): m.group(2) for m in re.finditer(r"^\s+([0-9a-f-]{36})\s+(\S+) \(\w+\)", txt, re.M)}
    edges = [(m.group(1), m.group(2), m.group(3)) for m in re.finditer(r"^\s+(\w+)\s+([0-9a-f-]{36}) → ([0-9a-f-]{36})", txt, re.M)]
    return objs, edges


def bfs(adj, start):
    dist, via, q = {start: 0}, {}, [start]
    while q:
        x = q.pop(0)
        for y in sorted(adj.get(x, ())):
            if y not in dist:
                dist[y], via[y] = dist[x] + 1, x
                q.append(y)
    return dist, via


def answer(name):
    sync = lib.load_sync()
    ws = lib.ekos_dir(sync)
    d1, d2 = ekl_names(ws, name, 1), ekl_names(ws, name, 2)
    if name not in d2:
        raise SystemExit(f"{name!r}: no object of that name in the ledger of sync {sync['stamp']}")
    root = d2[name]
    ring1 = sorted(set(d1) - {name})
    ring2 = sorted(set(d2) - set(d1))
    objs, edges = neighbourhood(ws, root["id"], 2)
    adj, label = {}, {}
    for kind, s, t in edges:
        sn, tn = objs[s], objs[t]
        adj.setdefault(sn, set()).add(tn)
        adj.setdefault(tn, set()).add(sn)
        label[(sn, tn)] = f"{sn} references {tn} ({kind})"
        label[(tn, sn)] = label[(sn, tn)]
    dist, via = bfs(adj, name)
    control = {"ring1": sorted(n for n, d in dist.items() if d == 1), "ring2": sorted(n for n, d in dist.items() if d == 2)}
    # the links the compiler wrote into the compiled documents the reader can read
    doc2cell = {c["document"]: n for n, c in sync["cells"].items() if c["document"]}
    nadj = {}
    for n, c in sync["cells"].items():
        for t in c["links"]:
            if t in doc2cell:
                nadj.setdefault(n, set()).add(doc2cell[t])
                nadj.setdefault(doc2cell[t], set()).add(n)
    rc = lib.M.table_cell(name)
    ndist, _ = bfs(nadj, rc)
    node_side = {"ring1": sorted(n for n, d in ndist.items() if d == 1), "ring2": sorted(n for n, d in ndist.items() if d == 2)}
    cell_of = {n: lib.M.table_cell(n) for n in d2}
    node_equal = (sorted(cell_of[n] for n in ring1) == node_side["ring1"] and sorted(cell_of[n] for n in ring2) == node_side["ring2"])
    # pins
    members = {}
    for n in [name] + ring1 + ring2:
        o = lib.parse_object(lib.ekos(ws, "query", "object", d2[n]["id"]).stdout)
        members[n] = {"obj": o, "pin": lib.pin_for_object(sync, o | {"name": n})}
    rootpin = members[name]["pin"]
    stale = {}
    for n in members:
        c = sync["cells"].get(cell_of[n])
        stale[n] = [p for p in (c["pins"] if c else []) if rootpin and p["atom"] == rootpin["atom"]]
    already = sum(1 for v in stale.values() for p in v if rootpin and p["rev"] != rootpin["rev"])
    total_stale = sum(len(v) for c in sync["cells"].values() for v in [[p for p in c["pins"] if rootpin and p["atom"] == rootpin["atom"]]])
    readable_targets = {c["target"] for c in sync["cells"].values()}
    blind = sum(1 for c in sync["cells"].values() for p in c["pins"] if p["source"] not in readable_targets)
    mention = re.compile(r"\b" + re.escape(name) + r"\b", re.I)
    mentions = {}
    for rel, f in sync["files"].items():
        text = (pathlib.Path(sync["dir"]) / "ws" / rel).read_text().splitlines()
        for s in f["statements"]:
            body = "\n".join(text[s["lines"][0] - 1:s["lines"][1]])
            if s["key"] != (rootpin or {}).get("stmt") and mention.search(body):
                mentions.setdefault(s["key"], 0)
                mentions[s["key"]] += 1
    return {"sync": sync, "root": name, "ring1": ring1, "ring2": ring2, "control": control, "node_side": node_side,
            "node_equal": node_equal, "members": members, "stale": stale, "total_stale": total_stale,
            "via": via, "label": label, "blind": blind, "already": already, "mentions": mentions, "cell_of": cell_of}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    a = ap.parse_args()
    t0 = time.time()
    r = answer(a.name)
    sync = r["sync"]
    pins = [m["pin"] for m in r["members"].values() if m["pin"]]
    secs, verdicts = lib.recheck(pins, sync)
    vs = iter(verdicts)
    vmap = {n: (next(vs) if m["pin"] else None) for n, m in r["members"].items()}

    def line(n, extra):
        m, v = r["members"][n], vmap[n]
        pin = f"pin: {lib.pin_label(m['pin'])} [{m['pin']['by']}]   {lib.verdict_line(v)}" if m["pin"] else "pin: none"
        s = len(r["stale"][n])
        print(f"    {n:<12}{extra}  {pin}")
        print(f"                 pins in {r['cell_of'][n]} on {a.name}'s statement (stale if it is rewritten): {s}")
        for l in lib.show_moved(v, "                 "):
            print(l)

    print(f"before {a.name!r} (ledger of sync {sync['stamp']}; documents I could read only)")
    print(f"  {a.name}:")
    line(a.name, "")
    print(f"  one hop out ({len(r['ring1'])}), EKOS `FROM '{a.name}' DEPTH 1`:")
    for n in r["ring1"]:
        line(n, f"  {r['label'][(n, a.name)]}")
    print(f"  two hops out ({len(r['ring2'])}), EKOS `FROM '{a.name}' DEPTH 2` minus depth 1:")
    for n in r["ring2"]:
        line(n, f"  via {r['via'][n]}: {r['label'][(n, r['via'][n])]}")
    ms = ", ".join(f"{k} x{v}" for k, v in sorted(r["mentions"].items())) or "none"
    print(f"  if {a.name}'s statement were rewritten: {r['total_stale']} pin(s) in the {len(sync['cells'])} cells I can read would go `moved` ({r['already']} of them already do, against the source as I read it: the compiled document was made from an earlier revision); "
          f"{r['blind']} more pin(s) in those cells point into documents I cannot read, so I cannot check them; "
          f"statements that also mention it in plain text (a grep, not EKOS): {ms}")
    print(f"  control, EKOS vs EKOS on the same copies: `query neighbourhood --depth 2` rings "
          f"{'equal' if r['control'] == {'ring1': r['ring1'], 'ring2': r['ring2']} else 'DIFFER ' + json.dumps(r['control'])}; "
          f"the links the compiler wrote into the compiled documents I can read give rings "
          f"{'equal' if r['node_equal'] else 'DIFFERENT ' + json.dumps(r['node_side'])}")
    print(f"  (pins re-read just now: {len(secs)} cell(s), {len(secs)} signed read(s), {time.time() - t0:.1f} s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
