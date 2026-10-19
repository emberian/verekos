<!-- Scout memo, lane D1 (items 1-4 of the upstream review), 2026-10-19. Written by claude-grok (grok-4.7) with --add-dir grants and a context budget; the first run died on "Prompt is too long". Harvested verbatim; findings verified separately by the root before any issue is filed. -->

## Summary

The ledger trait really is append-only: no `KnowledgeStore` method deletes an object, and `vacuum_into` copies. The determinism audit of relationship **ids** holds on the 15 production sites sampled (all uuid v5). Two stated invariants do not. Evidence ids are still `KirId::new()` (uuid v4), and `content_signature` hashes them, so a recompile of unchanged SQL appends a new version forever. Several compiled edges (`FeedsInto`, `EvidencedBy`, `Disputes`) are persisted with an empty `evidence` vector. `ekos_clickhouse_query` appends to the ledger, and `ekos_identity_review` confirms `AuthorizedBy` as well as `SameAs`, despite `CLAUDE.md`.

## Findings

### 1. Evidence ids are random, so a deterministic recompile still appends

- **Invariant:** compiler passes are deterministic; the ledger is append-only, so a non-deterministic id is permanent.
- **Severity:** invariant actually violated (determinism). Append-only then makes the extra versions unremovable.
- **Evidence:** `KirEvidence::new` mints `KirId::new()` (`/Users/ember/dev/EKOS/ekos/crates/kir/src/lib.rs:14`, `:366`). The SQL pass does not overwrite it, then hangs that id on a **stable** object id:

```505:510:/Users/ember/dev/EKOS/ekos/crates/recovery/src/sql_analyzer.rs
                format!("CREATE TABLE {table_name}"),
            );
            let ev_id = graph.add_evidence(ev);
            let mut obj = KirObject::new(&table_name, ObjectKind::Table).with_evidence(ev_id);
            obj.id = table_kir_id(&table_name);
```

`content_signature` strips only `created_at` (`/Users/ember/dev/EKOS/ekos/crates/ledger/src/lib.rs:47-50`). `FactLedger::append_inner` writes a new version whenever that signature differs (`/Users/ember/dev/EKOS/ekos/crates/ledger/src/fact_ledger.rs:722-724`). The same gate is `(id, content_sig)` on the SQLite path (`/Users/ember/dev/EKOS/ekos/crates/ledger/src/lib.rs:514`). A fresh evidence uuid is therefore a new evidence **entity** (old one orphaned) and a new version of the table. `source_evidence::attach` does the same mint (`/Users/ember/dev/EKOS/ekos/crates/recovery/src/source_evidence.rs:47-55`). Contrast `conflicts::kid` / `business_semantics::kid`, which are uuid v5 (`/Users/ember/dev/EKOS/ekos/crates/semantic/src/conflicts.rs:50-51`, `/Users/ember/dev/EKOS/ekos/crates/semantic/src/business_semantics.rs:144-145`). There is no `KirEvidence::deterministic`.
- **Upstream (M):** `KirEvidence::deterministic(path, line, fragment)` as uuid v5, use it in `sql_analyzer` and `source_evidence::attach`, and extend the RFC 0135 guard to fail on `KirEvidence::new` in production passes unless `ev.id` is assigned a v5. Add a test that two `parse_ddl_structural` calls on the same SQL produce equal evidence ids and equal `content_signature`s.
- **VerEKOS:** yes, if an evidence id must be a function of `(path, line, fragment)`.

**Relationship-id sample (RFC 0135 Part C).** All 15 production sites derive the id; none leave `KirRelationship::new`'s v4 in place:

