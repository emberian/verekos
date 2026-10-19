<!-- Scout memo, lane D2 (items 5-8 of the upstream review), 2026-10-19. Written by claude-glm (glm-5.3) with --add-dir grants after two claude-grok runs died on "Prompt is too long". Harvested verbatim; findings verified separately by the root before any issue is filed. -->

# TASK D memo — adversarial review of EKOS vs its stated invariants

**Summary (5 lines):**
1. The strongest invariant (RFC 0043 redaction at *every* raw-content entry point) is violated twice outside the two canonical entry points: `//!` crate doc comments go to external LLMs unredacted, and `git blame` commit summaries are persisted to the append-only ledger unredacted.
2. `is_pending_review` was generalized (RFC 0047) but the biggest producer of hypotheses (`business_semantics`) writes its `ExplainedBy` edges with **no** `status`, so hypothesis edges are walked as facts by `ekos_dependents`/`ekos_impact`/neighborhood — and the dependents output cannot even show the endpoint's hypothesis status.
3. The human-only source-scan tests are lexical, single-file, vacuous under a rename, and defeatable by `use … as` aliasing; they also do not cover extension MCP tools at all.
4. Read scope (RFC 0181) is the best-defended area: `#[serde(skip)]` config, three-command flag gating, per-call scope composition by nesting, overfetching retrieval, and a 726-line leak suite — residual gaps are the name-presence-only structural test and one CLAUDE.md phrasing omission.
5. Nothing here required running builds or tests (read-only lane); all evidence is quoted source.

---

## Finding 1 — Hypothesis `ExplainedBy` edges are traversed as facts, and the output hides the hypothesis

**Invariant:** "Every semantic conclusion must be traceable to Evidence" + RFC 0029's rule that an unconfirmed item stays "structurally distinguishable from an observed fact, never indistinguishable" (`/Users/ember/dev/EKOS/ekos/docs/rfcs/0029-cross-system-identity-resolution.md:36,224`), restated in code at `/Users/ember/dev/EKOS/ekos/crates/kir/src/lib.rs:465-477`.

**Evidence:** `is_pending_review` reads only the **relationship's** `status` property (`/Users/ember/dev/EKOS/ekos/crates/kir/src/lib.rs:480-485`):
```rust
pub fn is_pending_review(&self) -> bool {
    match self.properties.get("status").and_then(|v| v.as_str()) {
        None => false,
        Some(status) => status != "confirmed",
    }
}
```
But `business_semantics::relate` writes hypothesis edges with no properties at all (`/Users/ember/dev/EKOS/ekos/crates/semantic/src/business_semantics.rs:469-475`):
```rust
fn relate(&mut self, kind: &str, from: KirId, to: KirId) {
    self.out.relationships.push(KirRelationship::deterministic(
        RelationshipKind::Custom(kind.into()), from, to, "",
    ));
}
```
while the *object* gets `status: "hypothesis"` (`business_semantics.rs:479-481`, `o.properties.insert("status".into(), json!(HYPOTHESIS));`, `HYPOTHESIS = "hypothesis"` at `:50`, `EXPLAINED_BY` at `:46`). The edge is created `owner → hypothesis-item` (`b.relate(EXPLAINED_BY, owner, id)`, `business_semantics.rs:2082`), so `is_traversable` (`/Users/ember/dev/EKOS/ekos/crates/runtime/src/lib.rs:148-150`) passes it and the hypothesis item lands in the **dependencies** bucket of a real table/column. Worse, the `ekos_dependents` entry prints only the *relationship's* properties (`/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/mcp.rs:1952-1960`):
```rust
bucket.push(json!({
    "id": other_id.to_string(),
    "name": other.as_ref().map(|o| o.name.clone()),
    "kind": other.as_ref().map(|o| o.kind.to_string()),
    "relationship": rel.kind.to_string(),
    "properties": rel.properties,
}));
```
— the endpoint object's `status: hypothesis` never appears, so the answer to "what does this table depend on?" is indistinguishable-from-fact exactly as RFC 0029 forbids. `MigrationProposal` objects (`status: "proposed"`, `/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/migrate_logic.rs:414-430`) are similarly ordinary queryable objects; distinguishability there rests entirely on the consumer reading the `status` property.

**Severity:** invariant enforced only by convention for the whole semantics layer (actively enforced for `SameAs`, unenforced for the layer that produces the most hypotheses).

