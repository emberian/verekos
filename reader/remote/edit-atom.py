#!/usr/bin/env python3 -I
"""reader/remote/edit-atom.py MAPPER_DIR READ.json SRCKEY STRUCTURAL CELL NEWTEXT OUT.json
SCENE ONLY. One `editAtom` request that replaces the payload of the statement atom named by its
structural key with the bytes of NEWTEXT. The mapper's `import` splits a file into one atom per
statement, so it cannot put two statements into one atom; this can."""
import pathlib
import sys

sys.path.insert(0, sys.argv[1])
import mapper as M  # noqa: E402

read, key, structural, cell, new, out = sys.argv[2:8]
src = M.Source(key, read)
aid = src.by_key[structural]
text = pathlib.Path(new).read_text()
act = {"type": "editAtom", "atom": aid, "before": src.doc.before(aid), "kind": M.TEXT, "payload": M.hexs(text), "tombstone": False}
M.write_req(out, M.invoke(cell, [act]))
print(f"1 action(s): editAtom (atom {aid[:12]}…, {structural}, {len(text)} bytes)")
