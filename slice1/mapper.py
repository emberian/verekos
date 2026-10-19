#!/usr/bin/env python3 -I
"""slice1/mapper.py: EKOS sources and an EKOS graph export, as minidregg content commands.

Stdlib only; run with `python3 -I`. Every output is a pure function of the inputs named on the
command line: no clock, no randomness, no environment. The outputs are proposal-v1 `invoke`
request files that `mini workspace --action propose --request FILE` signs and `submit` lands
(the raw form journey.d/j12t-kernel.sh uses; the action JSON is decoded by
minidregg Host/Json.lean `contentAction`).

Subcommands
  split   FILE                       print the statement atoms of FILE (key, bytes, first line)
  import  --source-key K --path P --file F --cell NAME [--read READ.json] --out REQ.json
          the import family of exploration 01 §2.2: one text atom per statement, atom ids by
          structural key, diffed against the current document. Writes REQ.json only when
          there is something to submit; prints `nothing to submit` otherwise.
  render  --read READ.json --out FILE
          the source document's statements, concatenated in run order: the file EKOS compiles.
  plan    --export E --source K=READ.json ...   the cells a compile needs (name, schema, law, room)
  compile --export E --source K=READ.json ... --cells CELLS.json --out DIR
          [--current NAME=READ.json ...] [--ekos-version S]
          one request per compiled cell that changes, in a fixed order, plus DIR/commands.sha256:
          the SHA-256 of the concatenated request bytes. --current gives the compiled cells'
          present documents (recompile); without it every cell is a birth.
  runrec  --dir DIR --source K=READ.json ... --cell NAME [--read READ.json] --out REQ.json
          the compile-run append (L-run): the run record and a snapshot of each source header.
  attest  --compile-run READ.json --claimed SHA --replayed SHA --cell NAME --source-cell NAME --out REQ.json
          the verifier's attestation (L-run): its record and a snapshot of the compile-run record.
  review  --conflict READ.json --conflict-cell NAME --cell NAME [--read READ.json] --pick K
          --note TEXT --out REQ.json   a reviewer decision transcluding the conflict header.
"""
import hashlib
import json
import pathlib
import re
import sys

MAPPER_VERSION = "verekos-slice1-mapper/1"
DEATH = "keepTombstone"

# ------------------------------------------------------------------ identifiers and bytes


def num(*parts):
    """A 120-bit identifier as minidregg's JSON spells it (a decimal string).

    Approximation: minidregg derives ids with `deriveIdentifier` over a Lean `IdPreimage`
    (Theory/Hyperdocument.lean:166-169); the deployed client exposes no command for it, so the
    preimage here is SHA-256 over a tagged, NUL-joined tuple, truncated to 15 bytes."""
    h = hashlib.sha256(b"VEREKOS/ID/v1\x00" + "\x00".join(parts).encode()).digest()
    return str(int.from_bytes(h[:15], "big") or 1)


def schema(name):
    """A schema digest: `DocumentRecord.schema` / `inlineObject schema` are Nats in the JSON."""
    return num("schema", name)


def canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def hexs(text):
    return text.encode().hex() if isinstance(text, str) else text.hex()


def obj_kind(name):
    return {"type": "inlineObject", "schema": schema(name)}


TEXT = {"type": "text"}

# ------------------------------------------------------------------ statements


CREATE = re.compile(r'^\s*create\s+(?:or\s+replace\s+)?(?:unique\s+)?(table|index|view|materialized\s+view|function|procedure|trigger)\s+(?:if\s+not\s+exists\s+)?([\w."]+)', re.I)


def structural_key(text):
    m = CREATE.match(text)
    if m:
        kind = re.sub(r"\s+", "-", m.group(1).lower())
        return f"create-{kind}:{m.group(2).strip(chr(34)).lower()}"
    norm = " ".join(text.split())
    return "anon:" + hashlib.sha256(norm.encode()).hexdigest()[:16]