**Proposed upstream change (M):** (a) make `is_traversable` and the mcp.rs:1945 / runtime lib.rs:273,682,724 filters also consult the endpoint objects' `status` (or stamp `status: "hypothesis"` on `relate()` edges and re-derive it on review confirmation); (b) add the endpoint's `status` to the dependents/dependencies JSON; (c) a test mirroring `is_pending_review_generalizes_beyond_same_as` (`kir/src/lib.rs:949`) at the runtime level: a `BusinessConcept` with `EXPLAINED_BY` from a table must not appear in `ekos_dependents`/impact until confirmed. **VerEKOS:** catches this by construction — a model where traversal is typed over verified-vs-hypothetical edges cannot even express "walk an edge whose endpoint carries `hypothesis`".

## Finding 2 — `read_crate_doc_comment` sends raw, unredacted source text to an external LLM provider

**Invariant:** "Secrets/PII are never observed or stored (RFC 0043) — a built-in redaction baseline (`ekos_common::redaction`) runs at every raw-content entry point" (`/Users/ember/dev/EKOS/CLAUDE.md:162-164`).

**Evidence:** `/Users/ember/dev/EKOS/ekos/crates/recovery/src/architecture_reasoning.rs:412-417` reads a crate's entry file with neither the exclusion check nor `redact`:
```rust
pub fn read_crate_doc_comment(workspace_root: &std::path::Path, crate_dir: &str) -> Option<String> {
    for entry_file in ["src/lib.rs", "src/main.rs"] {
        let path = workspace_root.join(crate_dir).join(entry_file);
        let Ok(source) = std::fs::read_to_string(&path) else { continue; };
```
The extracted `//!` lines flow: `commands/architecture.rs:91` → `with_crate_context` (`architecture.rs:186-188`) → `extra_context` → the prompt JSON (`architecture_reasoning.rs:264-266`, `entry["doc_comment"] = serde_json::json!(ctx);`) → `self.llm.complete(&req)` (`architecture_reasoning.rs:311-316`). No `redact` anywhere on that path (`grep -n redact` in both files: zero hits). Contrast the codebase's own standard for LLM-bound source text, `/Users/ember/dev/EKOS/ekos/crates/recovery/src/llm_description.rs:266-268`: "Real source text for `obj`'s own `source_span`, redacted (RFC 0043 — sent to an external LLM provider, the same secrets/PII boundary every other raw-content entry point already enforces)" — and it delivers (`return Some(redact(&text, redaction));`, `llm_description.rs:298`), as does the span re-reader (`/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/migrate_logic.rs:43-49`: `is_excluded_path` then `redact`). RFC 0067 even names this function "the one real precedent" for raw doc-comment extraction (`/Users/ember/dev/EKOS/ekos/docs/rfcs/0087-real-doc-comment-extraction.md:17`) — the precedent skips the boundary. The usage log and LLM cache store no prompt text (`recovery/src/usage.rs:63`, `recovery/src/cache.rs:125-131`), so this is an exfiltration-path violation, not persistence.

**Severity:** invariant actually violated (a secret-shaped string in a `//!` comment leaves the machine to the provider, and an excluded file is still read).

**Proposed upstream change (S):** thread `RedactionConfig` into `read_crate_doc_comment` (the call site has `&EkosConfig`), refuse `is_excluded_path`, `redact` the joined doc lines; add a test with a `//!` comment containing `sk-...`/`AKIA...` shapes asserting a mock provider's received prompt contains only the placeholder. **VerEKOS:** a model typing entry points as `Source → Redacted → (LLM | Ledger)` makes this path untypable — caught by construction.

## Finding 3 — `git blame` commit summaries are persisted to the ledger unredacted

**Invariant:** same RFC 0043 baseline; "Because the ledger is append-only, this has to be a prevention control … there is no way to un-commit something already ledgered" (`/Users/ember/dev/EKOS/CLAUDE.md:164-167`).

**Evidence:** the RFC 0170 blame source runs `git blame --porcelain` directly and parses commit `summary` lines (`/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/semantics.rs:307-327`) with no `redact` and no `is_excluded_path` on the blamed path. The summary is then persisted twice — as a `RationaleLink` property (`("summary", json!(hit.summary))`, `/Users/ember/dev/EKOS/ekos/crates/semantic/src/business_semantics.rs:2064`) and as evidence text (`format!("git blame: {short} {}", hit.summary)`, `business_semantics.rs:2078`). RFC 0043's non-goals exempt only *structured* author name/email (`/Users/ember/dev/EKOS/ekos/docs/rfcs/0043-secrets-and-pii-redaction.md:102-107`: "git commit author name/email … is explicitly **not** redacted") — free-text commit subjects (a classic secrets vector: "rotate AKIA… before prod") are neither exempted nor covered. RFC 0043's entry-point census (build.rs + recover.rs, later pg-live as "third") was simply never re-run when RFC 0170 added a fourth direct-to-git reader.

**Severity:** invariant actually violated for secret-shaped commit subjects, and permanently (append-only ledger).

