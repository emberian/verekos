#!/usr/bin/env python3 -I
"""reader/scene.py: the scene of exploration 04 §4, replayed against the real slice-1 world.

    python3 -I reader/scene.py OUTDIR

Runs, in order, every step as a child process with its own command line, and saves each command
line, output and wall time in OUTDIR/NN-name.txt plus one row per receipt in OUTDIR/receipts.tsv.
The reader's state goes to OUTDIR/state (a fresh folder, so the first sync has no past).

It makes three WORLD WRITES as the importer principal, not the reader: an edit of one shop
statement, the addition of a second `customers` statement to the shop file, and a restore of the
original text. Needs the slice-1 server (run-2) to be running on the node's machine.
"""
import json
import os
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = pathlib.Path(sys.argv[1]).resolve()
SCENE_FILES = ROOT / "var" / "lane-a" / "scene"
STATE = OUT / "state"
OUT.mkdir(parents=True, exist_ok=True)
ENV = dict(os.environ, VEREKOS_READER_STATE=str(STATE))
n = [0]
RECEIPTS = OUT / "receipts.tsv"
RECEIPTS.write_text("")


def run(name, *argv, py=True):
    n[0] += 1
    cmd = (["python3", "-I"] if py else []) + [str(a) for a in argv]
    t0 = time.time()
    r = subprocess.run(cmd, capture_output=True, text=True, env=ENV, cwd=ROOT)
    secs = time.time() - t0
    shown = " ".join(["python3 -I"] + [pathlib.Path(a).name if str(a).startswith("/") and i == 0 else str(a) for i, a in enumerate(argv)]).replace(str(ROOT) + "/", "")
    (OUT / f"{n[0]:02d}-{name}.txt").write_text(f"$ {shown}\n(exit {r.returncode}, {secs:.1f} s)\n{r.stdout}{r.stderr}")
    print(f"{n[0]:02d} {name}: exit {r.returncode}, {secs:.1f} s")
    return r.stdout + r.stderr, secs, r.returncode


def row(step, name, expect, got, secs, detail=""):
    ok = "OK" if expect == got or (expect.endswith("*") and got.startswith(expect[:-1])) or (expect.startswith(">=") and got.isdigit() and int(got) >= int(expect[2:])) else "DIFFERS"
    detail = " ".join(detail.split())
    with RECEIPTS.open("a") as f:
        f.write(f"{step}\t{name}\texpect={expect}\tgot={got}\t{secs:.1f}s\t{ok}\t{detail[:500]}\n")
    print(f"   {step} {name}: expect={expect} got={got} [{ok}]")


def last_sync():
    d = STATE / "reader-shop"
    s = json.loads((d / (d / "LATEST").read_text().strip() / "sync.json").read_text())
    return s


R = HERE
o, secs, _ = run("sync", R / "sync.py")
s1 = last_sync()
rd = {r["name"]: r for r in s1["rows"]}
row("A1", "reader-shop reads src-shop; src-legacy refused by the host",
    "src-shop read; src-legacy refused: no-grant*",
    f"src-shop {'read' if rd['src-shop']['rc'] == 0 else 'NOT read'}; src-legacy {rd['src-legacy']['refusal'][:70]}", secs, rd["src-legacy"]["refusal"])
w17 = json.loads((ROOT / "var/w17/run-2/compile-1/ekos/conflicts.json").read_text())
row("A2", "local compile: 6 tables, 0 conflicts (the compiler's slice-1 compile of the same world has %d)" % len(w17),
    "6 tables, 0 conflicts", f"{s1['kinds'].get('Table', 0)} tables, {s1['conflicts']} conflicts", secs,
    f"documents {s1['documents']}, atoms {s1['atoms']}, objects {s1['objects']}, unreadable {len(s1['unreadable'])}, columns agree with compiled cells on {len(s1['crosscheck']['agree'])}/{len(s1['crosscheck']['agree']) + len(s1['crosscheck']['differ'])}")