def split(data):
    """Statement atoms whose concatenation is `data` byte for byte.

    A statement runs from its first non-blank, non-comment line to the line that ends in `;`,
    and keeps the blank lines after it. A run of comment lines (with the blank lines around it)
    is its own anonymous atom. Keys are `create-table:<name>#<occurrence>` or `anon:<sha>#n`."""
    lines = data.splitlines(keepends=True)
    chunks, cur, state = [], [], "gap"   # gap: collecting comments/blank; stmt: inside a statement
    gap_has_text = False
    for line in lines:
        s = line.strip()
        if state == "stmt":
            cur.append(line)
            if s.endswith(";"):
                state = "tail"
            continue
        if state == "tail":                      # blank lines after a statement stay with it
            if s == "":
                cur.append(line)
                continue
            chunks.append(("stmt", "".join(cur))); cur = []; state = "gap"; gap_has_text = False
        if s == "" or s.startswith("--"):
            cur.append(line)
            gap_has_text = gap_has_text or s.startswith("--")
            continue
        if cur:                                  # a gap before this statement
            if gap_has_text or not chunks:
                chunks.append(("gap", "".join(cur)))
            else:                                # blank-only gap: belongs to the previous statement
                k, t = chunks[-1]; chunks[-1] = (k, t + "".join(cur))
            cur = []
        cur.append(line)
        state = "tail" if s.endswith(";") else "stmt"
    if cur:
        chunks.append(("stmt" if state != "gap" else "gap", "".join(cur)))
    assert "".join(t for _, t in chunks) == data, "split lost bytes"
    seen, out = {}, []
    for _, text in chunks:
        key = structural_key(text)
        occ = seen.get(key, 0); seen[key] = occ + 1
        out.append((f"{key}#{occ}", text))
    return out


# ------------------------------------------------------------------ reading a signed view


class Doc:
    """The parts of a `mini workspace --action read` view the mapper uses."""

    def __init__(self, path):
        view = json.loads(pathlib.Path(path).read_text())
        cell = view.get("cell") or {}
        # `read` views carry no target; the runner adds the reference's `target` (read_cell).
        self.target = str(view["target"])
        self.entries = cell.get("entries", [])
        self.atoms = {e["id"]: e for e in self.entries if e.get("type") == "atom"}
        self.runs = {e["id"]: e for e in self.entries if e.get("type") == "run"}
        self.elements = {e["id"]: e for e in self.entries if e.get("type") == "element"}
        self.transclusions = {e["id"]: e for e in self.entries if e.get("type") == "transclusion"}
        self.links = {e["id"]: e for e in self.entries if e.get("type") == "link"}
        docs = [e for e in self.entries if e.get("type") == "document"]
        self.document = docs[0] if docs else None

    def before(self, atom):
        """The exact prior record `editAtom` is guarded on (j12t-kernel.sh `edit_line`)."""
        return {k: v for k, v in self.atoms[atom].items() if k not in ("type", "id", "canonical")}

    def payload(self, atom):
        return bytes.fromhex(self.atoms[atom]["payload"])

    def revision(self, atom):
        return str(self.atoms[atom]["revision"])

    def element_revision(self, element):
        return str(self.elements[element]["revision"])


def source_header(doc):
    for a in doc.atoms.values():
        if a.get("kind") == obj_kind("ekos/source-header/v1"):
            return json.loads(bytes.fromhex(a["payload"]))
    raise SystemExit(f"read of {doc.target}: no ekos/source-header/v1 atom")


class Source:
    """One imported source cell: its key, header, statement atoms (by structural key) in run order."""

    def __init__(self, key, read_path):
        self.key = key
        self.doc = Doc(read_path)
        self.header = source_header(self.doc)
        self.cell = self.header["cell"]
        sk, path = self.header["source_key"], self.header["path"]
        assert sk == key, f"source {key}: header says {sk}"
        self.path = path
        ids = ids_for_source(key, path)
        self.header_atom, self.header_run, self.stmt_run = ids["header"], ids["header_run"], ids["stmt_run"]
        run = self.doc.runs.get(self.stmt_run)
        order = [str(a) for a in run["atoms"]] if run else []
        self.by_key, self.order = {}, []
        for aid in order:
            a = self.doc.atoms.get(aid)
            if a is None or a.get("tombstonedAt") not in (None, "null"):
                continue
            key_of = self.key_of_atom(aid)
            self.by_key[key_of] = aid
            self.order.append((key_of, aid))

    def key_of_atom(self, aid):
        text = bytes.fromhex(self.doc.atoms[aid]["payload"]).decode()
        k = structural_key(text)
        for occ in range(64):
            if num("atom", self.key, self.path, f"{k}#{occ}") == aid:
                return f"{k}#{occ}"
        raise SystemExit(f"atom {aid} of {self.key}: key changed under its id (a rename is a new statement)")

    def text(self):
        return "".join(bytes.fromhex(self.doc.atoms[a]["payload"]).decode() for _, a in self.order)

    def pin(self, structural):
        aid = self.by_key[structural]
        return aid, self.doc.revision(aid)

    def snapshot(self, atom, run=None):
        """A snapshot transclusion request over one atom of this source, pinned at its revision."""
        run = run or self.stmt_run
        return {"source": self.doc.target,
                "range": {"start": {"run": run, "neighbor": atom, "bias": "before", "death": DEATH},
                          "finish": {"run": run, "neighbor": atom, "bias": "after", "death": DEATH}},
                "mode": "snapshot", "pins": [{"atom": atom, "revision": self.doc.revision(atom)}]}


