#!/usr/bin/env python3 -I
"""reader/find.py TEXT: search the reader's own ledger; every hit ends in a pin that is re-read now.

    python3 -I reader/find.py customers [--mode lexical|hybrid|vector]

The hits are `ekos query find` over the ledger sync.py built (so only documents the reader could
read). Each hit's pin is (cell, atom, revision) at sync time, found from EKOS's evidence by a
GUESS (structural key; EKOS evidence names the file only). Before printing, the cited cells are
read again by the reader and each pin is `same bytes` or `moved`.
"""
import argparse
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import lib  # noqa: E402


def answer(text, mode="lexical"):
    sync = lib.load_sync()
    ws = lib.ekos_dir(sync)
    r = lib.ekos(ws, "query", "find", text, "--mode", mode)
    hits = lib.parse_find(r.stdout)
    for h in hits:
        o = lib.parse_object(lib.ekos(ws, "query", "object", h["id"]).stdout)
        h.update(o)
        h["pin"] = lib.pin_for_object(sync, o | {"name": h["name"]})
    return sync, hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("text")
    ap.add_argument("--mode", default="lexical")
    a = ap.parse_args()
    t0 = time.time()
    sync, hits = answer(a.text, a.mode)
    pins = [h["pin"] for h in hits if h["pin"]]
    secs, verdicts = lib.recheck(pins, sync)
    vs = iter(verdicts)
    print(f"find {a.text!r}: {len(hits)} hit(s) in the ledger of sync {sync['stamp']} (documents I could read only)")
    for i, h in enumerate(hits, 1):
        if not h["pin"]:
            print(f"  {i}. {h['name']} ({h['kind']})   pin: none (EKOS gave no evidence I can place)")
            continue
        v = next(vs)
        print(f"  {i}. {h['name']} ({h['kind']})   pin: {lib.pin_label(h['pin'])} [{h['pin']['by']}]   {lib.verdict_line(v)}")
        for l in lib.show_moved(v):
            print(l)
    print(f"  (pins re-read just now: {len(secs)} cell(s), {len(secs)} signed read(s), {time.time() - t0:.1f} s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
