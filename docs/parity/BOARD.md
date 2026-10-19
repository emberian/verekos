# The VerEKOS parity board (M0.5)

Generated 2026-10-19T19:56:03Z by `tools/scoreboard/board.py` from the committed control and classification files. Hand edits are overwritten on the next render.

- EKOS pin: `8e3c178fc45741c7e2b1576e936646e0c461e75c` (tree `8719103d4703b3b43f8294497fa446f7320d7362`), control manifest `sha256:b4425855fdd8…`
- Panels: 6 rows with an item-keyed control, 5 rows with inputs but no item-keyed control, 2 placeholder rows (no panel yet)
- Counts are agree / classified / unexplained. Agree with the control is not correctness: EKOS can be wrong (see classified ekos_defect rows). Classified differences are not hidden; they are counted.
- No VerEKOS candidate is scored yet. Until one is, the Agree column is the control scored against itself (exploration 03 §3.5-1): it shows the diff code runs, nothing more. The column that measures something today is **Test asserts**: EKOS's own function, run on the transcribed input, reproduced what the Rust test asserts (from the last `regen_controls.py` run recorded in controls/MANIFEST.json).

| Kernel | Panel | Items | Test asserts | Agree | Classified (E / V / N) | Unexplained | Assurance | Scope: what this panel measures | Does NOT measure |
|---|---|---|---|---|---|---|---|---|---|
| Scope | `scope.decision` | 59 | 59 / 59 | 59 | 0 / 0 / 0 | 0 (law: 0) | design target | ReadScope parsing (parse vs rule refusals), the visibility decision `Compiled::visible` on (id, origins) inputs, `is_unrestricted`, and the sources×paths `origins` crossing — the decision-test families of ekos/crates/ledger/src/scope.rs, answered by EKOS's own functions on 59 items from 17 tests. | anything inside a store (the ScopedStore wrappers: filtered reads, both-ends relationships, evidence gating, counts, diff, search, write refusal — that is the scope.store panel); MCP/CLI scope enforcement end to end (the RFC 0181 leak suite needs the fixture pipeline, no control exists yet); the scope fingerprint's equality behaviour across scope changes. |
| Conflicts | `conflicts.unit` | 16 | 16 / 16 | 16 | 0 / 0 / 0 | 0 (law: 0) | design target | the detectors `duplicate_definitions`, `merge_losses`, `label_mismatches` and `normalize_type` (ekos/crates/semantic/src/conflicts.rs): type-alias normalization, duplicate collapse (incl. silent and per-attribute), permutation-invariance with stable conflict ids/claims/signature, exact vs fuzzy merge losses, label mismatch exclusion rules — 16 items from 8 tests. | the conflicts review workflow (`resolve`, `carry_forward`, `column_links` — reviewing, not detecting); conflict persistence (EKOS prints conflicts, it does not store them); fixture-scale conflict finding (conflicts.ledgersmb needs the LedgerSMB demo pipeline, not built). |
| Scope | `scope.store` | 8 | 8 / 8 | 8 | 0 / 0 / 0 | 0 (law: 0) | design target | ScopedStore — the RFC 0181 store wrapper — over a real (temp SQLite) Ledger built through ekos_ledger's public API: the eight store tests of scope.rs:1041 on as ordered step scenarios — filtered object/relationship/history/at/fact/audit reads, both-ends relationship visibility, evidence gating through visible objects, search and retrieval filtering, scoped counts and diff, write/event/vacuum refusal, multi-scope intersection and set_scopes replacement. | the MCP/CLI surface over a compiled project (the read_scope.rs leak suite: marker words through every tool shape, the result cache, --read-scope flag and process scope) — that needs the fixture pipeline (run_fixture.py), not built; the every_store_method_has_a_decision_here meta-test (source inspection, nothing to replay); scale (the world is four objects). |
| Ledger | `ledger.ecommerce` | 1 | — | — | — | — | design target | the six-stage ekos pipeline (init, build, recover, resolve, compile, commit --yes) on ecommerce.sql through the release binary in a scratch workspace: the graph export ndjson (8 nodes — 2 File plus exactly the 6 Tables the integration test counts — and 6 ForeignKey edges), the EKL object and relationship rows sorted by id, status and conflicts json, pinned by a sidecar (binary sha256, EKOS commit, fixture sha256, per-stage timings); plus the versions control (controls/ledger.ecommerce.versions.control.jsonl): per object (sorted by id) the id, kind, name, version count (object_history length), a locally recomputed content signature per version (content_signature is pub(crate); created_at stripped here, hashed by ekos_artifact's own ArtifactId::compute — with a no-evidence variant that isolates EKOS#10) and every version's evidence id list, the workspace totals, and diff(epoch, now) as a sorted id list; two signature self-checks (adjacent versions must differ; get_object must equal the last history version) falsify a wrong recomputation | relationship version history (only its count in totals — objects only; the EKOS#10 fork's relationship half is inferred from entry arithmetic, not pinned per relationship); events and session objects; edge properties (a pending SameAs is still invisible); object properties beyond what the signature hash covers; the MySQL/docs/git fixtures (not run); the ledger's own byte layout (the control pins logical content, not segment bytes) |
| Ledger | `ledger.northwind` | 1 | — | — | — | — | design target | the six-stage ekos pipeline (init, build, recover, resolve, compile, commit --yes) on northwind.sql through the release binary in a scratch workspace: the graph export ndjson (15 nodes — 2 File plus the 13 real Tables the integration test counts — and 13 ForeignKey edges), the EKL object and relationship rows sorted by id, status and conflicts json, pinned by a sidecar (binary sha256, EKOS commit, fixture sha256, per-stage timings); plus the versions control (controls/ledger.northwind.versions.control.jsonl): per object (sorted by id) the id, kind, name, version count (object_history length), a locally recomputed content signature per version (content_signature is pub(crate); created_at stripped here, hashed by ekos_artifact's own ArtifactId::compute — with a no-evidence variant that isolates EKOS#10) and every version's evidence id list, the workspace totals, and diff(epoch, now) as a sorted id list; two signature self-checks (adjacent versions must differ; get_object must equal the last history version) falsify a wrong recomputation | relationship version history (only its count in totals — objects only; the EKOS#10 fork's relationship half is inferred from entry arithmetic, not pinned per relationship); events and session objects; edge properties (a pending SameAs is still invisible); object properties beyond what the signature hash covers; the MySQL/docs/git fixtures (not run); the ledger's own byte layout (the control pins logical content, not segment bytes) |
| Identity | `identity.unit` | 58 | 58 / 58 | 58 | 0 / 0 / 0 | 0 (law: 0) | design target | DefaultResolver::resolve on named objects (ekos/crates/identity/src/lib.rs): merge proposals as member sets with exact_name_match and confidence, SameNameDifferentKind conflict groups against the five expected-coexistence narrowings, structurally-keyed Custom-kind exclusion through the ekos_kir::custom_kinds registry, and the name_for_similarity rules (Table schema qualifier, GitHub owner/repo#n prefix) — 58 items from 45 tests. | the structural_score columns/rows signals on their own (four not-transcribed test families, a future structural-score panel); the stats/threshold/serde API tests; every_pipeline_custom_kind_is_registered (walks the EKOS source tree, no object inputs); merge execution (resolve proposes, the ledger merges — that is branch.unit); fixtures-scale resolve. |
| Branch | `branch.unit` | 3 | 3 / 3 | 3 | 0 / 0 / 0 | 0 (law: 0) | design target | merge_branch over two real temp SQLite ledgers (ekos/crates/ledger/src/lib.rs:1621): clean additions from branch, content-signature no-ops for identical objects (created_at stripped before hashing), and same-id diverged objects recorded as conflicts rather than overwritten — 3 items from the 3 merge_branch tests. | relationship merging (no transcribed test appends a relationship, so that half of merge_branch is unmeasured); objects removed in branch (EKOS never looks for absences); three-way merges; evidence propagation into main; persisted conflicts (the report only, EKOS does not store them). |
| Impact | `impact.unit` | 26 | 26 / 26 | 26 | 0 / 0 / 0 | 0 (law: 0) | design target | the Runtime graph walks (ekos/crates/runtime/src/lib.rs) over a real temp SQLite ledger: load_neighborhood and load_neighborhood_bounded (truncation reporting, no dangling edges after a cut), trace_impact both directions with kind filters and hop bounds, dependents()/related(), the pending-review exclusion (unconfirmed SameAs), the RFC 0151 session-memory exclusions, and the RFC 0144 doc-mention rule — 26 items from 15 tests. | named_graph_ops_respect_direction_edge_kind_and_hops and the kind-prefilter test (not walk-shaped items); the relationship-read session filters outside these walks (session_edges_are_absent_from_every_relationship_read_path); search-quality aspects of dependents ranking; fixture-scale graphs (needs run_fixture.py). |
| Redact | `redact.unit` | 26 | no control yet | — | — | — | design target | (when the dump exists) redact / redact_json / is_excluded_path from ekos/crates/common/src/redaction.rs on the inputs of its own 16 unit tests, including extra patterns and excluded globs. | policy completeness: a secret of a shape the pattern table does not name is not caught and will not be claimed (design §10); planted fixture strings (not transcribed); the two readers that skip redaction (EKOS#18, #19) are entry-point defects, not redact-function inputs. |
| EKL | `ekl.parser` | 50 | no control yet | — | — | — | design target | (when the dump exists) the EKL parser on the query strings of its own tests: AST fields the tests assert (entity, predicates, returns, order, limit, AS OF, GROUP BY, SEMANTIC) or the error kind. | AST fields a test does not assert (only asserted fields are in the expected file); the fuzz test (asserts only no panic); REASON/Datalog. |
| EKL | `ekl.interpreter` | 33 | no control yet | — | — | — | design target | (when the dump exists) the EKL interpreter over each test's own small world: rows, counts, groups, UnknownField refusals. | three AS OF tests with no fixed timestamp (not reproducible as data); queries against fixture-scale ledgers (the real `ekos ekl --json` binary over run_fixture.py workspaces is the planned second family); SEMANTIC retrieval quality. |
| Time | `time.ecommerce` (no panel) | — | — | — | — | — | design target | (planned) as-of cuts with relationship validity windows stated separately from domain time. | domain time semantics beyond the stored windows. |
| Fusion | `fusion.unit` (no panel) | — | — | — | — | — | design target | (planned) rrf_fuse ranked-list fusion, order-sensitive. | retrieval relevance (the retrieval_eval harness is search quality, not a Fusion panel). |

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

Placeholder: controls committed and wired into regen_controls.py's LEDGER_REGISTRY (W20): the ledger dump opens the workspace's fact store READ-ONLY (.ekos/ledger/facts) and regen runs it twice byte-identically against the committed control like every other entry; no expected file — the workspace is the expectation source, and the EKOS#10 fork away from this control is classified ekos_defect in controls/classified.jsonl (diff_id 07e3cb27…).

Classification manifest entries on record for this panel that no difference of this run matched (they belong to other recorded runs):

- `ecommerce` — **ekos_defect** — EKOS#10 (https://github.com/alexeyban/EKOS/issues/10), observed: a pass re-run forced by a cache miss on an unchanged workspace forks a version of every Table object. The reproduction (var/w20/ecommerce, a copy of W18’s workspace; sources byte-identical, fixture sha256 accad143… matches the panel before and after) ran `ekos clean` — which empties .ekos/artifacts including the pass-manifests that key pass-cache validity (compiler-core/src/cache.rs should_recompute: no manifest ⇒ recompute) but leaves .ekos/ledger untouched (cli/src/commands/clean.rs) — then recover/resolve/compile/commit again. All 6 Tables went 1→2 versions, entries 28→52, evidence 14→26; the 2 File objects stayed at 1. The exact field that changed is each object’s evidence id list (KirEvidence::new mints uuid v4), which sits inside content_signature: customers v1 evidence [a5e8f77f-1616-48fb-a0b6-0cb3f2a00714] → v2 [11ce6850-e338-40a7-a571-130614cb6d16], version_signatures moved on every table while version_signatures_no_evidence stayed byte-equal — the evidence list is the only payload change. The control snapshot is the before-dump; the committed control remains the untouched W18 workspace’s. (`diff_id 07e3cb2755d7…, signed: W20 lane (EKOS#10 reproduction on the var/w20 copy of W18’s ecommerce workspace))

### `ledger.northwind`

Placeholder: controls committed and wired into regen_controls.py's LEDGER_REGISTRY (W20): the ledger dump opens the workspace's fact store READ-ONLY (.ekos/ledger/facts) and regen runs it twice byte-identically against the committed control like every other entry; no expected file — the workspace is the expectation source, and the EKOS#10 fork away from this control is classified ekos_defect in controls/classified.jsonl (diff_id 07e3cb27…).

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

### `redact.unit`

Placeholder: panel and expected outcomes committed (W15: 26 items from 16 tests); no control dump subcommand yet, so EKOS's own answers have not been recorded.

No classified differences on record.

### `ekl.parser`

Placeholder: panel and expected outcomes committed (W16: 50 items from 26 parser tests); no control dump subcommand yet.

No classified differences on record.

### `ekl.interpreter`

Placeholder: panel and expected outcomes committed (W16: 33 items from 32 interpreter tests); no control dump subcommand yet.

No classified differences on record.

## Assurance labels

From `panels/LABELS.json`, the one copy of these definitions. A label describes the kernel's claim, never the panel result.

| Label | Meaning |
|---|---|
| `design target` | no theorem about this kernel yet; the row exists to say the panel is measured by the control only |
| `executable property` | a property checked by running a Lean definition on the panel (#eval or a compiled reader), with no theorem behind it |
| `conditional` | a Lean theorem about the kernel with an explicit premise (for example injective ids, or a coverage premise), and the panel is scored by running that same definition |
| `proved` | a Lean theorem about the kernel with no premise beyond the model's own definitions, and the panel is scored by running that same definition (hash-tied to the build) |
| `cross-language` | the claim crosses a seam the theorem does not cover: the Lean model on one side, a deployed minidregg host or a non-Lean reader on the other |

## Not measured

- search relevance (BM25/vector quality) — design §10 will not claim it
- model-pass quality (evals/datasets agent+retrieval runners) — LLM-dependent, not a kernel input
- SQL/parser coverage breadth — parsing is untrusted (design §4, §10)
- Events — no control available in M0.5 (no lister; exploration 03 §2.4)