**Proposed upstream change (S):** run `redact(summary, &config.redaction_config())` at the `RationaleSource` boundary (or in `business_semantics` where hits are consumed), plus a planted-token test; and add blame to the enumerated raw-content entry points in CLAUDE.md's `common`/`recovery` rows and RFC 0043's list. **VerEKOS:** same `Redacted<Content>` typing as Finding 2.

## Finding 4 — The human-only "a test scans" guards are lexical, rename-vacuous, and blind to indirection and extensions

**Invariant:** "AI systems consume knowledge through the Runtime only"; `apply_review` / `resolve` / lifecycle / approvals are human-only (`/Users/ember/dev/EKOS/CLAUDE.md:109,118,119`).

**Evidence:** all four guards are `!mcp.contains(string)` over one file's text: `semantics.rs:1683-1694` (`!mcp.contains("semantics_review")`, `!mcp.contains("semantics::review")`, `!mcp.contains("import::linkml")`); `session.rs:591-599` (`!mcp.contains("ekos_session::lifecycle")`, `!mcp.contains("Actor::Human")`); `migrate.rs:3398-3418` (`"ekos_migrate::lifecycle"`, `"ekos_migrate_approval::lifecycle"`, `"ApprovalRequest"`, `"Actor::Human"`); `conflicts.rs:779-791` (`!mcp.contains("conflicts::resolve")`, `!mcp.contains("Resolution::")`). Three failure modes: (a) **rename vacuity** — if `semantics_review` is ever renamed, the assertion passes forever while the new name may appear freely in mcp.rs; no test ties the scanned string to the symbol that still exists; (b) **aliasing** — `use super::semantics::review as confirm_now;` followed by `confirm_now(…)` in mcp.rs contains none of the forbidden substrings; (c) **scope** — the MCP surface is larger than mcp.rs: extension tools (`ext.mcp_tool_is_scoped(name)`, `/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/mcp.rs:1564-1566`; RFC 0149/0191) are outside every scan, and an extension binary invoking the CLI `semantics confirm` subprocess is unconstrained (the web console's catalogue `Class::Review` fence — `catalogue.rs:322-335` — covers only console-spawned commands). The migrate crate's `the_lifecycle_actor_has_no_agent_variant` (`migrate.rs:3415+`) shows the stronger structural style already exists in-tree.

**Severity:** enforced only by convention (lexical convention, explicitly — one test even self-describes as "Crude, and it works", `migrate.rs:3396-3397`).

**Proposed upstream change (M):** (a) make each scan bidirectional — `include_str!` the review module and assert the forbidden symbol still exists there, so a rename breaks both sides; (b) add a whole-tree caller census: scan `crates/cli/src/**` for `apply_review(`, `lifecycle::confirm`, `resolve(` etc. and assert the caller set equals the known CLI command files — this catches indirection through new sibling modules; (c) state the extension seam's human-only expectation (an extension tool must not reach review entry points) in RFC 0149 and add the same census over `ext.mcp_tools` registrations where possible. **VerEKOS:** a model whose review-transition relation is indexed by `Actor ∈ {Human}` makes an agent-reachable transition unrepresentable — the scans become unnecessary rather than crude.

## Finding 5 — The ScopedStore coverage test proves name presence, not a decision

**Invariant:** "`every_store_method_has_a_decision_here` reads the trait source" (`/Users/ember/dev/EKOS/CLAUDE.md:110`) — i.e. every `KnowledgeStore` method has a real scope decision.

**Evidence:** `/Users/ember/dev/EKOS/ekos/crates/ledger/src/scope.rs:1311-1341` extracts trait method names and checks `wrapper.contains(&format!("    fn {name}("))` — presence of the signature in the impl, nothing about the body. A future edit that makes some `fn` a bare `self.inner.X()` passthrough (filter forgotten) still passes; only the leak suite's specific probes would notice, and only for the paths it exercises (`/Users/ember/dev/EKOS/ekos/crates/cli/tests/read_scope.rs:400` covers the scoped tools with marker words — it cannot cover a *new* store method no tool calls yet).

**Severity:** enforced only by convention at the margin (the known methods are genuinely decided — I read `find_objects`/`retrieve`/counts at `scope.rs:688-746`, including the OVERFETCH widen-then-filter; the residual risk is regression, not a present leak).

**Proposed upstream change (S/M):** extend the test to require each wrapper `fn` body between its signature and the next `fn ` to mention one of the decision tokens (`visible`, `admit`, `refuse`, `is_restricted`, `keep_`) — a body with none is a passthrough by definition. **VerEKOS:** the read-scope model is the natural first formalization: `read(store, scope) ⊆ visible(scope)` as a checked property over every trait method would make the wrapper's completeness a theorem rather than a grep.