| Site | Id |
|---|---|
| `semantic/src/data_lineage.rs:79-83` | `reads_writes_kir_id` v5 |
| `recovery/src/sql_analyzer.rs:694-695` | `foreign_key_kir_id` v5, `fk_desc` in the seed |
| `recovery/src/requirements_analyzer.rs:150-151` | `depends_on_kir_id` v5 |
| `recovery/src/package_json_analyzer.rs:121-122` | `depends_on_kir_id` v5 |
| `recovery/src/crate_topology_analyzer.rs:331-332` | `depends_on_kir_id` v5 |
| `recovery/src/dbt_analyzer.rs:652-653` | `dbt_depends_on_kir_id` v5 |
| `recovery/src/python_analyzer.rs:679-680` | `orm_foreign_key_kir_id` v5 |
| `recovery/src/python_analyzer.rs:878-882` | `extends_kir_id` v5 |
| `semantic/src/rollup.rs:166` | `KirRelationship::deterministic` |
| `semantic/src/lib.rs:259` | `SameAs`, `deterministic` |
| `semantic/src/lib.rs:393` | risk `References`, `deterministic` |
| `semantic/src/conflicts.rs:225` | `Disputes`, `deterministic` |
| `semantic/src/transform_ir.rs:299` | `FeedsInto`, `deterministic` |
| `semantic/src/triggers.rs:274` | `DependsOn`, `deterministic` |
| `semantic/src/business_semantics.rs:469-472` | `relate()`, `deterministic` |

The guard that is supposed to keep it that way is a non-recursive `read_dir` of `src/*.rs` plus a 600-character `".id ="` window (`/Users/ember/dev/EKOS/ekos/crates/recovery/src/lib.rs:159-169`, `/Users/ember/dev/EKOS/ekos/crates/semantic/src/lib.rs:1532-1541`). It does not look at evidence ids, object ids, or any other crate. No production relationship in this sample slipped through that window.

### 2. Compiled edges are stored with `evidence: []`

- **Invariant:** every semantic conclusion is traceable to Evidence.
- **Severity:** invariant actually violated for the edge itself. Endpoints sometimes carry evidence; nothing copies it onto the edge. `ekos coverage` already missed this class once (Python, fixed in `merge_file_result`).
- **Evidence:**
  - `lower_to_kir` pushes `FeedsInto` with the default empty vector. The node just above has evidence; the edge does not (`/Users/ember/dev/EKOS/ekos/crates/semantic/src/transform_ir.rs:286-306`).
  - `relate` always pushes a deterministic edge and never sets `evidence` (`/Users/ember/dev/EKOS/ekos/crates/semantic/src/business_semantics.rs:469-472`). Callers include `EvidencedBy` (`:1495`), `Describes`, `ConflictsWith` (`:1588`), `ExplainedBy` (`:2082`).
  - Both `Disputes` constructors omit evidence (`/Users/ember/dev/EKOS/ekos/crates/semantic/src/conflicts.rs:225-229` and `:480-488`). The conflict **object** has evidence; the second edge does not copy it.
  - Concentration-risk `References` is the same (`/Users/ember/dev/EKOS/ekos/crates/semantic/src/lib.rs:393-394`). The risk object copies up to five evidence ids (`:383-391`); the edge gets none.
- **Upstream (M):** one helper that builds the deterministic edge and sets `evidence` from the subject's evidence (the Python `merge_file_result` pattern at `/Users/ember/dev/EKOS/ekos/crates/recovery/src/python_analyzer.rs:247-270`). A semantic-crate test that every non-test `KirRelationship` pushed to a graph has non-empty `evidence`.
- **VerEKOS:** yes, if a persisted relationship's type requires a non-empty evidence set.

### 3. `ekos_clickhouse_query` writes the ledger

