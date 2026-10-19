#!/usr/bin/env python3
"""Write the SYNTHETIC run roots `verekos-check laws` is checked against.

These are not slice 1's run. Slice 1 (lane W17) was still running on hbox
when lane B reached this step, so the checker was built against run roots
constructed by hand from the shapes in `world/World/Examples.lean` and the
step list in `slice1/run.sh` (S2 compile, S5 review, S5 legacy edit and
recompile). Wiring the checker to the real run needs a converter from the
real run root (its signed command attempts and the cells' read JSON) to
`log.jsonl`; see notes/B-check.md.

    synthetic-run/      a run that keeps every law; the email conflict is
                        confirmed by the reviewer, a compiler-signed review
                        that *says* it is human is written too, and after
                        the legacy edit the header is rewritten (hdr@2): the
                        expected status is needsReview. A second conflict
                        whose signature does not change keeps its decision.
    synthetic-run-bad/  a compiled claim with no pins, a pin to an absent
                        claim, a self pin, transaction numbers out of order.

    python3 -I check/fixtures/make_synthetic.py
"""

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent

PRINCIPALS = {"owner": "subj-owner", "importer": "subj-importer", "compiler": "subj-compiler",
              "reviewer": "subj-reviewer", "verifier": "subj-verifier",
              "reader-shop": "subj-reader-shop"}
COMP, REV = PRINCIPALS["compiler"], PRINCIPALS["reviewer"]


def key(schema, subject, sources):
    return {"schema": schema, "subject": subject, "sources": sources}


CUSTOMERS = key("Table", ["sql-analyzer-table:customers"], ["legacy", "shop"])
ORDERS = key("Table", ["sql-analyzer-table:orders"], ["shop"])
FK = key("ForeignKey", ["orders", "customers"], ["shop"])
CF_EMAIL = key("Conflict", ["sql-analyzer-table:customers", "columns.email.data_type"],
               ["legacy", "shop"])
CF_TOTAL = key("Conflict", ["sql-analyzer-table:orders", "columns.total.data_type"], ["shop"])


def src(doc, rng, rev):
    return {"source": doc, "range": rng, "atoms": [rev]}


def on(k, core=""):
    return {"claim_key": k, "core": core}


def put(tx, signer, run, stage, k, pins, payload, **extra):
    return {"tx": tx, "signer": signer, "run": run, "stage": stage, "op": "put",
            "claim": {**k, "payload": payload, "pins": pins}, **extra}


def review(tx, signer, n, cf, hdr, decision, **extra):
    return put(tx, signer, "", "review",
               key("Review", [cf["subject"][0], cf["subject"][1], str(n)], []),
               [on(cf, hdr)], {"decision": decision}, **extra)


GOOD = [
    put(1, COMP, "c1", "compile", CUSTOMERS,
        [src("src-shop", "create-table:customers#0", "shop@r1"),
         src("src-legacy", "create-table:customers#0", "legacy@r1")],
        {"name": "customers", "columns": ["id", "email", "name"]}),
    put(2, COMP, "c1", "compile", ORDERS,
        [src("src-shop", "create-table:orders#0", "shop@r1")], {"name": "orders"}),
    put(3, COMP, "c1", "compile", FK,
        [on(ORDERS), on(CUSTOMERS), src("src-shop", "create-table:orders#0", "shop@r1")],
        {"from": "orders.customer_id", "to": "customers.id"}),
    put(4, COMP, "c1", "compile", CF_EMAIL,
        [on(CUSTOMERS), src("src-legacy", "create-table:customers#0", "legacy@r1"),
         src("src-shop", "create-table:customers#0", "shop@r1")],
        {"attribute": "columns.email.data_type", "values": ["text", "varchar(255)"]},
        header_rev="hdr-email@1"),
    put(5, COMP, "c1", "compile", CF_TOTAL,
        [on(ORDERS), src("src-shop", "create-table:orders#0", "shop@r1")],
        {"attribute": "columns.total.data_type", "values": ["int", "numeric(10,2)"]},
        header_rev="hdr-total@1"),
    review(6, REV, 1, CF_EMAIL, "hdr-email@1", "confirmed"),
    review(7, REV, 1, CF_TOTAL, "hdr-total@1", "dismissed"),
    # the compiler signs a review whose payload claims a human wrote it
    review(8, COMP, 2, CF_EMAIL, "hdr-email@1", "rejected", payload_author="human"),
    # S5: the legacy file is edited; the recompile re-puts customers and the
    # email conflict, whose signature changed, so its header moves to @2.
    put(9, COMP, "c2", "compile", CUSTOMERS,
        [src("src-shop", "create-table:customers#0", "shop@r1"),
         src("src-legacy", "create-table:customers#0", "legacy@r2")],
        {"name": "customers", "columns": ["id", "email", "name"]}),
    put(10, COMP, "c2", "compile", CF_EMAIL,
        [on(CUSTOMERS), src("src-legacy", "create-table:customers#0", "legacy@r2"),
         src("src-shop", "create-table:customers#0", "shop@r1")],
        {"attribute": "columns.email.data_type", "values": ["varchar(320)", "varchar(255)"]},
        header_rev="hdr-email@2"),
    # the total conflict is recompiled with the same signature: same header revision
    put(11, COMP, "c2", "compile", CF_TOTAL,
        [on(ORDERS), src("src-shop", "create-table:orders#0", "shop@r1")],
        {"attribute": "columns.total.data_type", "values": ["int", "numeric(10,2)"]},
        header_rev="hdr-total@1"),
]
GOOD_EXPECT = {"adm_log": True, "pins_nonempty": True, "tx_monotone": True, "conflicts": [
    {"subject": CF_EMAIL["subject"], "status": "needsReview",
     "timeline": [[4, "open"], [6, "confirmed"], [10, "needsReview"]]},
    {"subject": CF_TOTAL["subject"], "status": "dismissed"}]}

SELF = key("Table", ["self"], ["shop"])
BAD = [
    put(1, COMP, "c1", "compile", ORDERS, [], {"name": "orders"}),
    put(3, COMP, "c1", "compile", FK, [on(ORDERS), on(CUSTOMERS)], {"from": "orders"}),
    put(2, COMP, "c1", "compile", SELF, [on(SELF)], {"name": "self"}),
]


def write(name, lines, expect):
    d = HERE / name
    d.mkdir(exist_ok=True)
    (d / "principals.json").write_text(json.dumps(PRINCIPALS, indent=1) + "\n")
    (d / "log.jsonl").write_text("".join(json.dumps(l) + "\n" for l in lines))
    if expect is not None:
        (d / "expect.json").write_text(json.dumps(expect, indent=1) + "\n")


write("synthetic-run", GOOD, GOOD_EXPECT)
write("synthetic-run-bad", BAD, None)