def ids_for_source(key, path):
    return {"root": num("element", key, path, "root"), "header": num("atom", key, path, "header"),
            "header_run": num("run", key, path, "header"), "stmt_run": num("run", key, path, "statements")}


# ------------------------------------------------------------------ requests


def invoke(cell, actions, reads=()):
    targets = [{"name": cell, "payload": {"type": "content", "actions": actions}}]
    targets += [{"name": r, "payload": {"type": "read"}} for r in sorted(set(reads))]
    return {"type": "minidregg-workspace-proposal-v1", "action": "invoke", "targets": targets}


def write_req(path, req):
    data = (canon(req) + "\n").encode()
    pathlib.Path(path).write_bytes(data)
    return data


# ------------------------------------------------------------------ import


def cmd_import(a):
    data = pathlib.Path(a["file"]).read_bytes().decode()
    key, path, cell = a["source-key"], a["path"], a["cell"]
    ids = ids_for_source(key, path)
    stmts = split(data)
    header = {"cell": cell, "source_key": key, "path": path, "importer": MAPPER_VERSION,
              "redaction": "not run: the Redact kernel is not built and ekos_common::redaction has no CLI entry; fixtures carry no secrets",
              "pipeline_logic_version": None}
    doc = Doc(a["read"]) if a.get("read") else None
    acts = []
    if doc is None or doc.document is None:
        acts.append({"type": "createDocument", "rootElement": ids["root"], "schema": schema("ekos/source/v1")})
        acts.append({"type": "createAtom", "atom": ids["header"], "kind": obj_kind("ekos/source-header/v1"),
                     "payload": hexs(canon(header))})
        sids = []
        for k, text in stmts:
            aid = num("atom", key, path, k); sids.append(aid)
            acts.append({"type": "createAtom", "atom": aid, "kind": TEXT, "payload": hexs(text)})
        acts.append({"type": "createRun", "run": ids["header_run"], "atoms": [ids["header"]]})
        acts.append({"type": "createRun", "run": ids["stmt_run"], "atoms": sids})
    else:
        run = doc.runs.get(ids["stmt_run"])
        present = [str(x) for x in run["atoms"]] if run else []
        want = [(k, num("atom", key, path, k), t) for k, t in stmts]
        want_ids = [w[1] for w in want]
        live = [x for x in present if doc.atoms[x].get("tombstonedAt") in (None, "null")]
        if [x for x in want_ids if x in live] != [x for x in live if x in want_ids]:
            raise SystemExit("import: statements were reordered; editElement .move is not implemented in slice 1")
        prev = None
        for k, aid, text in want:
            if aid in doc.atoms and aid in live:
                if doc.payload(aid) != text.encode():
                    acts.append({"type": "editAtom", "atom": aid, "before": doc.before(aid), "kind": TEXT,
                                 "payload": hexs(text), "tombstone": False})
            else:
                if aid in doc.atoms:
                    raise SystemExit(f"import: {k} returns under a tombstoned id; not handled in slice 1")
                acts.append({"type": "createAtom", "atom": aid, "kind": TEXT, "payload": hexs(text)})
                anchor = None if prev is None else {"run": ids["stmt_run"], "neighbor": prev, "bias": "after", "death": DEATH}
                acts.append({"type": "insertRun", "run": ids["stmt_run"], "anchor": anchor, "atoms": [aid]})
            prev = aid
        for x in live:
            if x not in want_ids:
                acts.append({"type": "editAtom", "atom": x, "before": doc.before(x), "kind": TEXT,
                             "payload": doc.atoms[x]["payload"], "tombstone": True})
    if not acts:
        print("nothing to submit")
        return
    write_req(a["out"], invoke(cell, acts))
    print(f"{len(acts)} action(s): " + ", ".join(sorted({x['type'] for x in acts})))


