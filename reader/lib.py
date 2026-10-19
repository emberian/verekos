"""reader/lib.py: what sync.py, find.py, before.py and disagree.py share.

Stdlib only; run the scripts with `python3 -I`. Everything here is UNTRUSTED in the VerEKOS
sense: the structural-key pin is a guess (EKOS evidence names the file, not a statement), and
EKOS's own output is the thing being relayed, not checked.

The reader's reads are signed `mini workspace --action read` calls made as the reader
principal. The reader's key is a file on the node's machine, so the reads run there over ssh
(the same way slice 1's scripts do); nothing is submitted by anything in this file.
"""
import hashlib
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE / "vendor"))
import mapper as M  # noqa: E402  W17's mapper, copied unchanged (vendor/VENDORED.txt)

CONF = json.loads((HERE / "reader.conf.json").read_text())
for _k in ("ssh", "ekos", "who", "reader_workspace", "remote_dir"):
    if os.environ.get("VEREKOS_READER_" + _k.upper()):
        CONF[_k] = os.environ["VEREKOS_READER_" + _k.upper()]
STATE = pathlib.Path(os.environ.get("VEREKOS_READER_STATE", ROOT / "var" / "lane-a" / "reader"))

GUESS = "guess: structural key"   # said on every pin line: EKOS evidence names the file only
PROPS = ["columns", "check_constraints", "indexes", "description", "source", "sources", "signature",
         "claims", "subject_id", "attribute", "status", "subject_kind", "conflict_type", "chosen",
         "subject_name"]
SCHEMAS = {M.schema(n): n for n in ("ekos/object/v1", "ekos/header/v1", "ekos/properties/v1", "ekos/edge/v1",
                                    "ekos/evidence-meta/v1", "ekos/source-header/v1", "ekos/conflict/v1",
                                    "ekos/conflict-header/v1", "ekos/claim/v1", "ekos/manifest/v1")}


def stamp():
    return time.strftime("%Y%m%dT%H%M%S")


def sha(b):
    return hashlib.sha256(b).hexdigest()


def short(n, k=10):
    n = str(n)
    return n if len(n) <= k + 1 else n[:k] + "…"


# ------------------------------------------------------------------ the node, over ssh


def ssh(cmd, stdin=None, check=True):
    r = subprocess.run(["ssh", CONF["ssh"], cmd], input=stdin, capture_output=True)
    if check and r.returncode != 0:
        raise SystemExit(f"ssh {CONF['ssh']} failed ({r.returncode}): {r.stderr.decode()[:400]}")
    return r


def read_cells(names, out_dir, tag):
    """Signed reads as the reader, one per name (`@all` = every reference the reader's
    workspace names). Returns the rows of reads.tsv and leaves NAME.json / NAME.refused.txt in
    out_dir. Costs len(names) signed reads on the node and one ssh round trip plus one tar."""
    out_dir = pathlib.Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    remote = f"{CONF['remote_dir']}/{tag}"
    args = " ".join(shlex.quote(a) for a in [CONF["mini"], CONF["reader_workspace"], remote] + list(names))
    ssh(f"bash -s -- {args}", stdin=(HERE / "remote" / "read-cells.sh").read_bytes())
    tarred = subprocess.run(["ssh", CONF["ssh"], f"tar cf - -C {shlex.quote(remote)} ."], capture_output=True)
    if tarred.returncode != 0:
        raise SystemExit("could not fetch the reads back: " + tarred.stderr.decode()[:300])
    subprocess.run(["tar", "xf", "-", "-C", str(out_dir)], input=tarred.stdout, check=True)
    rows = []
    for line in (out_dir / "reads.tsv").read_text().splitlines():
        n, rc, secs, size, why = (line.split("\t") + [""] * 5)[:5]
        rows.append({"name": n, "rc": int(rc), "seconds": float(secs), "bytes": int(size), "refusal": why})
    return rows


# ------------------------------------------------------------------ a read, as the reader sees it


def doc_summary(name, path):
    """Atoms, links and transclusion pins of one read cell. `role`: source / compiled / empty."""
    view = json.loads(pathlib.Path(path).read_text())
    d = M.Doc(path)
    judged = view.get("judgedAt", {})
    out = {"cell": name, "target": d.target, "height": judged.get("height"), "worldRoot": judged.get("worldRoot"),
           "document": (d.document or {}).get("id"), "atoms": [], "links": [], "pins": [], "role": "empty"}
    for aid, a in d.atoms.items():
        if a.get("tombstonedAt") not in (None, "null"):
            continue
        k = a.get("kind", {})
        kind = "text" if k.get("type") == "text" else SCHEMAS.get(k.get("schema"), "inline:" + str(k.get("schema")))
        out["atoms"].append({"id": aid, "rev": str(a["revision"]), "kind": kind, "sha": sha(bytes.fromhex(a["payload"]))})
    for l in d.links.values():
        t = l.get("target") or {}
        if l.get("tombstonedAt") in (None, "null") and t.get("type") == "document":
            out["links"].append(str(t["id"]))
    for t in d.transclusions.values():
        op = t.get("opening") or {}
        for p in op.get("pins", []):
            out["pins"].append({"atom": str(p["atom"]), "rev": str(p["revision"]), "source": str(op.get("source"))})
    kinds = {a["kind"] for a in out["atoms"]}
    if "ekos/source-header/v1" in kinds:
        out["role"] = "source"
    elif kinds:
        out["role"] = "compiled"
    return out


