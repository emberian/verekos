# Exploration 03: the VerEKOS scoreboard (M0.5)

Design lane, 2026-10-19. Read-only except this file. Nothing here is built; every path marked "new" is a proposal.

**Summary**
1. EKOS's shipped bulk dump (`ekos graph export --format ndjson`) carries nodes and edges only: no relationship ids, no edge properties (so no `status`, so a pending `SameAs` looks like a fact), no evidence, no versions, no events. It is a control for ids and kinds, not for the ledger.
2. So the control is two things: the real `ekos` binary for what it prints, plus a small Rust `scoreboard-dump` binary (new, path deps on a pinned EKOS checkout) that calls the library functions behind each kernel and writes one JSONL per kernel.
3. Panels come from three places: fixtures run through the real pipeline (ledger, impact, time, EKL), EKOS unit tests transcribed by hand with a drift checker (branch, scope, identity, conflicts), and `evals/datasets` (not kernels; reported only as "not measured").
4. The diff is per kernel and set-based on a stable key plus a content signature; every difference lands in one of three classes and is recorded in a signed manifest keyed by the difference's hash, so it never counts as unexplained twice.
5. The board is one Markdown table with columns for panel, items, agree, classified, unexplained, assurance label, and a mandatory "does not measure" cell.
6. First checkpoint: for every panel, `score --control` against itself gives 0 unexplained, and a second run of EKOS on the same fixture reproduces the control byte-for-byte after volatile fields are stripped (or the non-reproducible fields are named).

---

## 0. What I read, and what I could not verify

Read in full or in the cited ranges: design §2.2/§4/§6, `notes/E-veri7vn-lessons.md`, `project/PLAN.md`, veri7vn's `tools/parity/{score,harness}.py` heads, `docs/parity/{README,BOARD}.md` heads, `docs/contracts/answerer.md`, EKOS `graph.rs` (all 361 lines), `runtime/src/graph_export.rs` (the export function and wire types), the audit/status code in `ledger.rs`, the `tool_*` MCP functions, `branch.rs`, and the test regions named in the brief.

