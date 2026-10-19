# The VerEKOS parity board (M0.5)

Generated 2026-10-19T19:34:49Z by `tools/scoreboard/board.py` from the committed control and classification files. Hand edits are overwritten on the next render.

- EKOS pin: `8e3c178fc45741c7e2b1576e936646e0c461e75c` (tree `8719103d4703b3b43f8294497fa446f7320d7362`), control manifest `sha256:1c1ea3ff394a…`
- Panels: 8 measured rows, 4 placeholder rows
- Counts are agree / classified / unexplained. Agree with the control is not correctness: EKOS can be wrong (see classified ekos_defect rows). Classified differences are not hidden; they are counted.

| Kernel | Panel | Items | Agree | Classified (E / V / N) | Unexplained | Assurance | Scope: what this panel measures | Does NOT measure |
|---|---|---|---|---|---|---|---|---|
| Scope | `scope.decision` | 59 | 59 | 0 / 0 / 0 | 0 (law: 0) | design target | ReadScope parsing (parse vs rule refusals), the visibility decision `Compiled::visible` on (id, origins) inputs, `is_unrestricted`, and the sources×paths `origins` crossing — the decision-test families of ekos/crates/ledger/src/scope.rs, answered by EKOS's own functions on 59 items from 17 tests. | anything inside a store (the ScopedStore wrappers: filtered reads, both-ends relationships, evidence gating, counts, diff, search, write refusal — that is the scope.store panel); MCP/CLI scope enforcement end to end (the RFC 0181 leak suite needs the fixture pipeline, no control exists yet); the scope fingerprint's equality behaviour across scope changes. |
| Conflicts | `conflicts.unit` | 16 | 16 | 0 / 0 / 0 | 0 (law: 0) | design target | the detectors `duplicate_definitions`, `merge_losses`, `label_mismatches` and `normalize_type` (ekos/crates/semantic/src/conflicts.rs): type-alias normalization, duplicate collapse (incl. silent and per-attribute), permutation-invariance with stable conflict ids/claims/signature, exact vs fuzzy merge losses, label mismatch exclusion rules — 16 items from 8 tests. | the conflicts review workflow (`resolve`, `carry_forward`, `column_links` — reviewing, not detecting); conflict persistence (EKOS prints conflicts, it does not store them); fixture-scale conflict finding (conflicts.ledgersmb needs the LedgerSMB demo pipeline, not built). |
| Scope | `scope.store` | 8 | 8 | 0 / 0 / 0 | 0 (law: 0) | design target | ScopedStore — the RFC 0181 store wrapper — over a real (temp SQLite) Ledger built through ekos_ledger's public API: the eight store tests of scope.rs:1041 on as ordered step scenarios — filtered object/relationship/history/at/fact/audit reads, both-ends relationship visibility, evidence gating through visible objects, search and retrieval filtering, scoped counts and diff, write/event/vacuum refusal, multi-scope intersection and set_scopes replacement. | the MCP/CLI surface over a compiled project (the read_scope.rs leak suite: marker words through every tool shape, the result cache, --read-scope flag and process scope) — that needs the fixture pipeline (run_fixture.py), not built; the every_store_method_has_a_decision_here meta-test (source inspection, nothing to replay); scale (the world is four objects). |
| Ledger | `ledger.ecommerce` | — | — | — | — | design target | the six-stage ekos pipeline (init, build, recover, resolve, compile, commit --yes) on ecommerce.sql through the release binary in a scratch workspace: the control is the graph export ndjson (8 nodes — 2 File plus exactly the 6 Tables the integration test counts — and 6 ForeignKey edges), the EKL object and relationship rows sorted by id, status and conflicts json (0 conflicts), pinned by a sidecar (binary sha256, EKOS commit 8e3c178, fixture sha256, per-stage timings); a second fresh-workspace run reproduced ids and content identically, differing only in named volatile fields. | evidence and its randomly-minted v4 ids (EKOS#10 — no evidence field in the export, none in the EKL default returns; the 14 evidence entries appear as a count in status only); relationship ids and edge properties in the export (edges are s/t node indexes; the EKL rows carry ids but no status, so a pending SameAs is invisible); object properties (columns, check_constraints, sources — the export drops them unless named one by one); versions/history, events and session objects; content signatures (pub(crate) in EKOS — the control-dump's job); the re-commit append-only claim (needs a second commit on the same workspace); mysql_hash_comments, sample_project, sample_docs and git_fixture (not run in W18). |
| Ledger | `ledger.northwind` | — | — | — | — | design target | the six-stage ekos pipeline on northwind.sql through the release binary in a scratch workspace: the control is the graph export ndjson (15 nodes — 2 File plus the 13 real Tables the integration test counts — and 13 ForeignKey edges), the EKL object and relationship rows sorted by id, status json (56 entries, 28 evidence) and conflicts json (0 conflicts), pinned by the same sidecar shape as ledger.ecommerce. | everything listed for ledger.ecommerce (same control shapes, same blind spots — evidence ids, relationship ids in the export, edge properties, object properties, versions, events, content signatures, the re-commit claim); reproducibility was measured on ecommerce only (W18 ran northwind once). |
| Identity | `identity.unit` | 58 | 58 | 0 / 0 / 0 | 0 (law: 0) | design target | DefaultResolver::resolve on named objects (ekos/crates/identity/src/lib.rs): merge proposals as member sets with exact_name_match and confidence, SameNameDifferentKind conflict groups against the five expected-coexistence narrowings, structurally-keyed Custom-kind exclusion through the ekos_kir::custom_kinds registry, and the name_for_similarity rules (Table schema qualifier, GitHub owner/repo#n prefix) — 58 items from 45 tests. | the structural_score columns/rows signals on their own (four not-transcribed test families, a future structural-score panel); the stats/threshold/serde API tests; every_pipeline_custom_kind_is_registered (walks the EKOS source tree, no object inputs); merge execution (resolve proposes, the ledger merges — that is branch.unit); fixtures-scale resolve. |
| Branch | `branch.unit` | 3 | 3 | 0 / 0 / 0 | 0 (law: 0) | design target | merge_branch over two real temp SQLite ledgers (ekos/crates/ledger/src/lib.rs:1621): clean additions from branch, content-signature no-ops for identical objects (created_at stripped before hashing), and same-id diverged objects recorded as conflicts rather than overwritten — 3 items from the 3 merge_branch tests. | relationship merging (no transcribed test appends a relationship, so that half of merge_branch is unmeasured); objects removed in branch (EKOS never looks for absences); three-way merges; evidence propagation into main; persisted conflicts (the report only, EKOS does not store them). |
| Impact | `impact.unit` | 26 | 26 | 0 / 0 / 0 | 0 (law: 0) | design target | the Runtime graph walks (ekos/crates/runtime/src/lib.rs) over a real temp SQLite ledger: load_neighborhood and load_neighborhood_bounded (truncation reporting, no dangling edges after a cut), trace_impact both directions with kind filters and hop bounds, dependents()/related(), the pending-review exclusion (unconfirmed SameAs), the RFC 0151 session-memory exclusions, and the RFC 0144 doc-mention rule — 26 items from 15 tests. | named_graph_ops_respect_direction_edge_kind_and_hops and the kind-prefilter test (not walk-shaped items); the relationship-read session filters outside these walks (session_edges_are_absent_from_every_relationship_read_path); search-quality aspects of dependents ranking; fixture-scale graphs (needs run_fixture.py). |
| Time | `time.ecommerce` (no panel) | — | — | — | — | design target | (planned) as-of cuts with relationship validity windows stated separately from domain time. | domain time semantics beyond the stored windows. |
| EKL | `ekl.grid` (no panel; the control is the real `ekos ekl --json` binary) | — | — | — | — | design target | (planned) query grid over the grammar plus the parser/interpreter tests' own queries. | REASON/Datalog rules (out of scope for M0.5). |
| Fusion | `fusion.unit` (no panel) | — | — | — | — | design target | (planned) rrf_fuse ranked-list fusion, order-sensitive. | retrieval relevance (the retrieval_eval harness is search quality, not a Fusion panel). |
| Redact | `redact.unit` (no panel) | — | — | — | — | design target | (planned) redact/redact_json/is_excluded_path on the patterns' own unit tests plus planted fixture strings. | policy completeness beyond the pinned pattern set. |

## Per-panel detail

### `scope.decision`

Self-score (the control is the candidate, §3.5-1) run at render time: 59 items, 59 agree, 0 mismatch, 0 missing, 0 extra, 0 unexplained.

Classification manifest entries on record for this panel that no difference of this run matched (they belong to other recorded runs):

- `default_deny_hides_everything_without_a_rule#1` — **non_goal** — score.py self-test (exploration 03 §3.5-2 planted defect): the candidate is a hand-altered scratch copy of the control in var/w9/score-selftest/, not a kernel output; the difference is by design of the self-test. (`diff_id fb449a0a76c1…, signed: W9 lane (self-test entry, not a kernel verdict))

### `conflicts.unit`

Self-score (the control is the candidate, §3.5-1) run at render time: 16 items, 16 agree, 0 mismatch, 0 missing, 0 extra, 0 unexplained.

No classified differences on record.

### `scope.store`

Self-score (the control is the candidate, §3.5-1) run at render time: 8 items, 8 agree, 0 mismatch, 0 missing, 0 extra, 0 unexplained.

No classified differences on record.

### `ledger.ecommerce`

Placeholder: controls committed (controls/ledger.ecommerce.{graph.ndjson,objects.jsonl,relationships.jsonl,status.json,conflicts.json,sidecar.json}) but not self-scored here: they are whole-fixture artifacts, not the item-keyed JSONL score.py's diff code consumes, and wiring them into regen_controls.py means either a control-dump subcommand (lane W12's tree) or a new fixture-runner entry kind — registration left to the root (notes/W18-fixture-pipeline.md).

No classified differences on record.

### `ledger.northwind`

Placeholder: controls committed (controls/ledger.northwind.{graph.ndjson,objects.jsonl,relationships.jsonl,status.json,conflicts.json,sidecar.json}) but not self-scored here: they are whole-fixture artifacts, not the item-keyed JSONL score.py's diff code consumes, and wiring them into regen_controls.py means either a control-dump subcommand (lane W12's tree) or a new fixture-runner entry kind — registration left to the root (notes/W18-fixture-pipeline.md).

No classified differences on record.

### `identity.unit`

Self-score (the control is the candidate, §3.5-1) run at render time: 58 items, 58 agree, 0 mismatch, 0 missing, 0 extra, 0 unexplained.

No classified differences on record.

### `branch.unit`

Self-score (the control is the candidate, §3.5-1) run at render time: 3 items, 3 agree, 0 mismatch, 0 missing, 0 extra, 0 unexplained.

No classified differences on record.

### `impact.unit`

Self-score (the control is the candidate, §3.5-1) run at render time: 26 items, 26 agree, 0 mismatch, 0 missing, 0 extra, 0 unexplained.

No classified differences on record.

## Not measured

- search relevance (BM25/vector quality) — design §4 lists it as not measured
- model-pass quality (evals/datasets agent+retrieval runners) — LLM-dependent, not a kernel input
- SQL/parser coverage breadth — parsing is untrusted per design §2.2
- Events — no control available in M0.5 (no lister; §2.4)