def source_of(path):
    """(Source, header) when the read cell is an imported source document, else None."""
    d = M.Doc(path)
    try:
        hdr = M.source_header(d)
    except SystemExit:
        return None
    return M.Source(hdr["source_key"], path), hdr


def statements(src):
    """Per statement of a source in run order: structural key, atom, revision, payload sha, lines."""
    out, line = [], 1
    for skey, aid in src.order:
        data = src.doc.payload(aid)
        n = data.decode().count("\n") or 1
        out.append({"key": skey, "atom": aid, "rev": src.doc.revision(aid), "sha": sha(data), "lines": [line, line + n - 1]})
        line += data.decode().count("\n")
    return out


def file_digest(stmts):
    return sha(json.dumps([(s["key"], s["atom"], s["rev"], s["sha"]) for s in stmts]).encode())


# ------------------------------------------------------------------ EKOS, unchanged


def ekos(ws, *args, check=True, env_extra=None):
    env = dict(os.environ)
    env.update(env_extra or {})
    r = subprocess.run([CONF["ekos"], *args], cwd=ws, capture_output=True, text=True, env=env)
    if check and r.returncode != 0:
        raise SystemExit(f"ekos {' '.join(args)} failed in {ws}: {r.stderr[-400:] or r.stdout[-400:]}")
    return r


def run_pipeline(ws, out):
    """The unchanged pipeline of slice1/ekos-compile.sh: init, build, recover, resolve, compile,
    commit, then the export and the conflicts list. Returns {step: seconds}."""
    ws, out = pathlib.Path(ws), pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=True)
    secs = {}
    for step in ("init", "build", "recover", "resolve", "compile", "commit"):
        t0 = time.time()
        r = ekos(ws, step, check=False)
        (out / f"{step}.log").write_text(r.stdout + r.stderr)
        if r.returncode != 0:
            raise SystemExit(f"ekos {step} failed; see {out / (step + '.log')}")
        secs[step] = round(time.time() - t0, 2)
    args = ["graph", "export", "--format", "ndjson"]
    for k in PROPS:
        args += ["--include-property", k]
    t0 = time.time()
    (out / "export.ndjson").write_text(ekos(ws, *args).stdout)
    (out / "conflicts.json").write_text(ekos(ws, "conflicts", "list", "--json").stdout)
    (out / "ekos-version.txt").write_text(ekos(ws, "--version").stdout)
    secs["export+conflicts"] = round(time.time() - t0, 2)
    return secs


def load_export(path):
    return M.load_export(path)


# ------------------------------------------------------------------ the local record


def latest_dir(who):
    p = STATE / who / "LATEST"
    if not p.exists():
        raise SystemExit(f"no sync yet for {who}: run `python3 -I reader/sync.py` first")
    return STATE / who / p.read_text().strip()


def load_sync(who=None):
    d = latest_dir(who or CONF["who"])
    s = json.loads((d / "sync.json").read_text())
    s["dir"] = str(d)
    return s


def ekos_dir(sync):
    return pathlib.Path(sync["dir"]) / "ws"


# ------------------------------------------------------------------ pins


def statement_pin(sync, relpath, structural):
    """The pin for one statement: (cell, atom, revision, payload sha) as recorded at sync."""
    f = sync["files"].get(relpath)
    if not f:
        return None
    for s in f["statements"]:
        if s["key"] == structural:
            return {"kind": "atom", "cell": f["cell"], "atom": s["atom"], "rev": s["rev"], "sha": s["sha"],
                    "file": relpath, "stmt": structural, "lines": s["lines"], "by": GUESS}
    return None


def file_pin(sync, relpath):
    f = sync["files"].get(relpath)
    if not f:
        return None
    return {"kind": "file", "cell": f["cell"], "file": relpath, "digest": f["digest"], "atoms": len(f["statements"]),
            "stmts": [(s["key"], s["atom"], s["rev"], s["sha"]) for s in f["statements"]], "by": "whole document"}


def cell_atom_pin(sync, cell, atom_id):
    for a in sync["cells"][cell]["atoms"]:
        if a["id"] == atom_id:
            return {"kind": "atom", "cell": cell, "atom": a["id"], "rev": a["rev"], "sha": a["sha"], "stmt": a["kind"],
                    "by": "node cell"}
    return None


def pin_label(p):
    if p["kind"] == "file":
        return f"{p['cell']} ({p['atoms']} atoms, whole document)"
    return f"{p['cell']} atom {short(p['atom'], 12)} @ rev {short(p['rev'], 12)}"