Not verified:
- I did not run `ekos`. Whether a second run of the pipeline on `ecommerce.sql` gives byte-identical object ids is read, not measured: `table_kir_id` and `foreign_key_kir_id` are UUIDv5 over names (`ekos/crates/recovery/src/sql_analyzer.rs:303,316`), evidence ids are `KirId::new()` (`kir/src/lib.rs`, `KirEvidence::new`, line 363ff; filed upstream as EKOS#10 item 1). Ids of other recovered kinds are unchecked.
- I did not check whether `append_object` in `merge_stores` also writes the object's evidence into `main` (it appends only the object: `ledger/src/lib.rs:1905-1913`). The Branch panel must ask; I am not claiming a defect.
- Whether `Compiled` (`ledger/src/scope.rs:133`) and `semantic::conflicts::*` are reachable from an outside crate: `pub mod scope` (`ledger/src/lib.rs:7`) and `pub mod conflicts` (`semantic/src/lib.rs:8`) are public, but I did not check every type signature for `pub(crate)` leaks (`content_signature` is `pub(crate)`, `lib.rs:47`; see 2.3).
- I did not open `evals/datasets/{architecture,code,history,lineage,security,adversarial}.yaml` beyond the README and `dependencies.yaml`.

---

## 1. Panels

### 1.1 Ground rule: a panel item is an input and nothing else

A panel item never contains the control's answer. Inputs live in `panels/`, control outputs in `controls/` (§5), so a kernel binary can be run on the panel without ever seeing EKOS's output. This is veri7vn's split between `upstream/root/specialists/*/` panels and the scorers' reference answers, and its first lesson (E rule 1).

### 1.2 Common JSONL envelope

One file per (kernel, panel); one JSON object per line. Every item has:

```
{"panel":"ledger.ecommerce","item":"obj-000017","origin":"fixture|test|eval","source":"<where the input came from>","input":{...}}
```

`origin` is how the item was produced. `source` is exact: a fixture path plus its sha256, or `crate/path.rs:fn_name`. `item` is a stable id inside the panel (never a UUID that EKOS generated at random).

### 1.3 Fixtures: the exact command sequence (route (a))

Fixtures: `/Users/ember/dev/EKOS/tests/fixtures/{ecommerce.sql (70 lines), northwind.sql (174), mysql_hash_comments.sql (224)}`, `sample_project/src/{lib.rs,main.rs}`, `git_fixture/odoo_utm.bundle`, `sample_docs/{README.md,runbook.md}`.

The routine to reuse is the one the leak suite uses, `ekos/crates/cli/tests/read_scope.rs:80-165` (`project()`): an isolated `EKOS_HOME`, `project add <name> --source name=dir --detect`, then the five stages. It scrubs `EKOS_PROJECT/TENANT/CONFIG/WORKSPACE/READ_SCOPE` (`read_scope.rs:40-52`); the scoreboard driver must do the same. Sequence (new script `tools/scoreboard/run_fixture.py`):

```
export EKOS_HOME=$SCRATCH/home            # fresh per run; never ~/.ekos
cp -R <fixture dir> $SCRATCH/src/<name>   # sources are never written to, but copy anyway for the hash
ekos project add <name> --source <name>=$SCRATCH/src/<name> --detect
for s in build recover resolve compile; do ekos --project <name> $s; done
ekos --project <name> commit --yes
ekos --project <name> graph export --format ndjson --max-nodes 1000000 --max-edges 1000000 \
     --first-seen --output $SCRATCH/graph.ndjson
```

Notes. (i) The graph defaults cap at 5,000 nodes and 20,000 edges (`graph_export.rs:38-39`); the header's `truncated` field says if the cap bit, and the driver must fail when it is true. (ii) For `ecommerce.sql` the integration test expects exactly six tables (`tests/integration/tests/integration.rs:64`); that count is the first panel number. (iii) `northwind.sql` has "13 real tables" (`integration.rs:102`). (iv) For `git_fixture`, the bundle must be cloned to a directory first; I did not check how `integration.rs` does it. (v) `demo/ledgersmb-linkml` takes about 10 minutes and ~11k objects (its README); it is panel `conflicts.ledgersmb` and `ledger.ledgersmb`, built once per control version, not on every score run, and pinned to LedgerSMB commit `544bcd947` as the demo pins it.

### 1.4 What the `ecommerce.sql` control dump will contain, and will not

From `graph_export.rs:191-229` (wire types) and `:395-470` (builder):

Contains:
- header line: `schema_version`, `workspace`, `generated_at`, `level`, `as_of`, `id_space:"kir"`, `counts`, `truncated`, `filters`, `kind_index`, `rel_kind_index`;
- one node per object: `id` (UUID), `n` name, `k` index into `kind_index`, `d` degree, `fs` first-seen if asked;
- one edge per relationship: `s`,`t` indexes into the node list, `k` index into `rel_kind_index`, `fs`.

Does NOT contain (each is a reason the dump is not a sufficient control):
- **Relationship ids.** `Edge` has only `source,target,kind,weight,first_seen` (`graph_export.rs:216-229`). Two foreign keys between the same two tables (the very case `foreign_key_kir_id` exists for, `sql_analyzer.rs:316`) are indistinguishable except by position; the `Branch`/`Ledger` kernels key relationships by id.
- **Edge properties, including `status`.** Pending-review edges (`is_pending_review`, `kir/src/lib.rs:480`) are exported as ordinary edges. The Identity and Impact panels depend on exactly that bit.
- **Object properties**, unless `--include-properties <key>` names them one by one (`graph_export.rs:394-399`). `columns`, `check_constraints`, `sources` must be requested by name; a content signature cannot be rebuilt from this.
- **Evidence.** Neither `Node` nor `Edge` has an evidence field, and `evidence_is_ignored_by_the_export` (`graph_export.rs:945-956`) pins that a stray evidence record changes nothing. `KirObject.evidence: Vec<KirId>` (`kir/src/lib.rs:200`) is dropped.
- **Versions.** The export is "current" or `all_objects_at(at)` (`graph_export.rs:238-243`): one version per id. No history.
- **Events.** Not read at all.
- **Session objects**, deliberately dropped (`graph_export.rs:244-259`).
- `created_at` (only as `fs`, "an upper bound" for objects that changed, per the option's doc, `graph_export.rs:~96-100`).
- Truncation by degree order if the cap bites (`selection:"degree_desc"`).

Consequence: `graph export` is the control for the *id/kind/name/degree graph* only (Ledger-current, Impact on confirmed edges, Time `--as-of` cuts of the same). Everything else needs the dump binary (§2.2).

### 1.5 Per-kernel panels

#### Ledger (fixtures)
Inputs: the fixture directories (§1.3). Items are not "objects"; an item is a *question to the kernel*, so the kernel binary can be driven without parsing SQL (SQL parsing is untrusted per design §2.2). Two item kinds:

```
{"panel":"ledger.ecommerce","item":"log","kind":"log","input":{"entries":[
   {"txid":1,"entry":"object","id":"<uuid>","payload":{...KirObject...}} ... ]}}
{"panel":"ledger.ecommerce","item":"at-0007","kind":"object_at","input":{"id":"<uuid>","at":"2026-10-19T00:00:00Z"}}
{"panel":"ledger.ecommerce","item":"diff-03","kind":"diff","input":{"from":"...","to":"..."}}
```
The `log` item is produced by the dump binary (§2.2: `scoreboard-dump ledger-log`) from the ledger EKOS built, so the log is EKOS's own typed output for the untrusted front end. The queries (`at`, `from`, `to`) are chosen by the panel generator from the `created_at` times present, plus the boundary cases: exactly at a `created_at`, one nanosecond before, before everything, after everything.

Re-commit panel (the append-only claim): run `commit --yes` twice and add the second `entry_count`. EKOS's claim is that identical content appends nothing (`content_signature`, `ledger/src/lib.rs:47`, strips `created_at`). Because evidence ids are random, the claim holds for objects only if evidence ids do not enter the signature; `KirObject.evidence` does enter the payload, so the expected truth may be that a second build forks every object. This is EKOS#10 item 1; the panel records what EKOS does and labels it.

#### Branch (unit tests as data, plus fixtures)
Tests: `ledger/src/lib.rs:2861-2910`: `merge_branch_adds_new_objects_from_branch`, `merge_branch_flags_diverged_objects_as_conflicts`, `merge_branch_is_noop_for_identical_objects`. Their inputs use `KirObject::new` (random id, `Utc::now()`), so they cannot be read out as constants. Panel items are the *shape*, re-instantiated with fixed ids:

```
{"panel":"branch.unit","item":"adds-new","origin":"test","source":"ledger/src/lib.rs:2861 merge_branch_adds_new_objects_from_branch",
 "input":{"main":[{"id":"00000000-0000-5000-8000-000000000001","name":"customers","kind":"Table","properties":{}}],
          "branch":[{"id":"00000000-0000-5000-8000-000000000002","name":"orders","kind":"Table","properties":{}}]}}
```
plus items for relationships (the unit tests cover objects only; `merge_stores` does relationships too, `lib.rs:1914-1933`), plus a generated family: for each ecommerce table, branch = main + one property edited, branch = main + one table added, branch = main with a relationship removed (removed ones are not seen: the merge reads the branch's current set and never looks for absences). `merge_stores` (`lib.rs:1900`) is the one to mirror, not the SQLite-only `merge_branch` (`lib.rs:1621`); `branch.rs:merge` calls `merge_stores`.

#### Scope (unit tests as data; the leak suite's inputs)
Strong candidate for exact extraction: the scope unit tests take a JSON scope string and a list of `Origin` pairs and assert a boolean (`scope.rs:794-1040`, e.g. `deny_wins_over_allow_whatever_the_order`, `an_object_in_two_sources_needs_both`, `a_star_stays_in_one_component_and_two_cross_them`). Item:

```
{"panel":"scope.decision","item":"two-sources-need-both","origin":"test","source":"ledger/src/scope.rs:891",
 "input":{"scope":{"default":"deny","rules":[{"effect":"allow","source":"api"},{"effect":"allow","source":"web"}]},
          "id":"<uuid>","origins":[{"source":"api","path":"x"},{"source":"web","path":"x"}]}}
```
Control output: `{"visible":true}`. Parse-error items are also panel items (`a_scope_without_a_default_does_not_parse`, `scope.rs:812`): the control is `{"error":"parse"}`.

Second family, the leak suite (`cli/tests/read_scope.rs`): the fixture workspace is built by `project()` (`:80-165`, two sources `api` and `handbook`, `secrets/**` and `hr/**` hidden), scopes `deny_directories()` and `api_only()` (`:169-186`). Panel: for each scope, the set of object ids visible. Control: `ScopedStore` over the real ledger (§2.2), cross-checked with the MCP `_meta["ekos/readScope"]` route that the suite uses. Marker words (`SECRET_DIR_MARKERS`, `read_scope.rs:15-26`) become the "disabled filter is caught" control (§3.5).

#### Identity (unit tests as data)
Tests from `identity/src/lib.rs:854` on: the `exact_name_match_*` family (`:958-1060`), the "never merged" kind family (`:1670-1840`), conflict exclusions (`:1137-1460`). Inputs are named objects with a kind and a name; `DefaultResolver::resolve(&KirGraph)` (`:99`) returns `ResolutionResult{proposals,conflicts,stats}`. Panel item = a list of `{id,name,kind,properties}` with *assigned* ids; expected = merge groups (set of id sets, with `exact_name_match`) and conflict groups. Also: every ecommerce/northwind/mysql fixture table list, since those are what `resolve` runs on. I did not verify the full test builder helpers; hand-transcription is required.

#### Conflicts (unit tests as data)
Best-shaped of all: tests use deterministic ids (`kid("t:orders")`, `conflicts.rs:~51`: UUIDv5 over a key) and a pure function `duplicate_definitions(&mut KirGraph) -> KirGraph` (`:294`). Tests at `conflicts.rs:649-948`, notably `detection_is_independent_of_input_order_and_ids_are_stable` (`:745`), which compares ids, `claims`, `signature` under reversed input. Items: a list of `(table name, source path, columns JSON, check_constraints)` tuples, like the test helper `table(name, path, cols, checks)` (`:620-630`). Expected: the set of conflict objects, each `(subject id, attribute, claims, chosen)`. Panel includes a *permuted* copy of every item so the kernel's permutation-invariance is measured, not asserted.

#### Impact (fixtures)
Inputs: the graph from the fixture (as a typed graph, taken from the dump binary, not the SQL), a seed id, direction, kinds, `max_hops`. Control: `Runtime::trace_impact(&id, direction, &kinds, max_hops)` (`runtime/src/lib.rs:244`), printed in the MCP shape of `tool_impact` (`mcp.rs:1973-2020`: `hops[{hop,id,name,kind,via}]`). Unit-test shapes to transcribe: `trace_impact_*` tests, `runtime/src/lib.rs:1102-1310` (`excludes_unconfirmed_same_as_but_keeps_confirmed`, `skips_doc_mention_edges`, `handles_cycles`, `max_hops_bounds_traversal`). Also `tool_dependents` (`mcp.rs:1934`) for the one-hop view. Seeds: every object in ecommerce/northwind, both directions, hops 1..5 (cheap, exhaustive).

#### EKL (fixtures and evals)
Inputs: a query string and the graph. Control: `ekos ekl "<query>" --json` (`commands/ekl.rs:9,41`, prints `result.rows` as a JSON array). Panel queries: a generated grid over the grammar (`FIND Object WHERE kind = 'Table'`, `ORDER BY`, `GROUP BY`, `COUNT`, `AS OF <ts>`, unknown field => `UnknownField`, RFC 0175), plus the query strings in the EKL parser/interpreter tests (not read by me; to be listed by the lane). REASON/Datalog rules are out of scope for M0.5.

#### Time (fixtures)
Same as Ledger `at` items plus relationship validity windows (`valid_from`/`valid_until`, `kir/src/lib.rs:392-396`): `relationships_at` (`ledger/src/lib.rs:1704`) versus domain-time. Panel items state both cuts so conflation is visible.

#### Fusion (unit tests as data)
`rrf_fuse(lists, k, limit)` (`ledger/src/retrieval.rs:211`). Items: ranked lists of ids per source, `k`, `limit`. I did not read its tests; the lane lists them. The retrieval harness (`runtime/src/retrieval_eval.rs`: `seed_reference_estate`, ~30 objects, graded queries) is a relevance harness and is **not** a Fusion panel: it measures search quality, which design §4 lists as "not measured".

#### Redact (unit tests as data)
`ekos_common::redaction::{redact, redact_json, is_excluded_path}` (`common/src/redaction.rs:226,247,310`). Items: `{text, config}` -> redacted text; `{path}` -> excluded bool. Inputs: the patterns' own unit tests (not read; lane lists them) plus planted strings in the fixtures.

### 1.6 Eval datasets (route (c))

`evals/datasets/*.yaml`: a scenario is `{id, question, mode, expected_query_type, expected_facts[], difficulty}` (`dependencies.yaml`), and the runner is an LLM-or-retrieval pipeline (`evals/README.md`: `agent_runner`, `retrieval_runner`, six evaluators). These are not kernel inputs: their answers depend on model calls and BM25/vector scores, both untrusted in design §2.2. Use them for exactly one thing: the `dependencies.yaml` and `lineage.yaml` `expected_facts` become **Impact oracle checks** ("`recovery` is among the dependents of `redact`") on the EKOS repo's own ledger, as a smoke test that the Impact panel generator is not vacuous. Everything else is listed on the board as not measured.

---

## 2. The control

### 2.1 What gets pinned

Recorded in one file per control set, `controls/MANIFEST.json` (new), written by the control command and committed:

```
{"ekos":{"repo":"/Users/ember/dev/EKOS","commit":"<git rev-parse HEAD>","dirty":false},
 "ekos_binary":{"path":"...","sha256":"..."},
 "dump_binary":{"path":"...","sha256":"...","source_tree_sha256":"..."},
 "fixtures":{"ecommerce.sql":"<sha256>", "...":"..."},
 "panels":{"ledger.ecommerce.jsonl":"<sha256>", "...":"..."},
 "controls":{"ledger.ecommerce.control.jsonl":"<sha256>", "...":"..."},
 "volatile_fields_stripped":["generated_at","workspace","created_at","written_at","evidence_id"],
 "recorded":"2026-10-19T..Z"}
```
The EKOS commit at the time of this note is `8e3c178` (from the session's git status). The control command refuses a dirty EKOS tree. Rule 7: a score line always prints the control manifest's sha256 and the binary's generated-SML sha1 (§5.3); a score without both is not a score.

### 2.2 `scoreboard-dump` (new)

A Rust binary; a separate Cargo workspace (like `tests/integration/Cargo.toml`, which uses `ekos = { path = "../../ekos/crates/cli" }`, `ekos-ledger`, `ekos-runtime`, etc.). Location: I recommend `/Users/ember/dev/verekos/tools/scoreboard/control-dump/` with path deps into the pinned EKOS checkout, because (a) this lane may not edit EKOS, (b) the control must be tied to a commit, and (c) a dump binary inside EKOS would be changed by EKOS's own churn. Open question for ember: upstream it later as `tests/scoreboard-dump/` once stable. Rule: it only reads; it opens stores with `open_store_read_only` semantics (`commands/store.rs`, used at `graph.rs:181`) and, for unit-test-shaped panels, builds in-memory/temp stores.

Module layout and the real function each calls:

| Module (new) | Subcommand | Calls | Writes |
|---|---|---|---|
| `ledger.rs` | `ledger-log <ws>` | `KnowledgeStore::all_objects`, `all_relationships`, `object_history`, `relationship_history` (`ledger/src/lib.rs:1700-1721`), `get_evidence`, `get_event`; `audit_trail` (`:1693`) | `ledger.log.jsonl`: every version, every evidence reachable from an object's `evidence` list |
| `ledger.rs` | `ledger-at <ws> <panel>` | `object_at` (`:1703`), `all_objects_at`/`all_relationships_at` (`:1711,1714`), `relationships_at` (`:1704`), `diff` (`:1759`) | answers per query item |
| `branch.rs` | `branch <panel>` | build two temp `FactLedger`s (`ekos_ledger::FactLedger`, as `branch.rs:12` does), `merge_stores` (`:1900`); also `merge_branch` on SQLite `Ledger` (`:1621`) | `MergeReport{objects_merged,relationships_merged,conflicts[{object_id,reason}]}` plus the post-merge state of `main` |
| `scope.rs` | `scope <panel>` | `ReadScope::from_json` (`scope.rs:94`), `Compiled::new` (`:153`), `Compiled::visible` (`:239`), `origins` (`:290`); and `ScopedStore::new/with_scopes/set_scopes` (`:333-351`) over a real ledger for the leak family | `{"visible":bool}` or `{"error":"parse"}`; visible-id sets |
| `identity.rs` | `identity <panel>` | `DefaultResolver::new().resolve(&KirGraph)` (`identity/src/lib.rs`), `with_threshold`/`with_kind_threshold` | `ResolutionResult` normalized to sorted merge groups + conflicts |
| `conflicts.rs` | `conflicts <panel>` | `ekos_semantic::conflicts::{duplicate_definitions, merge_losses, label_mismatches, normalize_type}` (`:294,329,379,62`) | conflict objects: `(id, attribute, claims, chosen, signature)` |
| `impact.rs` | `impact <ws>` | `Runtime::trace_impact` (`runtime/src/lib.rs:244`), `relationships_for` + `is_pending_review` for the one-hop view | hop lists |
| `ekl.rs` | none: use the real `ekos ekl --json` | | |
| `fusion.rs` | `fusion <panel>` | `ekos_ledger::retrieval::rrf_fuse` (`retrieval.rs:211`) | ranked ids |
| `redact.rs` | `redact <panel>` | `ekos_common::redaction::{redact, redact_json, is_excluded_path}` | strings, bools |
| `signature.rs` | (helper) | **needs a decision**: `content_signature` is `pub(crate)` (`lib.rs:47`) | see below |

`content_signature` problem: the Ledger and Branch kernels compare by it. I cannot call it from outside. Options, in order of preference: (1) recompute it in the dump from the documented definition, SHA-256 of canonical JSON minus `created_at` via `ArtifactId::compute` (`ekos-artifact`), and verify against a ledger's stored `content_sig` for every entry in the fixture (a self-check the dump runs on startup); (2) ask upstream to export it. Do (1) now; it adds a drift check for free.

### 2.3 What stays as the real binary

`ekos graph export --format ndjson [--as-of]`, `ekos ekl --json`, `ekos ledger audit <id> --json` (`ledger.rs:594`: `writes[]` with `written_at`, `run_id`, `stage`, `source_artifact_id`), `ekos ledger status --json` (`entries, objects, relationships, evidence`, `ledger.rs:160-243`; useful as the counts panel), `ekos ledger timeline --json`, `ekos branch merge` (prints counts and conflicts; it is human text, `branch.rs:84-95`, so the dump binary is the machine control and the CLI text is checked once by hand). MCP: `ekos_state` (`mcp.rs:1900`), `ekos_dependents` (`:1934`), `ekos_impact` (`:1973`), `ekos_diff` (`:2116`), `ekos_graph_export` (`:2022`) exist as JSON shapes if a stdio server is preferred; I recommend the library calls, since an MCP result cache keyed by scope is itself another thing to trust.

### 2.4 Where each dump path stops (honest list)

- Evidence: no CLI lists evidence. `evidence_count` only (`ledger/src/lib.rs:1754`). The dump walks `object.evidence`/`relationship.evidence` ids and calls `get_evidence` (`:1697`); evidence not referenced by anything is invisible. Events: only `get_event(id)` (`:1699`), no listing; so event ids must come from an audit trail or the segment files. Treat Events as *no control available* until the lane finds a lister. State that on the board.
- Versions: `object_history` (`:1718`) is on the trait; no CLI wraps it. `ekos ledger audit` gives write rows, not signatures.

---

## 3. The diff classifier

### 3.1 The law

Zero **unexplained** differences, per panel. A difference is a (panel, item, field) triple where the kernel output and the control disagree after normalization (3.3). Agree + classified + unexplained = items.

### 3.2 Per-kernel diff

| Kernel | Compared as | Order | Normalized away |
|---|---|---|---|
| Ledger | set of `(id, content_signature)` of current objects and relationships; `object_at`: `(id, signature)` or absent; `diff`: set of touched ids | insensitive | `created_at`, entry rowids, `written_at` |
| Branch | `MergeReport` counts + set of conflict ids + final state set of `(id, signature)` of main | insensitive | `reason` text equality is compared exactly (it is two fixed strings, `lib.rs:1924,1932`) |
| Scope | boolean per item; visible-id set per scope | set | none |
| Identity | set of merge groups, each as a sorted id set + `exact_name_match`; set of pending-edge pairs; set of conflict groups | insensitive within, set across | `confidence` float: compared with tolerance 1e-6 and listed separately (`f32` in EKOS) |
| Conflicts | set of `(subject, attribute, sorted claims, chosen)`; conflict-object id | claims by canonical order | none |
| Impact | set of `(hop, id, via-kind)`; hop number is compared (BFS depth) | insensitive | the ordering of equal-hop rows |
| EKL | multiset of rows (JSON values) | insensitive unless the query has `ORDER BY` | none |
| Time | as Ledger | | |
| Fusion | ranked id list, exact order | sensitive | none |
| Redact | exact string | | none |

Do not compare by id alone where the id is random (evidence, anything `KirObject::new`); compare by `(location, fragment)` multiset.

### 3.3 The three classes

Every difference gets exactly one:

| Class | Meaning | Required evidence |
|---|---|---|
| `EKOS-DEFECT` | EKOS's output contradicts a stated EKOS invariant or its own doc | the counterexample (panel item + both outputs) and an upstream issue link (the existing ones: `notes/upstream-issues.md`, EKOS#10-#20) |
| `VEREKOS-DEFECT` | the kernel binary is wrong | a failing item and a ticket; counts as a failure of the scoreboard run, not a classification you can sign off |
| `NON-GOAL` | the difference is by design of VerEKOS | a reference to a design section (§7 "will not claim", or a stated overlay-versus-re-key choice for Identity) |

Only `EKOS-DEFECT` and `NON-GOAL` may be signed off. A `VEREKOS-DEFECT` row stays red until fixed. That is the "0 wrong" analogue.

### 3.4 How a classification is recorded

`panels/classified/<kernel>.manifest.jsonl` (new), append-only, one line per classified difference:

```
{"diff_id":"sha256(panel|item|field|control_value|kernel_value)","panel":"identity.unit","item":"...",
 "field":"groups","class":"EKOS-DEFECT","ref":"EKOS#16","note":"...","control_sha":"<manifest sha256>",
 "kernel_sha1":"<generated SML sha1>","signed":"ember","date":"2026-10-.."}
```
The scorer recomputes `diff_id` for every difference; a line whose `diff_id` matches classifies it. Change the control, the kernel value, or the item and the hash changes, the entry no longer matches, and the difference counts as unexplained again until re-signed. This is the property veri7vn gets from its parked manifests (hash-tied, E rule 15) and from "a later edit never inherits an earlier score" (E §1). `signed` is a human name; a lane may propose entries but the scorer rejects an entry with `signed` empty. A report states the manifest sha256 too.

### 3.5 Controls on the scoreboard itself (the thing that makes the numbers count)

The leak suite's own lesson (`read_scope.rs:1-10`): "the same calls without a scope must show the markers, otherwise a fixture that never produced them would pass every assertion". The scoreboard therefore ships three self-checks that run before any kernel score is reported:
1. **Positive control**: the control compared with itself gives 0 unexplained and N agree (proves the diff code runs).
2. **Planted defect**: a deliberately broken stand-in kernel (`tools/scoreboard/standins/`, new: e.g. a Scope that ignores `deny`, a Branch that overwrites) must produce at least one unexplained difference on every panel it should. If a mutant scores clean, the panel is too weak and is reported as such. Reference: veri7vn counts the "false yes" for the same reason.
3. **Control reproducibility**: run the control command twice on one fixture; strip the volatile fields; byte-identical, or the diverging fields are listed (expected: evidence ids; `workspace`; `generated_at`). Whatever diverges can never be a compared field.

### 3.6 Assurance label column

One of the five labels from the hyperdreggmedia audit, per board row: `proved`, `conditional`, `executable property`, `cross-language`, `design target`. Assignment rules:
- `design target`: no theory yet; the row exists to say the panel is measured by the control only (every row at M0.5 is this).
- `executable property`: a HOL/QuickCheck-style property, no theorem.
- `conditional`: theorem with an explicit premise (e.g. coverage premise; E rule 3).
- `proved`: theorem on the HOL function, unconditional, and the exported ML is hash-tied to the session receipt.
- `cross-language`: the claim crosses the Lean/Isabelle seam (design §3).
The label describes the kernel's *claim*, never the panel result; a panel can be 100/100 and still `design target`. I did not have the hyperdreggmedia audit's wording in front of me; the lane should copy the labels' definitions verbatim from it into `docs/parity/README.md` (new).

---

## 4. The board

`docs/parity/BOARD.md` (new), generated by `tools/scoreboard/board.py` (new), never hand-edited, modelled on `/Users/ember/dev/o7vn/docs/parity/BOARD.md` (header block, then a Summary table, then one section per run).

Header (generated): date UTC, EKOS commit, control manifest sha256, number of panels, and the standing sentence: "Counts are agree / classified / unexplained. Agree with the control is not correctness: EKOS can be wrong (see classified EKOS-DEFECT rows). Classified differences are not hidden; they are counted."

Summary table:

| Kernel | Panel | Items | Agree | Classified (E / V / N) | Unexplained | Assurance | Scope: what this panel measures | Does NOT measure |
|---|---|---|---|---|---|---|---|---|

Worked example, placeholders where unmeasured:

| Kernel | Panel | Items | Agree | Classified (E / V / N) | Unexplained | Assurance | Scope: what this panel measures | Does NOT measure |
|---|---|---|---|---|---|---|---|---|
| Branch | `branch.unit` (3 EKOS tests re-keyed with fixed ids + 24 generated) | 27 | `<n>` | `<e>` / `<v>` / `<n>` | `<u>` (law: 0) | design target | `merge_stores` vs the kernel on object additions, property divergence and no-ops, on `ecommerce.sql` tables; main's version never overwritten | removed-in-branch objects (EKOS never looks for absences); three-way merges (RFC 0011 is last-write divergence only); evidence copied into main (control does not list it); persisted conflicts (EKOS prints them, does not store them) |

Rules for the last two columns (veri7vn rule 14): both are mandatory, the generator fails if either is empty, and every `unexplained` cell links to the list of its differences. Per-row detail sections list each classified difference with its class, reference and the manifest line. A final section "Not measured" repeats design §4: search relevance, model-pass quality, parser coverage, and in addition Events (no control available, §2.4) and anything the dump cannot see.

---

## 5. Layout and commands

### 5.1 Directory layout (all new)

```
/Users/ember/dev/verekos/
  panels/
    README.md                      # what a panel is; the envelope; the five labels
    ledger.ecommerce.jsonl         # inputs only
    ledger.northwind.jsonl
    branch.unit.jsonl
    scope.decision.jsonl
    scope.leak.jsonl
    identity.unit.jsonl  identity.fixtures.jsonl
    conflicts.unit.jsonl conflicts.ledgersmb.jsonl
    impact.ecommerce.jsonl impact.northwind.jsonl
    ekl.grid.jsonl
    time.ecommerce.jsonl
    fusion.unit.jsonl
    redact.unit.jsonl
    transcribed/                   # hand-transcribed test data + drift checker (5.4)
      branch_tests.py  scope_tests.py  identity_tests.py  conflicts_tests.py  tables_check.py
    classified/                    # signed manifests (3.4)
      <kernel>.manifest.jsonl
  controls/
    MANIFEST.json                  # 2.1
    <panel>.control.jsonl          # EKOS output on each panel
    raw/                           # raw ekos graph export ndjson, as produced, for audit
  tools/scoreboard/
    run_fixture.py                 # 1.3: fixture -> workspace -> graph.ndjson
    make_panels.py                 # fixture+dump -> panels/*.jsonl (generated families)
    control-dump/                  # Rust: Cargo.toml (path deps into EKOS), src/{main,ledger,branch,scope,identity,conflicts,impact,fusion,redact,signature}.rs
    score.py                       # 5.3
    classify.py                    # diff + manifest lookup (3.2-3.4)
    board.py                       # BOARD.md generator
    standins/                      # planted-defect kernels (3.5)
    tests/                         # unittest, no EKOS needed (as tests/parity in veri7vn)
  docs/parity/{README.md,BOARD.md}
```
Runtime scratch (workspaces, EKOS_HOME) goes in `var/scoreboard/` (new, git-ignored), following veri7vn's `var/parity/`. Generated artifacts stay out of git except `controls/` and `panels/` (small).

### 5.2 The one command that regenerates controls

```
python3 tools/scoreboard/regen_controls.py --ekos /Users/ember/dev/EKOS [--only ledger,scope] [--ledgersmb]
```
Does: require a clean EKOS tree; record commit; build `ekos` and `scoreboard-dump` (the one place a cargo build happens; run through the shared build lock, `swarm-build` on hbox); hash binaries and fixtures; run `run_fixture.py` per fixture; run the dump per kernel; write `controls/*` and `MANIFEST.json`; run the reproducibility self-check (3.5-3). Refuses to overwrite a committed control whose manifest differs unless `--accept` and prints the diff of control sha256s.

### 5.3 The one command that scores a kernel binary

```
python3 tools/scoreboard/score.py --kernel ledger --binary <path/to/ledger_kernel> [--panel ledger.ecommerce]
```
The kernel binary contract (borrowed from `docs/contracts/answerer.md` of veri7vn, newly defined here): reads a panel JSONL on stdin, one line in, one line out, same order; `{"item":..., "output":{...}}`; flushes after every reply; exits on EOF; anything else on stderr; an `error` field counts as an unexplained difference, not a skip. Also supports `--selftest` printing its identity:
```
{"kernel":"ledger","sml_sha1":"<sha1 of generated ML>","theory":"Ledger_Export","oracles":0}
```
Tying to inputs (E rule 7): `score.py` records in each verdict file `{binary_sha256, sml_sha1 (from --selftest), panel_sha256, control_manifest_sha256, ekos_commit}`. The SML sha1 is printed by the export theory exactly as `Relation_Reader_Export.thy` does (`/Users/ember/dev/o7vn/src/isabelle/reader/Relation_Reader_Export.thy:13-29`: `Code_Target.produce_code`, then the hash). A verdict whose `sml_sha1` does not equal the current generated ML is stale, and `board.py` shows it as such. Verdict files: `var/scoreboard/<run>/<panel>.json` (written last, resumable per panel as `harness.py` does).

### 5.4 Hand transcription with a drift checker, or something better

Rust test bodies are not data; transcribing them is a copy that can rot. Options:
1. **Hand transcription + drift checker** (veri7vn's `tables_check.py`, E rule 9). The checker (a) greps the cited test function by name in the pinned EKOS checkout, (b) fails if the function is missing or if its source text hash differs from the hash stored with the transcription. It does not prove the transcription equals the test, only that the test has not changed since a human did it. Cheap, honest about what it checks.
2. **Instrument the tests**: a small patch to the tests to write their inputs to JSONL. Better fidelity, but requires editing EKOS (forbidden to this lane) and the tests use random ids anyway.
3. **Do both for the highest-value ones**: transcribe, and *also* make the dump binary run the transcribed item against the real function, so a transcription error shows up as the control disagreeing with the test's own assertion. That check is the real value: every transcribed test also carries `expect_from_test` (the assertion the Rust test makes, e.g. `report.objects_merged == 1`). The dump run must reproduce it. If not, the transcription is wrong or EKOS drifted, and the checker says which.

Recommendation: 1 plus the `expect_from_test` check of 3. This is the "something better" and costs one extra field per item.

---

## 6. Order of work for the M0.5 lane

1. **Skeleton and self-checks, no EKOS yet.** Envelope, `score.py`, `classify.py`, `board.py`, unit tests with fake controls, the planted-defect machinery. Checkpoint: the board renders from fake data with all columns.
2. **Pin the control.** Build `ekos` at the recorded commit, `MANIFEST.json`, `run_fixture.py` on `ecommerce.sql` only. Run it twice. Checkpoint (first measurable): both runs give 6 `Table` nodes (the integration test's claim) and the strip-volatile-fields reproducibility report; write down which ids are stable (tables, FKs expected stable; evidence not).
3. **`scoreboard-dump` for Ledger and Impact** over the same workspace; `ledger-log` with evidence walk; prove the `content_signature` recomputation matches the ledger's stored `content_sig` for every entry. Checkpoint: dump counts equal `ekos ledger status --json` counts (`entries, objects, relationships, evidence`).
4. **Scope panels** (cleanest data): transcribe `scope.rs` decision tests with `expect_from_test`; run through the dump; then the leak-suite family. Checkpoint: dump reproduces every transcribed assertion; the "disabled filter is caught" mutant (3.5-2) is caught.
5. **Conflicts, Identity, Branch** transcription with the drift checker; `expect_from_test` reproduction for each.
6. **Time, EKL, Fusion, Redact** panels; fixtures `northwind`, `mysql_hash_comments`, `sample_project`, `sample_docs`, then LedgerSMB once.
7. **First BOARD.md** with every row `design target`. Classify what already differs between `graph export` and the dump (e.g. the edge-property gap of §1.4 is a documentation of the *control path's* limits, not a difference to classify; keep that in README).

### 6.1 "EKOS's own numbers reproduced on every panel" means

Not that a kernel exists. It means, for every panel in the Summary table:
- (a) the control's own count equals EKOS's own stated number where one exists: 6 tables for `ecommerce.sql` and 13 for `northwind.sql` (`integration.rs:64,102`), the entry/object/relationship/evidence counts from `ledger status --json`, the 21 confirmed/47 concepts/222 coded values for LedgerSMB (demo README) and the 3 `merge_branch_*` assertions, the 26 scope decisions' assertions, the identity and conflicts tests' assertions (via `expect_from_test`);
- (b) a second run of EKOS on the same input reproduces the control after named volatile fields are removed;
- (c) the scorer run with the control as the "kernel" gives 0 unexplained and the planted-defect stand-in gives more than 0.

Where EKOS publishes no number (Events, unreferenced evidence, anything under `evals` that needs a model), the board says "no control" and the panel is not counted as reproduced.

---

## 7. Questions for ember

1. Dump binary location: in VerEKOS (recommended) or upstreamed into EKOS's `tests/`?
2. May `content_signature` be exported upstream, or do we keep the recomputed copy and its self-check?
3. Is `Events` allowed to stay "no control" for M0.5?
4. Should the control also run on the SQLite backend? EKOS default for new workspaces is the fact engine (CLAUDE.md, RFC 0016), and `merge_branch` is SQLite-only while `merge_stores` is both; a Branch panel on one backend measures one backend.