o, secs, _ = run("find", R / "find.py", "customers")
row("A3", "find customers: the customers hit re-checks", "same bytes", "same bytes" if "customers (Table)" in o and "same bytes" in o.split("customers (Table)")[1].splitlines()[0] else "other", secs, o.splitlines()[1] if len(o.splitlines()) > 1 else "")
o, secs, _ = run("before", R / "before.py", "customers")
eq = "rings equal" if ("`query neighbourhood --depth 2` rings equal" in o and "give rings equal" in o) else "differ"
row("A5", "before customers: two hops equal EKOS's own neighbourhood (EKOS vs EKOS) and the node's links", "equal", "equal" if eq == "rings equal" else "differ", secs,
    next((l.strip() for l in o.splitlines() if "if customers" in l), ""))
o, secs, _ = run("disagree", R / "disagree.py")
d0 = "0" if "among the documents I can read: 0" in o else "other"
row("A6", "disagree: the reader sees only the shop side, so 0 disagreements, and says what it cannot see", "0 + named-source note",
    "0 + named-source note" if d0 == "0" and "a second definition I cannot compare" in o else "other", secs)
o, secs, _ = run("sync-unchanged", R / "sync.py")
row("A4a", "re-sync with nothing changed: one probe read, nothing re-read", "1 signed read", "1 signed read" if " 1 signed read" in o else "other", secs, o.strip()[:200])
o, secs, rc = run("edit1-importer", R / "edit_as_importer.py", SCENE_FILES / "shop.edit1.sql", "--tag", "edit1")
row("A4b", "importer edits one shop statement (email VARCHAR(255) -> VARCHAR(320)) -- a world write", "submitted rc=0*", o.strip()[:60], secs, o.strip())
o, secs, _ = run("find-after-edit", R / "find.py", "customers")
l = next((x for x in o.splitlines() if "customers (Table)" in x), "")
row("A4c", "the same find, local ledger not re-synced: the customers pin re-checks `moved`, the file pin too", "moved",
    "moved" if "moved" in l and "same bytes" not in l else "other", secs, l.strip()[:300])
o, secs, _ = run("before-after-edit", R / "before.py", "customers")
o, secs, _ = run("sync-after-edit", R / "sync.py")
s2 = last_sync()
row("A4d", "re-sync after the edit: reads every cell again (the node cannot say which one changed)", f"{len(s1['rows'])} signed reads", f"{s2['reads']} signed reads", secs,
    json.dumps(s2["changed_since"]["cells"]))
o, secs, _ = run("find-resynced", R / "find.py", "customers")
row("A4e", "after re-sync the customers pin is the new revision and re-checks", "same bytes", "same bytes" if "moved" not in o else "other", secs)
o, secs, _ = run("disagree-resynced", R / "disagree.py")
row("A6b", "disagree after the one-statement edit: still 0 (the reader never had the legacy side)", "0", "0" if "among the documents I can read: 0" in o else "other", secs)
o, secs, rc = run("edit2-importer", R / "edit_as_importer.py", SCENE_FILES / "customers.edit2.atom.sql", "--tag", "edit2", "--atom-key", "create-table:customers#0")
row("A6c", "importer adds a second customers definition inside the customers statement atom (one editAtom) -- a world write", "submitted rc=0*", o.strip()[:60], secs, o.strip())
o, secs, _ = run("sync-after-edit2", R / "sync.py")
o, secs, _ = run("disagree-after-edit2", R / "disagree.py")
s3 = last_sync()
row("A6d", "the disagreement list changes: the two shop definitions now disagree", ">=1", str(s3["conflicts"]), secs, o[:500])
o, secs, rc = run("restore-importer", R / "edit_as_importer.py", SCENE_FILES / "shop.orig.sql", "--tag", "restore")
row("A6e", "importer restores the original shop text -- a world write", "submitted rc=0*", o.strip()[:60], secs, o.strip())
o, secs, _ = run("sync-after-restore", R / "sync.py")
o, secs, _ = run("disagree-after-restore", R / "disagree.py")
s4 = last_sync()
row("A6f", "after the restore the list is empty again", "0", str(s4["conflicts"]), secs)
o, secs, rc = run("leakcheck", R / "leakcheck.py")
row("A7", "nothing from src-legacy on this machine (canary scan, planted control, EKOS queries)", "PASS", "PASS" if rc == 0 else "FAIL", secs, o.splitlines()[-1] if o.strip() else "")
print("done; receipts:", RECEIPTS)