def cmd_render(a):
    src = Source(a["key"], a["read"])
    pathlib.Path(a["out"]).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(a["out"]).write_bytes(src.text().encode())
    print(f"{src.key}: {len(src.order)} statement atom(s) -> {a['out']}")


# ------------------------------------------------------------------ the compile


def load_export(path):
    nodes, edges, kinds, rkinds = [], [], [], []
    for line in pathlib.Path(path).read_text().splitlines():
        r = json.loads(line)
        if r["record"] == "header":
            kinds, rkinds = r["kind_index"], r["rel_kind_index"]
        elif r["record"] == "node":
            nodes.append(r)
        elif r["record"] == "edge":
            edges.append(r)
    for n in nodes:
        n["kind"] = kinds[n["k"]]
    for e in edges:
        e["kind"] = rkinds[e["k"]]
        e["from"], e["to"] = nodes[e["s"]], nodes[e["t"]]
    return nodes, edges


def safe(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def table_cell(name):
    return "obj-" + safe(name)


def conflict_cell(node):
    return "cf-" + safe(node["n"])


def sources_arg(a):
    out = []
    for spec in a.get("source", []):
        k, path = spec.split("=", 1)
        out.append(Source(k, path))
    return out


def defining(sources, table):
    """GUESS (EKOS evidence location): EKOS table evidence names the file, not a statement
    (sql_analyzer.rs `SourceLocation::file`, fragment `CREATE TABLE <name>`), and a merged
    object keeps only the surviving definition's evidence. The mapper takes every source
    statement whose structural key is `create-table:<name>#0`."""
    key = f"create-table:{table.lower()}#0"
    return [(s, key) for s in sources if key in s.by_key]


def ekos_path(src):
    return f"src/{src.key}/{src.path}"


def build_plan(nodes, sources):
    """The compiled cells: one per Table, one per ConflictingEvidence, the manifest.
    Room rule (GUESS): a Table lives in the room of its first defining source in --source order
    (the order of [[sources]] in ekos.toml); conflicts and the manifest live in no room."""
    plan = []
    for n in sorted((n for n in nodes if n["kind"] == "Table"), key=lambda n: n["n"]):
        d = defining(sources, n["n"])
        if not d:
            raise SystemExit(f"table {n['n']}: no defining statement in any source")
        plan.append({"cell": table_cell(n["n"]), "schema": "ekos/object/v1", "law": "L-obj", "room": d[0][0].key,
                     "node": n["id"]})
    for n in sorted((n for n in nodes if n["kind"] == "ConflictingEvidence"), key=lambda n: n["n"]):
        plan.append({"cell": conflict_cell(n), "schema": "ekos/conflict/v1", "law": "L-obj", "room": None, "node": n["id"]})
    plan.append({"cell": "manifest", "schema": "ekos/manifest/v1", "law": "L-obj", "room": None, "node": None})
    return plan


def cmd_plan(a):
    nodes, _ = load_export(a["export"])
    print(json.dumps(build_plan(nodes, sources_arg(a)), indent=1))


class Builder:
    """Actions for one compiled cell: a birth or a diff against its current document."""

    def __init__(self, cell, cells, current):
        self.cell, self.cells, self.cur = cell, cells, current
        self.acts, self.reads = [], set()
        self.root = num("element", cell, "root")
        self.born = current is None or current.document is None
        self.root_rev = "0" if self.born else current.element_revision(self.root)

    def id(self, *p):
        return num(*p[:1], self.cell, *p[1:])

    def birth(self, schema_name):
        if self.born:
            self.acts.append({"type": "createDocument", "rootElement": self.root, "schema": schema(schema_name)})

    def atom(self, aid, kind, payload_text, run=None):
        """Create, or edit when the bytes differ; a run over it when `run` is named."""
        p = hexs(payload_text)
        if self.born or aid not in self.cur.atoms:
            self.acts.append({"type": "createAtom", "atom": aid, "kind": kind, "payload": p})
            if run:
                self.acts.append({"type": "createRun", "run": run, "atoms": [aid]})
            return True
        if self.cur.atoms[aid]["payload"] != p:
            self.acts.append({"type": "editAtom", "atom": aid, "before": self.cur.before(aid), "kind": kind,
                              "payload": p, "tombstone": False})
        return False

    def place(self, container, children, container_rev="0"):
        """Detach `children` (each just appended to the root) and splice them into `container`.

        `editElement` checks a container against the revision its author read; a container
        created or already edited by this same operation is current for it (CR `openContainer`),
        so a birth may name any revision ("0"). A later command names the revision it read."""
        for i, c in enumerate(children):
            self.acts.append({"type": "editElement", "element": self.root, "revision": self.root_rev,
                              "op": {"type": "remove", "child": c}})
            self.acts.append({"type": "editElement", "element": container, "revision": container_rev,
                              "op": {"type": "splice", "index": str(i), "child": c}})

    def detach(self, element):
        """Take an old evidence container out of the tree (its records stay; history keeps them)."""
        parent = str(self.cur.elements[element]["parent"])
        self.acts.append({"type": "editElement", "element": parent, "revision": self.cur.element_revision(parent),
                          "op": {"type": "remove", "child": element}})

    def evidence(self, tag, src, structural, meta):
        """An evidence container: a meta atom and a snapshot transclusion of one source statement.

        Ids derive from (cell, tag, source, atom, revision): the evidence id is (logical key,
        pins), never minted. Returns (container, created). When the pin moved since the cell's
        current evidence for the same statement, a new container is made and the old one is
        detached; when the same pin is already there, nothing is written."""
        atom, rev = src.pin(structural)
        ids = lambda r: (self.id("element", "ev", tag, src.key, atom, r),
                         self.id("transclusion", "ev", tag, src.key, atom, r))
        container, tr = ids(rev)
        self.reads.add(src.cell)
        if not self.born and tr in self.cur.transclusions:
            return container, False
        if not self.born:
            for t in self.cur.transclusions.values():
                pins = (t.get("opening") or {}).get("pins") or []
                if pins and str(pins[0]["atom"]) == atom:
                    old_c, old_t = ids(str(pins[0]["revision"]))
                    if old_t == t["id"] and self.cur.elements.get(old_c, {}).get("parent") not in (None, "null"):
                        self.detach(old_c)
        meta_atom = self.id("atom", "ev-meta", tag, src.key, atom, rev)
        self.acts.append({"type": "createContainer", "element": container})
        self.acts.append({"type": "createAtom", "atom": meta_atom, "kind": obj_kind("ekos/evidence-meta/v1"),
                          "payload": hexs(canon(meta))})
        self.acts.append({"type": "transclude", "transclusion": tr,
                          "link": self.id("link", "ev", tag, src.key, atom, rev), "request": src.snapshot(atom)})
        self.place(container, [meta_atom, tr])
        return container, True


def table_actions(b, node, sources, tables_by_name, edges, cells, ekos_version):
    name = node["n"]
    key = f"sql-analyzer-table:{name}"
    b.birth("ekos/object/v1")
    d = defining(sources, name)
    b.atom(b.id("atom", "header"), obj_kind("ekos/header/v1"),
           canon({"kind": node["kind"], "name": name, "logical_key": key, "ekos_id": node["id"],
                  "compiler": ekos_version, "mapper": MAPPER_VERSION, "sources": [s.key for s, _ in d]}))
    b.atom(b.id("atom", "properties"), obj_kind("ekos/properties/v1"), canon(node.get("p", {})))
    for src, structural in d:
        b.evidence("object", src, structural,
                      {"source_key": src.key, "structural_key": structural, "confidence_milli": 1000,
                       "pass": "sql_analyzer", "fragment_kind": "create-table",
                       "located_by": "structural key (EKOS evidence names the file only)"})
    for e in sorted((e for e in edges if e["from"]["id"] == node["id"] and e["kind"] == "ForeignKey"),
                    key=lambda e: e["to"]["n"]):
        to = e["to"]["n"]
        tag = ("edge", e["kind"], to)
        cont, edge_atom, run, link = (b.id("element", *tag), b.id("atom", *tag), b.id("run", *tag), b.id("link", *tag))
        if not b.born and link in b.cur.links:
            continue
        b.acts.append({"type": "createContainer", "element": cont})
        b.atom(edge_atom, obj_kind("ekos/edge/v1"),
               canon({"kind": e["kind"], "to": f"sql-analyzer-table:{to}", "to_name": to, "status": "confirmed",
                      "properties": {}, "valid_from": None, "valid_until": None}), run=run)
        b.acts.append({"type": "link", "link": link,
                       "source": {"start": {"run": run, "neighbor": edge_atom, "bias": "before", "death": DEATH},
                                  "finish": {"run": run, "neighbor": edge_atom, "bias": "after", "death": DEATH}},
                       "target": {"type": "document", "id": cells[table_cell(to)]},
                       "relation": schema("relation/" + e["kind"])})
        # GUESS: EKOS edges carry no evidence in the export; the mapper cites the referencing
        # table's own statement in each source whose text names `REFERENCES <to>`.
        kids = [edge_atom]
        for src, structural in d:
            text = src.doc.payload(src.by_key[structural]).decode().lower()
            if re.search(r"references\s+" + re.escape(to.lower()) + r"\b", text):
                ev = b.evidence("edge-" + to, src, structural,
                                   {"source_key": src.key, "structural_key": structural, "confidence_milli": 1000,
                                    "pass": "sql_analyzer", "fragment_kind": "foreign-key",
                                    "located_by": "REFERENCES clause inside the referencing statement"})
                kids.append(ev[0])
        b.place(cont, kids)
    return [s.cell for s, _ in d]


def conflict_actions(b, node, sources, cells, ekos_version):
    p = node.get("p", {})
    b.birth("ekos/conflict/v1")
    header = b.id("atom", "header")
    b.atom(header, obj_kind("ekos/conflict-header/v1"),
           canon({"subject_key": f"sql-analyzer-table:{p.get('subject_name')}", "subject_name": p.get("subject_name"),
                  "attribute": p.get("attribute"), "conflict_type": p.get("conflict_type"),
                  "signature": p.get("signature"), "ekos_id": node["id"], "compiler": ekos_version}),
           run=b.id("run", "header"))
    by_path = {ekos_path(s): s for s in sources}
    for claim in sorted(p.get("claims", []), key=lambda c: c["path"]):
        src = by_path.get(claim["path"])
        if src is None:
            raise SystemExit(f"conflict {node['n']}: claim path {claim['path']} names no imported source")
        structural = f"create-table:{p.get('subject_name', '').lower()}#0"
        cont = b.id("element", "claim", src.key)
        meta = b.id("atom", "claim", src.key)
        new = b.atom(meta, obj_kind("ekos/claim/v1"),
                     canon({"source_key": src.key, "path": claim["path"], "value": claim["value"],
                            "line": claim.get("line"), "claimed_by": claim.get("source")}))
        if new:
            b.acts.append({"type": "createContainer", "element": cont})
        ev, landed = b.evidence("claim", src, structural,
                                   {"source_key": src.key, "structural_key": structural, "confidence_milli": 1000,
                                    "pass": "conflicts::duplicate_definitions", "fragment_kind": "create-table",
                                    "located_by": "claim path + subject table's structural key"})
        if new:
            b.place(cont, [meta, ev])
        elif landed:  # the claim's container holds [meta, evidence]; the moved evidence was detached
            b.acts.append({"type": "editElement", "element": b.root, "revision": b.root_rev, "op": {"type": "remove", "child": ev}})
            b.acts.append({"type": "editElement", "element": cont, "revision": b.cur.element_revision(cont),
                           "op": {"type": "splice", "index": "1", "child": ev}})
    subject = table_cell(p.get("subject_name", ""))
    link = b.id("link", "disputes")
    if b.born or link not in b.cur.links:
        b.acts.append({"type": "link", "link": link, "source": None,
                       "target": {"type": "document", "id": cells[subject]}, "relation": schema("relation/Disputes")})


def manifest_actions(b, plan, sources, cells):
    b.birth("ekos/manifest/v1")
    for s in sources:  # L-obj: a birth carries evidence; the manifest's is each source header
        tag = ("input", s.key, s.header_atom, s.doc.revision(s.header_atom))
        tr = b.id("transclusion", *tag)
        b.reads.add(s.cell)
        if b.born or tr not in b.cur.transclusions:
            b.acts.append({"type": "transclude", "transclusion": tr, "link": b.id("link", *tag),
                           "request": s.snapshot(s.header_atom, run=s.header_run)})
    for row in plan:
        if row["cell"] == "manifest":
            continue
        link = b.id("link", "entry", row["cell"])
        if b.born or link not in b.cur.links:
            b.acts.append({"type": "link", "link": link, "source": None,
                           "target": {"type": "external", "scheme": hexs("ekos-object"),
                                      "authority": hexs(row["node"] or row["cell"]), "path": hexs(cells[row["cell"]])},
                           "relation": schema("relation/manifest-entry")})


def cmd_compile(a):
    nodes, edges = load_export(a["export"])
    sources = sources_arg(a)
    cells = json.loads(pathlib.Path(a["cells"]).read_text())
    current = {}
    for spec in a.get("current", []):
        name, path = spec.split("=", 1)
        current[name] = Doc(path)
    ev = a.get("ekos-version", "unknown")
    plan = build_plan(nodes, sources)
    missing = [r["cell"] for r in plan if r["cell"] not in cells]
    if missing:
        raise SystemExit(f"cells not born yet: {missing} (run `plan` and have the owner create them)")
    out = pathlib.Path(a["out"]); out.mkdir(parents=True, exist_ok=True)
    tables = {n["n"]: n for n in nodes if n["kind"] == "Table"}
    allbytes, listing = b"", []
    for i, row in enumerate(plan):
        b = Builder(row["cell"], cells, current.get(row["cell"]))
        node = next((n for n in nodes if n["id"] == row["node"]), None)
        if row["schema"] == "ekos/object/v1":
            table_actions(b, node, sources, tables, edges, cells, ev)
        elif row["schema"] == "ekos/conflict/v1":
            conflict_actions(b, node, sources, cells, ev)
        else:
            manifest_actions(b, plan, sources, cells)
        if not b.acts:
            continue
        name = f"{i:02d}-{row['cell']}.json"
        data = write_req(out / name, invoke(row["cell"], b.acts, b.reads))
        allbytes += data
        listing.append({"file": name, "cell": row["cell"], "actions": len(b.acts), "reads": sorted(b.reads),
                        "transclusions": sum(1 for x in b.acts if x["type"] == "transclude"),
                        "births": sum(1 for x in b.acts if x["type"] == "createDocument")})
    digest = hashlib.sha256(allbytes).hexdigest()
    (out / "commands.sha256").write_text(digest + "\n")
    (out / "commands.json").write_text(json.dumps({"sha256": digest, "requests": listing,
                                                    "inputs": {s.key: {"cell": s.cell, "header": s.header_atom,
                                                                       "header_revision": s.doc.revision(s.header_atom),
                                                                       "statements": {k: [aid, s.doc.revision(aid)] for k, aid in s.order}}
                                                               for s in sources}}, indent=1, sort_keys=True) + "\n")
    print(f"{len(listing)} request(s), sha256 {digest}")


# ------------------------------------------------------------------ run record, attestation, review


def cmd_runrec(a):
    sources = sources_arg(a)
    d = pathlib.Path(a["dir"])
    meta = json.loads((d / "commands.json").read_text())
    cur = Doc(a["read"]) if a.get("read") else None
    b = Builder(a["cell"], {}, cur)
    b.birth("ekos/compile-run/v1")
    k = meta["sha256"]
    cont, rec, run = b.id("element", "run", k), b.id("atom", "run", k), b.id("run", "run", k)
    b.acts.append({"type": "createContainer", "element": cont})
    b.acts.append({"type": "createAtom", "atom": rec, "kind": obj_kind("ekos/compile-run/v1"),
                   "payload": hexs(canon({"commands_sha256": k, "mapper": MAPPER_VERSION,
                                          "mapper_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
                                          "ekos": a.get("ekos-version", "unknown"), "inputs": meta["inputs"],
                                          "outputs": [r["cell"] for r in meta["requests"]]}))})
    b.acts.append({"type": "createRun", "run": run, "atoms": [rec]})
    kids = [rec]
    for s in sources:
        tr = b.id("transclusion", "input", k, s.key)
        b.reads.add(s.cell)
        b.acts.append({"type": "transclude", "transclusion": tr, "link": b.id("link", "input", k, s.key),
                       "request": s.snapshot(s.header_atom, run=s.header_run)})
        kids.append(tr)
    b.place(cont, kids)
    write_req(a["out"], invoke(a["cell"], b.acts, b.reads))
    print(f"compile-run record {rec} for {k}")


def cmd_attest(a):
    run_doc = Doc(a["compile-run"])
    recs = [x for x in run_doc.atoms.values() if x.get("kind") == obj_kind("ekos/compile-run/v1")]
    want = a["claimed"]
    rec = next((x for x in recs if json.loads(bytes.fromhex(x["payload"]))["commands_sha256"] == want), None)
    if rec is None:
        raise SystemExit(f"no compile-run record with commands_sha256 {want}")
    run = num("run", a["source-cell"], "run", want)
    cur = Doc(a["read"]) if a.get("read") else None
    b = Builder(a["cell"], {}, cur)
    b.birth("ekos/replay-attestation/v1")
    cont, atom = b.id("element", "attest", want), b.id("atom", "attest", want)
    tr, link = b.id("transclusion", "attest", want), b.id("link", "attest", want)
    b.acts.append({"type": "createContainer", "element": cont})
    b.acts.append({"type": "createAtom", "atom": atom, "kind": obj_kind("ekos/replay-attestation/v1"),
                   "payload": hexs(canon({"claimed_commands_sha256": want, "replayed_commands_sha256": a["replayed"],
                                          "match": want == a["replayed"], "liveness": "replayedDeterministic" if want == a["replayed"] else "reconstructedApproximate",
                                          "replayer": a.get("replayer", "verifier")}))})
    b.acts.append({"type": "transclude", "transclusion": tr, "link": link,
                   "request": {"source": run_doc.target,
                               "range": {"start": {"run": run, "neighbor": rec["id"], "bias": "before", "death": DEATH},
                                         "finish": {"run": run, "neighbor": rec["id"], "bias": "after", "death": DEATH}},
                               "mode": "snapshot", "pins": [{"atom": rec["id"], "revision": str(rec["revision"])}]}})
    b.place(cont, [atom, tr])
    write_req(a["out"], invoke(a["cell"], b.acts, [a["source-cell"]]))
    print(f"attestation: match={want == a['replayed']}")


def cmd_review(a):
    cf = Doc(a["conflict"])
    cname = a["conflict-cell"]
    header, run = num("atom", cname, "header"), num("run", cname, "header")
    cur = Doc(a["read"]) if a.get("read") else None
    b = Builder(a["cell"], {}, cur)
    b.birth("ekos/review/v1")
    rev = cf.revision(header)
    tag = ("decision", cname, header, rev)
    cont, atom = b.id("element", *tag), b.id("atom", *tag)
    tr, link = b.id("transclusion", *tag), b.id("link", *tag)
    b.acts.append({"type": "createContainer", "element": cont})
    b.acts.append({"type": "createAtom", "atom": atom, "kind": obj_kind("ekos/decision/v1"),
                   "payload": hexs(canon({"verb": a.get("verb", "resolve"), "pick": a["pick"], "note": a.get("note", ""),
                                          "conflict_cell": cname}))})
    b.acts.append({"type": "transclude", "transclusion": tr, "link": link,
                   "request": {"source": cf.target,
                               "range": {"start": {"run": run, "neighbor": header, "bias": "before", "death": DEATH},
                                         "finish": {"run": run, "neighbor": header, "bias": "after", "death": DEATH}},
                               "mode": "snapshot", "pins": [{"atom": header, "revision": rev}]}})
    b.place(cont, [atom, tr])
    write_req(a["out"], invoke(a["cell"], b.acts, [cname]))
    print(f"decision {atom} on {cname} header at revision {rev}")


# ------------------------------------------------------------------ main


def parse(argv):
    out, i = {}, 0
    while i < len(argv):
        k = argv[i].lstrip("-")
        v = argv[i + 1]
        if k in ("source", "current"):
            out.setdefault(k, []).append(v)
        else:
            out[k] = v
        i += 2
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd, rest = sys.argv[1], sys.argv[2:]
    if cmd == "split":
        for k, t in split(pathlib.Path(rest[0]).read_bytes().decode()):
            print(f"{k}\t{len(t.encode())}\t{t.splitlines()[0][:60]!r}")
        return
    a = parse(rest)
    {"import": cmd_import, "render": cmd_render, "plan": cmd_plan, "compile": cmd_compile,
     "runrec": cmd_runrec, "attest": cmd_attest, "review": cmd_review}[cmd](a)


if __name__ == "__main__":
    main()