def recheck(pins, sync, who=None):
    """Re-read every cell the pins cite (one signed read each, one ssh round trip) and compare.
    Returns ({cell: seconds}, [verdict per pin]). `same bytes` or `moved`; a moved verdict
    carries the reason and the old and new text where there is one."""
    cells = sorted({p["cell"] for p in pins})
    out = STATE / (who or CONF["who"]) / "recheck" / stamp()
    rows = read_cells(cells, out, f"recheck-{stamp()}-{os.getpid()}") if cells else []
    seconds = {r["name"]: r["seconds"] for r in rows}
    fresh = {}
    for r in rows:
        if r["rc"] != 0:
            fresh[r["name"]] = ("refused", r["refusal"])
            continue
        fresh[r["name"]] = ("ok", out / f"{r['name']}.json")
    verdicts = []
    for p in pins:
        st, val = fresh.get(p["cell"], ("refused", "not read"))
        if st != "ok":
            verdicts.append({"pin": p, "verdict": "moved", "why": f"the cell can no longer be read: {val}"})
            continue
        d = M.Doc(val)
        if p["kind"] == "atom":
            a = d.atoms.get(p["atom"])
            if a is None or a.get("tombstonedAt") not in (None, "null"):
                verdicts.append({"pin": p, "verdict": "moved", "why": "the atom is gone"})
                continue
            now_sha = sha(bytes.fromhex(a["payload"]))
            if str(a["revision"]) == p["rev"] and now_sha == p["sha"]:
                verdicts.append({"pin": p, "verdict": "same bytes", "why": ""})
            else:
                verdicts.append({"pin": p, "verdict": "moved", "why": f"revision {short(p['rev'], 12)} -> {short(a['revision'], 12)}",
                                 "old": _old_text(sync, p), "new": bytes.fromhex(a["payload"]).decode(errors="replace")})
        else:
            sr = source_of(val)
            if sr is None:
                verdicts.append({"pin": p, "verdict": "moved", "why": "the cell is no longer a source document"})
                continue
            now = [(s["key"], s["atom"], s["rev"], s["sha"]) for s in statements(sr[0])]
            if file_digest_of(now) == p["digest"]:
                verdicts.append({"pin": p, "verdict": "same bytes", "why": ""})
            else:
                was = {tuple(x[:2]): x for x in p["stmts"]}
                diff = sorted({k[0] for k, x in was.items() if not any(n[:2] == k and n[2:] == x[2:] for n in now)}
                              | {n[0] for n in now if tuple(n[:2]) not in was})
                verdicts.append({"pin": p, "verdict": "moved", "why": "changed statements: " + ", ".join(diff)})
    return seconds, verdicts


def file_digest_of(tuples):
    return sha(json.dumps([list(t) for t in tuples]).encode())


def _old_text(sync, p):
    cell_file = pathlib.Path(sync["dir"]) / "cells" / f"{p['cell']}.json"
    d = M.Doc(cell_file)
    a = d.atoms.get(p["atom"])
    return bytes.fromhex(a["payload"]).decode(errors="replace") if a else None


def verdict_line(v):
    s = v["verdict"]
    return s if not v["why"] else f"{s} ({v['why']})"


def show_moved(v, indent="      "):
    """The old and new text of a moved atom, first differing line of each."""
    lines = []
    if v["verdict"] == "moved" and v.get("old") is not None and v.get("new") is not None:
        o, n = v["old"].splitlines(), v["new"].splitlines()
        for a, b in zip(o + [""] * len(n), n + [""] * len(o)):
            if a != b:
                lines.append(f"{indent}the answer said:  {a.strip()}")
                lines.append(f"{indent}now it says:     {b.strip()}")
                break
    return lines


# ------------------------------------------------------------------ EKOS output, as text


def parse_find(text):
    hits = []
    for line in text.splitlines():
        m = re.match(r"^\s+([0-9a-f]{8}-[0-9a-f-]{27})\s+(.*)$", line)
        if m:
            hits.append({"id": m.group(1), "name": m.group(2).strip()})
    return hits


def parse_object(text):
    kind = re.search(r"^Object: .*\((\w+)\)\s*$", text, re.M)
    ev = re.findall(r'^\s+\[(\d+)%\]\s+(\S+)\s+—\s+"(.*)"\s*$', text, re.M)
    return {"kind": kind.group(1) if kind else None,
            "evidence": [{"pct": int(p), "path": a, "fragment": b} for p, a, b in ev]}


def pin_for_object(sync, obj):
    """Map an object's EKOS evidence to a pin. GUESS: the fragment is turned into a structural
    key (`CREATE TABLE customers` -> create-table:customers#0); a File object gets a
    whole-document pin."""
    if obj["kind"] == "File":
        for rel in sync["files"]:
            if obj["name"] == pathlib.PurePosixPath(rel).name:
                return file_pin(sync, rel)
        return None
    for ev in obj["evidence"]:
        m = M.CREATE.match(ev["fragment"])
        if m:
            kind = re.sub(r"\s+", "-", m.group(1).lower())
            sk = f"create-{kind}:{m.group(2).strip(chr(34)).lower()}#0"
            p = statement_pin(sync, ev["path"], sk)
            if p:
                return p
    for ev in obj["evidence"]:
        if ev["path"] in sync["files"]:
            return file_pin(sync, ev["path"])
    return None
