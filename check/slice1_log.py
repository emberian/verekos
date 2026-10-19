#!/usr/bin/env python3
"""Turn a slice-1 run root into the log `verekos-check laws` reads. UNTRUSTED.

Reads a copy of a slice-1 run root (lane W17's `var/w17/<run>`, fetched from
hbox by `slice1/run.sh`) and writes `<out>/principals.json`, `<out>/log.jsonl`
and `<out>/expect.json`. Nothing here is proved; it is a reading of the
mapper's document shapes (`slice1/the slice-1 mapper (now `verekos-map`, Lean; the Python twin was deleted 2026-10-19)`) and minidregg's cell-read JSON.

What becomes a claim (one log line per installed write, in `receipts.tsv`
order):

- `compile-N-obj-*` → a `Table`-kind claim (the header atom's `kind`),
  subject = its `logical_key`, sources = its `sources`.
- `compile-N-cf-*` → a `Conflict` claim, subject = (`subject_key`,
  `attribute`), sources = the `source_key`s of its claim atoms.
- `compile-N-manifest` → a `Manifest` claim (its links to objects are by
  logical key, not revision pins, so they are not claim pins here).
- `review-*` → a `Review` claim with ONE claim pin on the conflict it names,
  at the header revision the reviewer's transclusion pinned; the decision is
  the verb (`resolve` → `resolved`, `dismiss` → `dismissed`).
- Imports (source documents), compile-run records and attestations are not
  claims in `World.Claim` and are skipped (counted in the output).

Where each field comes from:

- **signer**: for a compile write, the host-recorded `createdBy.subject` of
  the cell entries that write created (entries are grouped by `createdAt`,
  the operation); for the review, the `subject` of the signed command in the
  reviewer's attempt `intent.json`. Never a payload field.
- **pins**: each live transclusion linked from the cell at that write, as a
  source pin (document = the source cell, range = the statement key, atoms =
  [atom@revision]), from the cell read taken after that write: `r5-before/`
  (or `compile-2/cur-*`) for compile 1, `r5-after/` for compile 2.
- **header_rev** (conflicts): the header atom's revision in that read (the
  world mints it; design 3.1).

    python3 -I check/slice1_log.py --run var/w17/run-2 --out check/fixtures/slice1-run-2
"""

import argparse
import json
import sys
from pathlib import Path


def entries(path: Path):
    d = json.loads(path.read_text())
    return d["cell"]["entries"]


def payload(e):
    return json.loads(bytes.fromhex(e["payload"]).decode())


def header_atom(es):
    """The atom whose payload names the claim: obj (logical_key) or cf (attribute)."""
    for e in es:
        if e["type"] != "atom":
            continue
        try:
            p = payload(e)
        except (ValueError, UnicodeDecodeError):
            continue
        if "logical_key" in p or ("attribute" in p and "signature" in p):
            return e, p
    return None, None


def statement_index(run: Path):
    """atom id → (source key, statement key), from the mapper's commands.json."""
    out = {}
    for n in (1, 2):
        f = run / f"compile-{n}/req/commands.json"
        if f.is_file():
            for src, v in json.loads(f.read_text())["inputs"].items():
                for skey, (atom, _rev) in v["statements"].items():
                    out[atom] = (src, skey)
    return out


def pins_of(es, stmts):
    """Live transclusions linked from the cell, as source pins."""
    linked = {e["target"]["id"] for e in es if e["type"] == "link" and not e.get("tombstonedAt")
              and isinstance(e.get("target"), dict) and e["target"].get("type") == "transclusion"}
    pins = []
    for e in es:
        if e["type"] != "transclusion" or e["id"] not in linked:
            continue
        o = e["opening"]
        if isinstance(o, str):
            o = json.loads(o.replace("'", '"'))
        for p in o["pins"]:
            src, skey = stmts.get(p["atom"], ("?", p["atom"]))
            pins.append({"source": f"src-{src}", "range": skey,
                         "atoms": [f"{p['atom']}@{p['revision']}"]})
    return sorted(pins, key=lambda p: (p["source"], p["range"], p["atoms"]))


def signer_of(es, op):
    subs = {e["createdBy"]["subject"] for e in es if e.get("createdAt") == op and "createdBy" in e}
    subs |= {e["author"]["subject"] for e in es if e["type"] == "transclusion"
             and e.get("createdAt") == op and "author" in e}
    if len(subs) != 1:
        raise ValueError(f"operation {op[:12]}: signers {subs}")
    return subs.pop()


