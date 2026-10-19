#!/usr/bin/env python3 -I
"""reader/edit_as_importer.py FILE [--tag T]: SCENE ONLY. The importer principal rewrites src-shop.

    python3 -I reader/edit_as_importer.py var/lane-a/scene/shop.edit1.sql --tag edit1

This is a WORLD WRITE made by a principal that is not the reader (the reader holds only
observe on the shop room and could not make it). The importer's read and submit run on the
node's machine (remote/importer-edit.sh); the diff runs here with `verekos-map import`, as
slice1/import.sh does (or `verekos-map edit-atom` with --atom-key). FILE is the full new text
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
    remote_out = f"{rd}/edits/{tag}"
    local = lib.ROOT / "var" / "w24" / "reader-edits" / tag
    local.mkdir(parents=True, exist_ok=True)
    script = (lib.HERE / "remote" / "importer-edit.sh").read_bytes()

    def remote(phase):
        args = " ".join(shlex.quote(x) for x in [phase, lib.CONF["mini"], IMPORTER_WS, "src-shop", remote_out, f"reader-{tag}"])
        return lib.ssh(f"bash -s -- {args}", stdin=script, check=False)

    t0 = time.time()
    r = remote("read")
    if r.returncode:
        print(r.stdout.decode().strip(), r.stderr.decode()[-300:])
        return r.returncode
    if lib.subprocess.run(["scp", "-q", f"{lib.CONF['ssh']}:{remote_out}/before.json", str(local / "before.json")]).returncode:
        raise SystemExit("scp failed")
    req = local / "req.json"
    if a.atom_key:
        m = lib.vmap("edit-atom", "--read", local / "before.json", "--source-key", "shop", "--structural", a.atom_key,
                     "--cell", "src-shop", "--file", a.file, "--out", req)
    else:
        m = lib.vmap("import", "--source-key", "shop", "--path", "ecommerce.sql", "--file", a.file, "--cell", "src-shop",
                     "--read", local / "before.json", "--out", req)
    (local / "mapper.txt").write_text(m.stdout)
    if not req.exists():
        print(f"nothing to submit ({m.stdout.strip()})   [{time.time() - t0:.1f} s wall]")
        return 0
    if lib.subprocess.run(["scp", "-q", str(req), str(local / "mapper.txt"), f"{lib.CONF['ssh']}:{remote_out}/"]).returncode:
        raise SystemExit("scp failed")
    r = remote("submit")
    print(r.stdout.decode().strip() + f"   [{time.time() - t0:.1f} s wall]")
    if r.returncode:
        print(r.stderr.decode()[-300:])
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
