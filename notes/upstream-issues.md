# Upstream issue drafts for alexeyban/EKOS

Drafted 2026-10-19 by the root after verifying each claim at the cited lines in
the checkout equal to upstream `main` (`8e3c178`). Scout memos A, D1 and F raised
them; nothing is filed on a scout's word alone. Items marked **filed** carry the
issue number once opened. Items from lane D2 are appended when it reports.

---

## 1. Evidence ids are random, so any pass re-run forks a new version of every object it touches

**Filed** 2026-10-19 as alexeyban/EKOS#10: https://github.com/alexeyban/EKOS/issues/10

**Where.** `ekos/crates/kir/src/lib.rs:364-372` (`KirEvidence::new` sets `id: KirId::new()`, a uuid v4); `ekos/crates/recovery/src/sql_analyzer.rs:503-510` (a fresh evidence id is hung on a table object whose own id is stable v5); `ekos/crates/ledger/src/lib.rs:47-53` (`content_signature` strips only `created_at`, so the object's `evidence` list is inside the signature); `ekos/crates/ledger/src/fact_ledger.rs:722-724` (a differing signature is a new version).

**What happens.** The SQL pass is cached per file by the SHA-256 of its text (`sql_analyzer.rs:151-156`; skip logic `compiler-core/src/pass.rs:241`). On a hit, evidence ids come back from the retained KIR artifact and nothing forks. On a miss (a pass version bump, a config-hash change, a fresh checkout of a workspace whose ledger lives in the EKOS home, or any edit to a file) the pass re-runs, every evidence record gets a new id, every object in that pass's output gets a new content signature, and the append-only ledger gains a version per object with no change in the source. The old evidence records are orphaned. RFC 0135 Part C audited relationship ids (the 15 production sites sampled all use v5) but evidence ids were outside its scope.

**Proposed change (M).** A `KirEvidence::deterministic(location, fragment)` that derives the id as uuid v5 of `(path, line, column, fragment)`, used by `sql_analyzer` and `source_evidence::attach`; extend the RFC 0135 guard to flag `KirEvidence::new` in production passes unless `ev.id` is reassigned; a test that two `parse_ddl_structural` calls over the same SQL give equal evidence ids and equal `content_signature`s for the objects.

**Why it matters for the product claim.** "Compiler passes are deterministic" and "the ledger is append-only" together make a non-deterministic id permanent.

---

## 2. `ekos_clickhouse_query` appends to the knowledge ledger

**Filed** 2026-10-19 as alexeyban/EKOS#11: https://github.com/alexeyban/EKOS/issues/11

**Where.** `ekos/crates/clickhouse-query/src/audit.rs:33-57` (`record_query_event` calls `append_evidence` and `append_event` on the `&dyn KnowledgeStore`); `ekos/crates/clickhouse-query/src/lib.rs:135` (called from the query path); the MCP tool shares `run_query` with the CLI and opens the normal writable store (`cli/src/commands/clickhouse.rs`, `store.rs::open_store`). The event id is `KirId::new()`, so each call is a new row for the same SQL.

**What the docs say.** `CLAUDE.md`: "Every other tool is read-only, going through `Runtime` only", naming only the two review tools and the session-note inbox as writers.

**Proposed change (S).** Either state the audit write in `CLAUDE.md` and RFC 0056 and give the event a deterministic id, or record query audits outside the knowledge ledger. Add an MCP dispatch test that the set of tools reaching an `append_*` is an explicit allowlist.

---

## 3. Compiled semantic edges and the rollup object are written with no evidence

**Filed** 2026-10-19 as alexeyban/EKOS#12: https://github.com/alexeyban/EKOS/issues/12

**Where.** `ekos/crates/semantic/src/transform_ir.rs:296-305` (`FeedsInto` via `KirRelationship::deterministic`, `evidence` left empty while the node just above pushes `evidence_id`); `ekos/crates/semantic/src/conflicts.rs:225-229` and `:480-488` (both `Disputes` constructors); `ekos/crates/semantic/src/business_semantics.rs:469-472` (`relate()` never sets evidence; callers emit `EvidencedBy`, `Describes`, `ConflictsWith`, `ExplainedBy`); `ekos/crates/semantic/src/lib.rs:393-394` (risk `References`); `ekos/crates/semantic/src/rollup.rs:187-196` (the rollup object gets no evidence; its member evidence is attached to the `Contains` edges with `SourceLocation::file(group_key)`, a group key rather than a file).

**What the docs say.** "Every semantic conclusion must be traceable to Evidence." `evidence: Vec<KirId>` is `#[serde(default)]`, so the empty vector is representable and nothing tests against it.

**Proposed change (M).** One helper that builds a deterministic edge and copies the subject's evidence ids (the pattern `python_analyzer.rs::merge_file_result` already uses for `DependsOn`/`Extends`); a semantic-crate test that every relationship and every `Custom` object a compile pass pushes has non-empty evidence.

---

## 4. The Runtime's read-only promise is a convention; split a read trait out of `KnowledgeStore`

**Filed** 2026-10-19 as alexeyban/EKOS#13: https://github.com/alexeyban/EKOS/issues/13

**Where.** `ekos/crates/ledger/src/lib.rs:1683-1687` (the trait starts with four `append_*` methods and `vacuum_into`); `ekos/crates/runtime/src/lib.rs:98-102` (`Runtime` holds `&dyn KnowledgeStore`). Every `append_*` call in the runtime crate is under `#[cfg(test)]` (`ai.rs:947`, `graph_export.rs:653`), so production code is read-only today, but nothing prevents the next method from writing, and no test pins it.

**Proposed change (S/M).** A `KnowledgeReader` trait holding the read methods, `KnowledgeStore: KnowledgeReader` adding the writes; `Runtime`, EKL, graph export, docs-gen and the MCP read tools take `&dyn KnowledgeReader`. Then "the Runtime is read-only" is a type, and the `ScopedStore` test `every_store_method_has_a_decision_here` can read the smaller trait.

---

## 5. The human-only guards are string-containment scans that a rename evades

**Filed** 2026-10-19 as alexeyban/EKOS#14: https://github.com/alexeyban/EKOS/issues/14

**Where.** `ekos/crates/cli/src/commands/conflicts.rs:780-790` (`!mcp.contains("conflicts::resolve")`, `!mcp.contains("Resolution::")`); the same shape in `semantics.rs:1682`, `session.rs:591`, `migrate.rs:3393`. `use conflicts::resolve as settle;` passes all four.

**Proposed change (S).** Keep the scans (they catch omission) and add a structural guard: a `#[cfg(test)]` build of `mcp.rs` against a `ledger` feature that removes the review functions, or a `Reviewer` capability type with a private constructor the MCP module cannot name. Alternatively a scan that resolves `use` lines before matching.

---

## 6. RFC 0007 no longer describes the shipped identity algorithm

**Filed** 2026-10-19 as alexeyban/EKOS#15: https://github.com/alexeyban/EKOS/issues/15

**Where.** `docs/rfcs/0007-identity-resolution.md:57` ("structural_score = 1.0 if same ObjectKind else 0.0") vs `ekos/crates/identity/src/lib.rs:655-675` (column-name Jaccard, then row-token Jaccard, with 1.0 as the fallback when both exist and have no structural signal); `:71` ("Default: 0.85") vs `identity/src/lib.rs:133` (`DEFAULT_MERGE_THRESHOLD = 0.90`) and `:112` (`CONCEPT_MERGE_THRESHOLD = 0.95`); `:26` ("All KirObjects … become candidates") vs `identity/src/lib.rs:490-500` (structurally keyed kinds and short concept names excluded, RFC 0135 Part D).

**Proposed change (S).** An amendment section in RFC 0007 pointing at RFC 0060/0135 and restating the shipped scoring and gates, so a reader of the RFC index is not misled.

---

## 7. `ekos_identity_review` also confirms `AuthorizedBy`, and a review decision carries no evidence or actor

**Filed** 2026-10-19 as alexeyban/EKOS#16: https://github.com/alexeyban/EKOS/issues/16

**Where.** `ekos/crates/cli/src/commands/mcp.rs:2289-2296` (kind check accepts `SameAs` or `AuthorizedBy`; the tool description at `:1389` says so); `CLAUDE.md` describes the tool as `Custom("SameAs")` only; RFC 0032 intended the widening. Both review handlers append an event with `evidence: Vec::new()` and `id: KirId::new()` (`mcp.rs:2305-2312`, `:2496-2506`), and no reviewer identity is recorded.

**Proposed change (S).** Amend `CLAUDE.md`; decide whether confirming a payment authorization (`AuthorizedBy`) should remain agent-reachable; put the reviewer and note on a `KirEvidence` the decision event cites, with a deterministic event id.

---

## Noted, not filed

- `is_pending_review` (`kir/src/lib.rs:480-485`) treats a non-string `status` as "confirmed". Every current writer stores a string (checked: `governance_analyzer.rs:167` writes a `String`), so this is a typing hole, not a live defect. Worth a sentence in the doc comment or a typed accessor.
- `KirEvidence.confidence` is a public field (`kir/src/lib.rs:355-360`); `with_confidence` clamps to [0,1], direct construction does not.
- When two definitions share an id, the surviving object is the last member read (`semantic/src/conflicts.rs:310-323`); RFC 0172 says path order, so this is deterministic when the caller sorts, and a model's side condition rather than a bug.
- `merge_branch` prints its conflicts and does not persist them, and re-appends merged objects at merge time (`ledger/src/lib.rs:1621-1663`); RFC 0011 describes this as divergence detection, so it is a design limit to raise as a proposal, not a defect.
- An object a later compile no longer emits stays current; nothing retracts at object level. By design given append-only; the freshness manifest (RFC 0171) is the only signal. A proposal, not a defect.