- **Invariant:** the Runtime is read-only; every MCP tool except the two review tools and the session-note inbox is read-only (`/Users/ember/dev/EKOS/CLAUDE.md:157`, `:180-181`).
- **Severity:** invariant actually violated.
- **Evidence:** `ask_clickhouse` calls `audit::record_query_event` (`/Users/ember/dev/EKOS/ekos/crates/clickhouse-query/src/lib.rs:135`), which `append_evidence`s and `append_event`s (`/Users/ember/dev/EKOS/ekos/crates/clickhouse-query/src/audit.rs:33-56`). The MCP tool uses the same `run_query` as the CLI (`/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/clickhouse.rs:27-50`), which opens `open_store` (`/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/store.rs:169`), not the read-only handle. The event id is `KirId::new()` (`audit.rs:46`), so each call is a new row even for the same SQL. SELECT-only is enforced before execution (`/Users/ember/dev/EKOS/ekos/crates/clickhouse-query/src/validate.rs:1-4`); that does not make the ledger write read-only.
- **Upstream (S):** state the audit write in `CLAUDE.md`, or record it outside the knowledge ledger. Add an MCP dispatch test that the only ledger-appending tool names are an explicit allowlist.
- **VerEKOS:** yes, if MCP tools are typed read-only except an allowlist that does not include this audit append.

### 4. A review decision is an unevidenced event, and the tool is wider than `CLAUDE.md`

- **Invariant:** conclusions carry evidence; `ekos_identity_review` reviews only `Custom("SameAs")` (`/Users/ember/dev/EKOS/CLAUDE.md:180`).
- **Severity:** documentation mismatch on scope; evidence rule enforced only by convention on the decision itself (the candidate relationship may already cite evidence; the decision event does not).
- **Evidence:** the kind check accepts `SameAs` **or** `AuthorizedBy` (`/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/mcp.rs:2289-2296`). The tool description matches the code (`mcp.rs:1389`); `CLAUDE.md:180` does not. RFC 0032 intended the widening (`/Users/ember/dev/EKOS/ekos/docs/rfcs/0032-treasury-compliance.md:210`). Both review handlers append an event with `evidence: Vec::new()` and `id: KirId::new()` (`mcp.rs:2305-2312`, `:2496-2506`). No actor is stored. An agent that can call the tool can confirm a payment authorization.
- **Upstream (S):** amend `CLAUDE.md:180` to name `AuthorizedBy`, or split a human-only payment decision off this tool. Put the decision's reviewer and note on a `KirEvidence` before `append_event`. (M if the payment path must become human-only.)
- **VerEKOS:** the empty evidence vector, yes. The SameAs-only predicate, yes, and it would currently fail.

### 5. The rollup object, the thing an agent reads, has no evidence

- **Invariant:** every semantic conclusion carries evidence.
- **Severity:** invariant actually violated for the object. The `Contains` edges do carry evidence, but that evidence's location is the group key, not a source file.
- **Evidence:** `synthesize_rollups` builds the object with `KirObject::new` and sets `id` only (`/Users/ember/dev/EKOS/ekos/crates/semantic/src/rollup.rs:187-196`). Evidence is created per member as `SourceLocation::file(group_key)` with fragment `"… is a member of {group_key}"` and attached to the edge, not the object (`:156-168`). `group_key` looks like `dir:ekos/crates/kir` or `project:…/dir:…` (`group_key_for`, same file).
- **Upstream (S):** set `rollup.evidence` to those evidence ids, and point `SourceLocation` at a real member path.
- **VerEKOS:** yes, same non-empty-evidence obligation as finding 2, applied to objects.

### 6. The embedding index tombstones and then drops rows

- **Invariant:** "`no object-level delete/tombstone exists anywhere in the codebase`" (`/Users/ember/dev/EKOS/CLAUDE.md:166`).
- **Severity:** documentation mismatch. These are index rows, not ledger entities. `compact` does physically delete.
- **Evidence:** `tombstones.bin`, `upsert` sets the old row to `1` and appends (`/Users/ember/dev/EKOS/ekos/crates/ledger/src/vector.rs:14-18`, `:191-207`), `remove` tombstones (`:214-216`), `compact` rewrites the files without tombstoned rows (`:257-267`, flush via `std::fs::write` at `:282`). The fact store still filters retracted objects at query time because the index is **not** pruned on retract (`/Users/ember/dev/EKOS/ekos/crates/ledger/src/fact_ledger.rs:1139-1140`). The only `remove` caller found is the unit test at `vector.rs:390`.
- **Upstream (S):** narrow `CLAUDE.md:166` to ledger entities, and note that `vectors/` is a rebuildable index with tombstones. No ledger API change.
- **VerEKOS:** only if "no tombstone" is stated over every durable file, not just `KnowledgeStore`.