def claim_of(cell, es, stmts):
    h, p = header_atom(es)
    if h is None:
        if cell == "manifest":
            return {"schema": "Manifest", "subject": ["manifest"], "sources": [],
                    "payload": {"cell": cell}, "pins": pins_of(es, stmts)}, None
        raise ValueError(f"{cell}: no header atom")
    if "logical_key" in p:
        return {"schema": p["kind"], "subject": [p["logical_key"]],
                "sources": sorted(p.get("sources", [])), "payload": p,
                "pins": pins_of(es, stmts)}, None
    srcs = set()
    for e in es:
        if e["type"] == "atom":
            try:
                q = payload(e)
            except (ValueError, UnicodeDecodeError):
                continue
            if "claimed_by" in q and "source_key" in q:
                srcs.add(q["source_key"])
    return {"schema": "Conflict", "subject": [p["subject_key"], p["attribute"]],
            "sources": sorted(srcs), "payload": p, "pins": pins_of(es, stmts)}, h["revision"]


def read_for(run: Path, cell: str, n: int) -> Path:
    """The cell read taken after compile n."""
    names = {"obj-customers": "obj-customers.json", "cf-customers-columns-email-data-type": "cf.json",
             "cf-customers-columns": "cf-columns.json"}
    if cell in names:
        return run / ("r5-before" if n == 1 else "r5-after") / names[cell]
    if n == 1:
        return run / f"compile-2/cur-{cell}.json"
    raise ValueError(f"{cell}: no read after compile {n}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    a = ap.parse_args()
    run = a.run
    principals = json.loads((run / "principals.json").read_text())
    stmts = statement_index(run)
    rows = [l.split("\t") for l in (run / "receipts.tsv").read_text().splitlines() if l.strip()]
    installed = [r for r in rows if len(r) > 3 and r[3] == "got=installed"]
    log, skipped, tx = [], [], 0
    claim_ids = {}
    for r in installed:
        name = r[1]
        if name.startswith("compile-") and not name.endswith("-run"):
            n = int(name.split("-")[1])
            cell = name.split("-", 2)[2]
            es = entries(read_for(run, cell, n))
            claim, hdr = claim_of(cell, es, stmts)
            ops = {e["createdAt"] for e in es if "createdAt" in e}
            doc = next(e for e in es if e["type"] == "document")
            # compile 1 created the document; compile 2 is the one other operation
            later = ops - {doc["createdAt"]}
            if n == 1:
                op = doc["createdAt"]
            elif len(later) == 1:
                op = later.pop()
            else:
                raise ValueError(f"{name}: expected one later operation, found {len(later)}")
            tx += 1
            line = {"tx": tx, "signer": signer_of(es, op), "run": f"compile-{n}",
                    "stage": "compile", "op": "put", "claim": claim, "source_step": name}
            if hdr is not None:
                line["header_rev"] = hdr
            claim_ids[cell] = {k: claim[k] for k in ("schema", "subject", "sources")}
            log.append(line)
        elif name.startswith("review-"):
            intent = json.loads((run / "receipts/world/reviewer-workspace/attempts" / name
                                 / "intent.json").read_text())
            cmd = intent["purpose"]["draft"]["command"]
            acts = cmd["targets"][0]["payload"]["actions"]
            decision = next(json.loads(bytes.fromhex(x["payload"]).decode())
                            for x in acts if x.get("type") == "createAtom")
            pin = next(x["request"]["pins"][0] for x in acts if x.get("type") == "transclude")
            target = claim_ids[decision["conflict_cell"]]
            verb = {"resolve": "resolved", "dismiss": "dismissed"}.get(decision["verb"], decision["verb"])
            tx += 1
            log.append({"tx": tx, "signer": cmd["subject"], "run": "", "stage": "review",
                        "op": "put", "source_step": name,
                        "claim": {"schema": "Review", "subject": [decision["conflict_cell"], name],
                                  "sources": [], "payload": {**decision, "decision": verb},
                                  "pins": [{"claim_key": target, "core": pin["revision"]}]}})
        else:
            skipped.append(name)
    out = a.out
    out.mkdir(parents=True, exist_ok=True)
    (out / "principals.json").write_text(json.dumps(principals, indent=1) + "\n")
    (out / "log.jsonl").write_text("".join(json.dumps(l) + "\n" for l in log))
    # What slice 1's own steps observed (receipts.tsv R5-after: the review pin
    # reads `moved`, the email header was edited, the columns header was not).
    (out / "expect.json").write_text(json.dumps({
        "adm_log": True, "pins_nonempty": True, "tx_monotone": True,
        "conflicts": [
            {"subject": ["sql-analyzer-table:customers", "columns.email.data_type"],
             "status": "needsReview"},
            {"subject": ["sql-analyzer-table:customers", "columns"], "status": "open"}]},
        indent=1) + "\n")
    print(json.dumps({"writes": len(log), "skipped_not_claims": skipped}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
