# The VerEKOS parity board (M0.5)

Generated 2026-10-19T19:15:32Z by `tools/scoreboard/board.py` from the committed control and classification files. Hand edits are overwritten on the next render.

- EKOS pin: `8e3c178fc45741c7e2b1576e936646e0c461e75c` (tree `8719103d4703b3b43f8294497fa446f7320d7362`), control manifest `sha256:7f17636b0eca…`
- Panels: 3 measured rows, 8 placeholder rows
- Counts are agree / classified / unexplained. Agree with the control is not correctness: EKOS can be wrong (see classified ekos_defect rows). Classified differences are not hidden; they are counted.

| Kernel | Panel | Items | Agree | Classified (E / V / N) | Unexplained | Assurance | Scope: what this panel measures | Does NOT measure |
|---|---|---|---|---|---|---|---|---|
| Scope | `scope.decision` | 59 | 59 | 0 / 0 / 0 | 0 (law: 0) | design target | ReadScope parsing (parse vs rule refusals), the visibility decision `Compiled::visible` on (id, origins) inputs, `is_unrestricted`, and the sources×paths `origins` crossing — the decision-test families of ekos/crates/ledger/src/scope.rs, answered by EKOS's own functions on 59 items from 17 tests. | anything inside a store (the ScopedStore wrappers: filtered reads, both-ends relationships, evidence gating, counts, diff, search, write refusal — that is the scope.store panel); MCP/CLI scope enforcement end to end (the RFC 0181 leak suite needs the fixture pipeline, no control exists yet); the scope fingerprint's equality behaviour across scope changes. |
| Conflicts | `conflicts.unit` | 16 | 16 | 0 / 0 / 0 | 0 (law: 0) | design target | the detectors `duplicate_definitions`, `merge_losses`, `label_mismatches` and `normalize_type` (ekos/crates/semantic/src/conflicts.rs): type-alias normalization, duplicate collapse (incl. silent and per-attribute), permutation-invariance with stable conflict ids/claims/signature, exact vs fuzzy merge losses, label mismatch exclusion rules — 16 items from 8 tests. | the conflicts review workflow (`resolve`, `carry_forward`, `column_links` — reviewing, not detecting); conflict persistence (EKOS prints conflicts, it does not store them); fixture-scale conflict finding (conflicts.ledgersmb needs the LedgerSMB demo pipeline, not built). |
| Scope | `scope.store` | 8 | 8 | 0 / 0 / 0 | 0 (law: 0) | design target | ScopedStore — the RFC 0181 store wrapper — over a real (temp SQLite) Ledger built through ekos_ledger's public API: the eight store tests of scope.rs:1041 on as ordered step scenarios — filtered object/relationship/history/at/fact/audit reads, both-ends relationship visibility, evidence gating through visible objects, search and retrieval filtering, scoped counts and diff, write/event/vacuum refusal, multi-scope intersection and set_scopes replacement. | the MCP/CLI surface over a compiled project (the read_scope.rs leak suite: marker words through every tool shape, the result cache, --read-scope flag and process scope) — that needs the fixture pipeline (run_fixture.py), not built; the every_store_method_has_a_decision_here meta-test (source inspection, nothing to replay); scale (the world is four objects). |
| Branch | `branch.unit` (panel exists (panels/branch/, lane W6); no control in controls/ yet — the merge_stores/merge_branch dump is not built) | 3 | — | — | — | design target | (planned) merge_stores vs the kernel on object additions, property divergence and no-ops with fixed re-keyed ids; main's version never overwritten. | removed-in-branch objects (EKOS never looks for absences); three-way merges; evidence copied into main; persisted conflicts. |
| Identity | `identity.unit` (panel exists (panels/identity/, lane W3); no control in controls/ yet — the DefaultResolver::resolve dump is not built) | 58 | — | — | — | design target | (planned) DefaultResolver::resolve merge groups, conflict groups and pending-edge sets on named objects with assigned ids. | confidence floats beyond 1e-6 tolerance; overlay-versus-re-key choices (design §7); fixtures-scale resolve. |
| Ledger | `ledger.ecommerce / ledger.northwind` (no panel; needs run_fixture.py (the fixture→workspace→graph pipeline) and the ledger dump) | — | — | — | — | design target | (planned) current (id, content_signature) sets, object_at cuts, diff touched ids, re-commit append-only behaviour. | events (no lister exists, §2.4); unreferenced evidence; entry rowids and written_at volatility. |
| Impact | `impact.ecommerce / impact.northwind` (no panel; needs the fixture pipeline and the impact dump) | — | — | — | — | design target | (planned) trace_impact hop lists both directions, hops 1..5, confirmed-edge exclusion of pending SameAs. | search-quality aspects of dependents ranking. |
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

## Not measured

- search relevance (BM25/vector quality) — design §4 lists it as not measured
- model-pass quality (evals/datasets agent+retrieval runners) — LLM-dependent, not a kernel input
- SQL/parser coverage breadth — parsing is untrusted per design §2.2
- Events — no control available in M0.5 (no lister; §2.4)