### 7. Append-only is a trait property, not a property of the process

- **Invariant:** knowledge is never modified in place; nothing ledgered can be un-committed (`CLAUDE.md:154`, `:166`).
- **Severity:** enforced only by convention once you leave the trait. Not an object-level tombstone.
- **Evidence:** `KnowledgeStore` exposes `append_*` and `vacuum_into` and no delete (`/Users/ember/dev/EKOS/ekos/crates/ledger/src/lib.rs:1683-1757`). `vacuum_into` is a copy (`lib.rs:1150-1161`, `fact_ledger.rs:1241-1254`, `partitioned/mod.rs:1383`). Current-state tables are `INSERT OR REPLACE` pointers (`lib.rs:594`); the old `entries` row stays. The one `DELETE` found is `DELETE FROM object_fts` when the FTS pointer moves (`lib.rs:465`), not the payload. Separately, `project remove --purge` is `remove_dir_all` on the project dir (`/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/project.rs:211-229`). `session purge` deletes inbox files only and prints that ledger claims remain (`/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/session.rs:330-360`); `source_purged` is computed at read time (`/Users/ember/dev/EKOS/ekos/crates/session/src/read.rs:310-311`).
- **Upstream (S):** an RFC sentence that names filesystem purge as the only un-commit, and a test that `KnowledgeStore` has no method whose name deletes or tombstones an entity.
- **VerEKOS:** the trait shape, yes. `remove_dir_all`, no, unless the model includes the operator surface.

## Not verified

The determinism-guard tests were not executed. Not every `KirObject::new` was classified; the object sites next to the relationship sample do assign a v5 id before insert (`sql_analyzer.rs:510`, `package_json_analyzer.rs` tech object, `rollup.rs:195`, `conflicts.rs` emit). Whether a warm compile cache makes a second `commit` identical **without** re-running the pass was not checked; the pass is non-deterministic when it runs. `DistributedLedger` was not read past `append_object` (`/Users/ember/dev/EKOS/ekos/crates/distributed/src/gateway.rs:457`). No production caller of `VectorIndex::remove` was found outside its test.

## What the code does better than its docs claim

- Idempotent append is real, not a comment: same `(entity, content_signature)` returns `false` and writes nothing (`fact_ledger.rs:722-724`), and `created_at` is excluded so a fresh `Utc::now()` does not by itself fork a version (`lib.rs:47-50`).
- Fact retraction is another op, not an in-place edit. `object_count` never shrinks on retract (`fact_ledger.rs:1209-1212`). `session purge` does not rewrite those ops.
- `home backup` refuses to overwrite an existing archive (`/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/home_backup.rs`, the `out.exists()` bail in `backup`).
- Redaction cannot be turned off: `RedactionConfig` only has `extra_patterns` and `extra_excluded_globs`, and a bad extra regex is skipped rather than aborting the built-in pass (`/Users/ember/dev/EKOS/ekos/crates/common/src/redaction.rs:213-220`, `:245`).
- Python edges used to be stored with empty evidence; `merge_file_result` now fills `DependsOn` and `Extends` from `edge_spans` (`python_analyzer.rs:223-227`, `:247-270`). That fix was not applied to the semantic edges in finding 2.
- Human-only promotion (semantics confirm/reject/edit, conflicts resolve, migrate approve/reject, session review, import linkml) is a `Class::Review` list the MCP server does not dispatch (`/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/catalogue.rs:322-331`, `mcp.rs:1086-1088`, `:1136-1137`).
