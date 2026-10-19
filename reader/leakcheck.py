#!/usr/bin/env python3 -I
"""reader/leakcheck.py: nothing from a document the reader cannot read is on this machine.

    python3 -I reader/leakcheck.py [--plant DIR]

Canaries are strings that occur in the legacy source (the reader's refused document) and in no
shop document: the table text of slice1's two legacy fixtures. Three checks, each with a
positive control so a zero means something:
  1. a byte scan of everything under the reader's state folder (reads, renders, EKOS ledger,
     exports, outputs), for each canary in plain text and hex (the node's views carry payloads as hex);
  2. the same scan over a PLANTED folder that holds the legacy fixture (must find every canary);
  3. EKOS queries for a legacy-only name over the reader's ledger (must find nothing) and over a
     scratch ledger built from the legacy fixture alone (must find it).
Byte scanning cannot see inside compressed ledger segments, which is why check 3 exists.
"""
import argparse
import json
import pathlib
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import lib  # noqa: E402

FIX = [lib.ROOT / "slice1" / "fixtures" / "legacy_customers.sql", lib.ROOT / "slice1" / "inputs" / "legacy_customers.v2.sql"]
CANARIES = ["CITEXT", "email  TEXT", "id     INT PRIMARY KEY"]


def scan(folder):
    hits = {c: 0 for c in CANARIES}
    n = 0
    for p in pathlib.Path(folder).rglob("*"):
        if not p.is_file():
            continue
        n += 1
        b = p.read_bytes()
        for c in CANARIES:
            if c.encode() in b or c.encode().hex().encode() in b:
                hits[c] += 1
    return n, hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--who", default=lib.CONF["who"])
    a = ap.parse_args()
    shop = (lib.ROOT / "slice1" / "inputs" / "ecommerce.sql").read_text()
    for c in CANARIES:
        assert c not in shop, f"canary {c!r} also occurs in the shop document; pick another"
    for f in FIX:
        t = f.read_text()
        assert "CITEXT" in t or "email  TEXT" in t, f
    ok = True
    n, hits = scan(lib.STATE / a.who)
    print(f"1. scan of {lib.STATE / a.who}: {n} files, canary hits {json.dumps(hits)}")
    ok &= sum(hits.values()) == 0
    with tempfile.TemporaryDirectory(prefix="plant-", dir=lib.STATE.parent) as plant:
        for f in FIX:
            (pathlib.Path(plant) / f.name).write_bytes(f.read_bytes())
        (pathlib.Path(plant) / "hexed.json").write_text(json.dumps({"payload": FIX[1].read_bytes().hex()}))
        pn, ph = scan(plant)
    print(f"2. positive control, a planted folder of {pn} files holding the legacy fixtures: canary hits {json.dumps(ph)}")
    ok &= all(v > 0 for v in ph.values())
    sync = lib.load_sync(a.who)
    ws = lib.ekos_dir(sync)
    # `find` matches loosely ("legacy_customers" also finds `customers`), so count only hits named for the legacy file
    legacy_named = lambda hs: [h["name"] for h in hs if "legacy" in h["name"].lower()]
    mine = legacy_named(lib.parse_find(lib.ekos(ws, "query", "find", "legacy_customers").stdout))
    mine2 = lib.parse_find(lib.ekos(ws, "query", "find", "CITEXT").stdout)
    with tempfile.TemporaryDirectory(prefix="plant-ws-", dir=lib.STATE.parent) as pw:
        w = pathlib.Path(pw)
        (w / "src" / "legacy").mkdir(parents=True)
        (w / "src" / "legacy" / "legacy_customers.sql").write_bytes(FIX[1].read_bytes())
        (w / "ekos.toml").write_text('[workspace]\nroot = "."\n[observe]\npaths = ["."]\nignore-patterns = [".ekos"]\n\n[[sources]]\nname = "legacy"\npath = "src/legacy"\n')
        lib.run_pipeline(w, w / "out")
        theirs = legacy_named(lib.parse_find(lib.ekos(w, "query", "find", "legacy_customers").stdout))
    print(f"3. `ekos query find legacy_customers` (hits named for the legacy file) / `CITEXT` on the reader's ledger: {len(mine)} / {len(mine2)}; "
          f"on a scratch ledger built from the legacy fixture alone: {len(theirs)} ({', '.join(theirs)})")
    ok &= not mine and not mine2 and len(theirs) >= 1
    print("leakcheck: " + ("PASS (the controls fire, the reader's side is clean)" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
