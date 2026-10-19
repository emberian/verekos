#!/usr/bin/env python3 -I
"""reader/edit_as_importer.py FILE [--tag T]: SCENE ONLY. The importer principal rewrites src-shop.

    python3 -I reader/edit_as_importer.py var/lane-a/scene/shop.edit1.sql --tag edit1

This is a WORLD WRITE made by a principal that is not the reader (the reader holds only
observe on the shop room and could not make it). It runs slice 1's mapper `import` (vendored in
reader/vendor/) on the node's machine, as slice1/s-import.sh does. FILE is the full new text
of ecommerce.sql; only the statements that differ are submitted.
"""
import argparse
import pathlib
import shlex
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import lib  # noqa: E402

IMPORTER_WS = "/home/hbox/verekos-runs/slice1/run-2/world/importer-workspace"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--tag", default="edit")
    ap.add_argument("--atom-key", help="FILE is the new text of this one statement atom (e.g. create-table:customers#0), not the whole file")
    a = ap.parse_args()
    rd = lib.CONF["remote_dir"]
    tag = f"{a.tag}-{lib.stamp()}"
    lib.ssh(f"mkdir -p {rd}/code/vendor {rd}/edits")
    for local, remote in ((lib.HERE / "vendor" / "mapper.py", f"{rd}/code/vendor/mapper.py"),
                          (lib.HERE / "remote" / "edit-atom.py", f"{rd}/code/edit-atom.py"), (pathlib.Path(a.file), f"{rd}/edits/{tag}.sql")):
        r = lib.subprocess.run(["scp", "-q", str(local), f"{lib.CONF['ssh']}:{remote}"])
        if r.returncode:
            raise SystemExit("scp failed")
    args = " ".join(shlex.quote(x) for x in [lib.CONF["mini"], IMPORTER_WS, "src-shop", "shop", "ecommerce.sql",
                                              f"{rd}/edits/{tag}.sql", f"{rd}/code/vendor/mapper.py", f"{rd}/edits/{tag}", f"reader-{tag}"])
    t0 = time.time()
    env = f"ATOM_KEY={shlex.quote(a.atom_key)} " if a.atom_key else ""
    r = lib.ssh(f"{env}bash -s -- {args}", stdin=(lib.HERE / "remote" / "importer-edit.sh").read_bytes(), check=False)
    print(r.stdout.decode().strip() + f"   [{time.time() - t0:.1f} s wall]")
    if r.returncode:
        print(r.stderr.decode()[-300:])
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