## Finding 6 — `read_symbol_source` redacts but skips the excluded-path check its sibling enforces

**Invariant:** RFC 0043 exclusion ("`[security]` excluded-file globs") applies at every raw-content reader; `ekos.toml`'s `[security]` "can only extend it, never disable it" (`CLAUDE.md:163-164`).

**Evidence:** `/Users/ember/dev/EKOS/ekos/crates/recovery/src/llm_description.rs:277` does `std::fs::read_to_string(workspace_root.join(file_path))` and redacts the slice (`:298`), but never calls `is_excluded_path`. The span-re-reader it mirrors does both (`migrate_logic.rs:43-45`: `if ekos_common::redaction::is_excluded_path(path, &redaction) { return Err(...) }`). A file observed before a `[security]` exclude glob was added keeps feeding the LLM-description path (redacted text, but from a file the operator excluded precisely so it would not be read). Same shape in `read_crate_doc_comment` (Finding 2).

**Severity:** enforced only by convention / inconsistency between sibling implementations.

**Proposed upstream change (S):** one shared helper (`read_source_redacted(cwd, path, &RedactionConfig) -> Option<String>` in `ekos_common` or recovery) used by all three span/comment re-readers, with the exclusion refusal and a test that an excluded path yields nothing.

## Finding 7 — CLAUDE.md overstates read-scope breadth relative to RFC 0181

**Invariant / claim:** "`commands/store.rs` wraps every store the CLI opens when `--read-scope` is given" (`/Users/ember/dev/EKOS/CLAUDE.md:110`).

**Evidence:** true as far as it goes, but only three commands accept the flag at all — `app.rs:1488-1496` bails for anything but `Commands::Mcp | Ekl | Query`, and RFC 0181 says so plainly (`/Users/ember/dev/EKOS/ekos/docs/rfcs/0181-read-scope.md:96-98` and "Not built" `:158`: "`--read-scope` on `ekos ask`, `docs generate` and the other commands"). A reader of CLAUDE.md alone (the file every lane/agent is told to trust) can believe `ekos ask`/`docs generate` can be scoped; they read the ledger unrestricted by design. The engineering underneath is sound — `read_scope` is `#[serde(skip)]` so it cannot arrive via `ekos.toml` (`compiler-core/src/config.rs:62-66`), and per-call `_meta` scope composes with the process scope by nesting (`mcp.rs:285`, `mcp.rs:200-215` with `set_scopes` on the outer wrapper only).

**Severity:** documentation mismatch (no code defect found).

**Proposed upstream change (S):** one clause in CLAUDE.md's `ledger` row: "`--read-scope` exists on `ekos mcp serve` / `ekos ekl` / `ekos query` only; every other command refuses it (RFC 0181)."

---

## What the code does better than its docs claim

- **`is_pending_review` is far more general than the task brief (and older docs) suggest:** RFC 0047 generalized it to *any* relationship kind adopting the `status` convention, with regression tests for `rejected`, `Custom("Opposes")`, and status-less compiler facts (`kir/src/lib.rs:940-972`) — the gap is only that producers don't adopt it (Finding 1), not that the check is `Custom(SameAs)`-only.
- **The RFC 0043 exemption is narrower in code than it reads:** the "author name/email not redacted" exemption is honored precisely — the *structured* `Person` fields keep attribution while everything else in the git path goes through the redacted artifact store; only the later blame reader (Finding 3) drifted.
- **Read scope's defense-in-depth exceeds its RFC:** `#[serde(skip)]` on `read_scope` (config file can't smuggle a scope), result-cache keys include the request scope (`mcp.rs:292-296, 217-222`), an unlisted MCP tool is refused for restricted readers by default (`mcp.rs:1567-1570` + the coverage test at `mcp.rs:3151-3162`), and `RankedResults` carries no total count that a filtered `retrieve` could leak (`scope.rs:702-721`, `retrieval.rs:129-137`).
- **Freshness content-hashing really never reads excluded paths:** `add_hashes` checks `is_excluded_path` before reading bytes (`cli/src/freshness.rs:214-218`), exactly as CLAUDE.md:121 promises — metadata-only, verified in source.
- **The migrate-approval guard already knows it needs to name every lifecycle module:** `migrate.rs:3401-3404` scans for *two* lifecycle crates with a comment saying "a second lifecycle module is a second way in" — the multi-symbol awareness is better than the single-string scans in semantics/session/conflicts.

**Not verified:** I ran no builds or tests (read-only lane); the web console (Python) and the out-of-tree ekos-lakehouse extension were assessed only from CLAUDE.md/RFC text, not source; of the 155 workspace `fs::read*` sites I audited the raw-*source*-content paths named in the brief plus every recovery-crate direct reader — config/ledger/state reads were excluded by purpose, not by inspection.
