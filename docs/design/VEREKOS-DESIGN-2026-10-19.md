# VerEKOS design, 2026-10-19 (revision 2, same day)

Written by the root (Fable 5.1). Revision 1 was written after reading EKOS
(`~/dev/EKOS`, 188K lines of Rust, 207 RFCs, 281 devlogs; our checkout equals
upstream `alexeyban/EKOS` main), veri7vn (`~/dev/o7vn`) and minidregg
(`~/dev/minidregg`). Revision 2 folds in six scout memos (`../../notes/`, A to F)
and the root's own verification of every claim that changed a sentence here.
Where a memo and this document disagree, the memo with the path and line wins
and this document is wrong.

What the scouts corrected is listed in §8, so a reader of revision 1 can see
what moved.

## 1. What EKOS actually promises, and how it keeps each promise

EKOS's product claim is not an algorithm. It is a set of properties of a ledger
and of the people and agents reading it. Stated as the theorems they want to be,
with how the code keeps each one today (lane A's census, `notes/A-invariants.md`,
has 60 rows; these are the twelve that carry the product):

| # | Promise | How EKOS keeps it today | Verified status |
|---|---|---|---|
| P1 | The **log** only grows. A version is a list of assert/retract facts (`FactOp`) diffed against the previous state; identical content appends nothing (content signature, `created_at` excluded). Retraction is an appended op, so the *reconstructed state* can lose a fact while the log cannot. | `fact_ledger.rs` append path; `append_is_idempotent` | holds; the state/log distinction is undocumented |
| P2 | `object_at(id, t)` is a fold of the log prefix; `diff(from, to]` is the union of write footprints in the window. | tests on both backends | holds, on the linear `TxId` order |
| P3 | Every compiled object and relationship cites evidence that resolves to a source location and fragment. | convention; `evidence: Vec<KirId>` is `serde(default)` | **does not hold**: `FeedsInto`, `Disputes`, risk `References`, every `business_semantics::relate` edge and the rollup object are written with an empty vector (D1 §2, §5) |
| P4 | Passes are deterministic: same input, same ids, same content. | RFC 0135 Part C guard on relationship ids (all 15 sampled sites v5); object ids per analyzer; **evidence ids are uuid v4** | **does not hold on a cache miss**: `KirEvidence::new` mints a random id, the object's `evidence` list is inside its content signature, so a re-run forks a new version of every object the pass touches (D1 §1, verified) |
| P5 | The Runtime is read-only; agents reach knowledge only through it. | all `append_*` in the runtime crate are under `cfg(test)`; the `&dyn KnowledgeStore` it holds still exposes four append methods; no read-only trait exists | convention only; `ekos_clickhouse_query` appends an audit evidence and event through the normal store (D1 §3, verified) |
| P6 | Identity: merge iff normalized names are exactly equal and neither kind is structurally keyed; a fuzzy match is an `unconfirmed` `SameAs` edge; traversal never crosses a pending edge. | `exact_name_match`, registry scan test, `is_pending_review` filters at four traversal sites | holds; `is_pending_review` reads a non-string `status` as "confirmed" (theoretical: every writer stores a string) |
| P7 | Conflicts: both claims kept, normalized before comparison, a `Custom("ConflictingEvidence")` object with a `Disputes` edge; detection pure and order-independent; a review survives while the signature is unchanged. | `conflicts.rs` and its reversed-input test | holds; the surviving object is the **last-read** member, so which definition survives is the caller's path order (`conflicts.rs:310-323`) |
| P8 | Read scope: deny wins; an object in two sources needs both; unattributed objects are hidden from a restricted reader; relationships need both ends; evidence only through a visible object; a per-call scope only removes. | `ScopedStore`, the leak suite, `every_store_method_has_a_decision_here` | holds; the strongest empirical check in the repo (lane A row 49) |
| P9 | Secrets never enter: a non-disableable pattern table runs at every raw-content entry point. | two entry points call `ekos_common::redaction`; `pg-live` has its own; no scan test enforces "every future entry point calls it" | holds for the known entry points; the table is a shape table and says so |
| P10 | Human-only decisions are unreachable from any agent surface. | four string-containment scans of `commands/mcp.rs`; the `Class::Review` catalogue list the MCP server does not dispatch | holds against omission; a `use … as` rename evades the scans |
| P11 | Domain time and observation time are distinct and never conflated. | `valid_from`/`valid_until` on relationships; `object_at` separate | holds; no query surface for validity windows yet |
| P12 | Freshness: a committed (path, size, mtime) manifest says whether the ledger still matches the source; session anchors go stale when their object changes. | RFC 0171/0151 | holds, as metadata |
| P13 | **Branches**: `ekos branch merge` is skip-if-present; a logical id present in both with different content is a reported conflict, never overwritten. | `merge_branch`, `merge_branch_*` tests | holds; the conflict is printed, not stored, and merged objects are re-appended at merge time, flattening the branch's history (F §5, verified) |

Two more facts that no document states and a model must: an object that a later
compile no longer emits stays current forever (nothing retracts at object level;
checked: no such path in `commit.rs`, `semantic`, `ledger` or `runtime`), and
object ids default to random v4 (`KirId::new`) with stable v5 keys only where an
analyzer assigns one.

## 2. Two layers, because there are two kinds of promise

P1, P2, P3, P5, P8, P9, P10, P12, P13 are promises about **a world**: who may
write, what a write must carry, who may read what, what a reader can conclude.
P4, P6, P7, P11 and the query language are promises about **decisions**: pure
functions from typed inputs to typed outputs. veri7vn verified decisions and left
the world to Python. EKOS's value is mostly in the world. So VerEKOS has two
layers with two proof styles and, for now, two provers.

### 2.1 The ledger as a world (Lean, against minidregg's hyperdocument family)

ember's question was whether EKOS is expressible as a minidregg world, inside its
document runtime and SPK grains, with no privileged kernel component. Lane B
(`notes/B-minidregg-map.md`) mapped nineteen constructs and lane F
(`notes/F-revision-system.md`) read the revision system. The answer: **a natural
world wearing a forced operational costume.** The data-plane maps are exact or
close; the forcing is in how things enter and who may read.

What minidregg has (real names, all in `Theory/Hyperdocument.lean` unless noted):

| EKOS | minidregg | Fit, and what the proof already carries |
|---|---|---|
| `KirObject` | `DocumentRecord` with `schema : Digest`; typed properties as `FieldRecord`s (`FieldType` text/natural/flag/digest/reference/opaque) each with a `MergeRegime` | adaptation: no float, timestamp or list field types; `confidence` becomes a scaled natural |
| `KirRelationship` | `LinkRecord`: own id, source + optional `StableRange`, `LinkTarget` (document / element / range / transclusion / external), `relation : Digest`, author, operation, `tombstonedAt` | **exact**; backlinks are derived from accepted link events |
| `KirEvidence` (location, fragment, confidence) | `AnnotationRecord` anchored to a document, a `StableRange` or an atom **at an exact revision**, body inline or a sealed `AuthoredFragment`; or a **snapshot transclusion** of a source range | **exact and stronger**: `transclusion_pinned` (`Kernel/ContentResource.lean:2565`) is proved: a pin shows the same bytes or says `moved`, never other bytes. Needs the source imported as a document first, and an importer that keeps atom ids stable for unchanged spans, or every re-import moves every pin |
| `KirEvent` | `VersionEventRecord` in a separate **append-only** event-log cell: parents, pre/post state roots, request, effect, author | **exact**, with an inversion: minidregg derives events from accepted declarations; EKOS authors them |
| content-signature idempotence, versions | guarded writes (`guardedSet` names the exact prior value), `ValidOperation.preRootExact`, per-record `revision : OperationId`, typed digest ids with `IdDomain` separation | guard-based idempotence is exact; **identical content is not a no-op**: a duplicate event is refused (`CausalVersionDag.lean:329`), so "re-append of identical content appends nothing" must be stated as a law over normalized patches with empty write footprint (`StoreNormalize.lean`) |
| `object_at` | the causal version DAG (`CausalVersionDag.lean`) plus `Replay` and `checkpoint_suffix_equivalence`; heights exist only in the **linear durable log** | adaptation: a fold over the linearized log; on a DAG with two tips "the version at t" is a frontier, not a version. Keep P2 over `TxId` and state P13 branches separately |
| `valid_from` / `valid_until` | none; `notBefore ≤ height ≤ notAfter` exists for capability validity, not business time | data plus a law |
| `Observer` / connector | an SPK application grain: sandboxed, under Mini authority, its only output is admitted declarations | adaptation, far stronger isolation than EKOS needs, and heavy (root broker, generations, recovery protocol) |
| redaction at the entry point (P9) | **no counterpart**; nothing raw is ever admitted, and stored secrets are sealed (`AuthoredFragment` ciphertext, rewrappable keys) | the enforced law fragment (`Pred`) is small: a regex table does not fit it. Redaction stays as Lean code in the import family, which is exactly where EKOS keeps it today, now with one entry instead of three |
| pass determinism (P4) | `Store.Patch.ResultAt` + `ValidatedPatch.resultAt`: the post state realizes the declaration definitionally; admission by re-execution for Objective Bend packages | **exact** as a Lean effect-family function |
| identity merge vs unconfirmed `SameAs` (P6) | `ConflictRecord` and unreviewed `LinkRecord`s: "Resolution is a later authority-sensitive operation, not a projection" (`:473-474`); atoms never change identity (`StableRanges.lean:36-38`) | exact for the pending edge; **an exact merge as a re-key fits worse**: minidregg would model it as an overlay `SameAs` link plus canonicalization at view time, which is reversible where EKOS's exact merge is not |
| `ConflictingEvidence` + `Disputes` (P7) | `ConflictRecord {field, base, alternatives, regime, recordedAt}` with `ConflictAlternative {value, author, operation}`, a dedicated `conflicts` namespace, produced by `Kernel/HyperdocumentMerge` | better than the annotation revision 1 proposed, with three gaps: no coverage obligation (a merge may omit a diverging field), no resolve action, alternatives stored inline |
| human-only review (P10) | `AuthenticatedPrincipal` with full capability lineage, epochs, validity window and revocation as proof fields; laws are decidable `Pred`s over old state, new state and the request | adaptation: enforcement moves from a grep to a credential path; "human" is an issuance policy |
| Runtime read-only (P5) | `ObserverLens` (`CanonicalReactiveView.lean:41-54`): declared dependencies, pure projection; `project_eq_of_clean` and `underDeclared_lens_impossible` | **exact, and a property EKOS cannot state**: read-onlyness is the type of a lens |
| `ReadScope` deny-wins (P8) | no stored scope algebra; the spirit is twice present (admission is a conjunction of authority, laws, read roots, funding; disclosure is sealed by default) | adaptation inside the lens and admission laws; noninterference precedents exist: `accountCut_noninterference` (`Compiler/CanonicalAccountView.lean:25`), `PrivacyPortal.compose_noninterference` (`Theory/PrivacyProfile.lean:94`), and breadstuffs' `FogOfWar.noninterference` where a hidden cell is structurally absent |
| MCP tools | Hermes / resident tools over the authorized view; "external model output is authored prose or a proposal, never proof of truth" | adaptation |
| session anchors, staleness (P12) | revision-anchored pins, `EndpointDeathPolicy`, `WitnessCursor` liveness (`live / replayedDeterministic / reconstructedApproximate`) | **exact** |
| branches (P13) | `HyperdocumentMerge`: an ordered frontier of parents; one source becomes a write, two or more become a stored `ConflictRecord`; deliberately not commutative (`raw_pair_order_observable`); `LaceMerge.merge` is the skip-if-present join with `merge_drops_at_collision` | EKOS's `merge_branch` is `LaceMerge` plus a divergence detector whose report is printed; the world version stores the conflict |

The three mismatches, now sharpened:

1. **Entry trust.** EKOS trusts the connector as the raw-content entry point and
   redacts there. minidregg admits only six typed verbs from authenticated
   principals. A connector-as-grain therefore does its parsing where admission
   cannot see it. The resolution is to make **import of a source file as a
   document** the one entry, redact in that Lean family, and compile over
   documents. That is more storage and a real ingestion step, and it is where
   P9 belongs.
2. **Readability of the compiled corpus.** EKOS's Runtime is read-only and
   *broadly read*; scopes narrow at the edges. minidregg discloses sealed by
   default. An EKOS world either publishes its compiled layer unsealed and keeps
   sealing for imported sources, or makes the Runtime a keyholder. Revision 2
   chooses the first. Conflict alternatives must then be references resolved by
   the reader's own read, not inline values, or a restricted reader sees every
   source's claim (F §5).
3. **Whole-corpus passes vs per-turn admission.** A pass recomputes the derived
   graph from all sources; minidregg prices and admits per declaration. The
   compile is one admitted computation whose output is checked by re-execution;
   **patch merge never applies to compiled output** (F §5): a branch merge
   re-runs the compile over the merged sources. Patch theory belongs to the
   authored layers: reviews, resolutions, session notes, semantics
   confirmations, imported documents.

Also now known (F §2): breadstuffs built a Pijul-shaped patch system (`dregg-doc`,
19K lines of Rust; five `Dregg2/Deos` Lean theories with join laws, a thin-category
pushout and commutation over a simplified model). minidregg did **not** import
it: decision record D-0005 replaces it and caps every patch and pushout claim.
What survived in re-derived form: stable atom identity with tombstones and
endpoint-death policies, conflict records with provenance, the I-confluent vs
conflict-bearing split, the LaceMerge join, and a real commutation theorem over
guarded store patches (`PlanBinding.independent_commute`). What is deployed is
simpler still: a stale edit is refused; history is one linear chain by height.

Decision for revision 2: **model EKOS as a minidregg world as a law package, a
document schema and an import family, with no kernel change**, and write it
against the deployed revision-refusal model plus the compiled `ConflictRecord`
merge, not against anything in breadstuffs. The Objective Bend question is
settled by lane B §5: a pass is a Lean effect-family function behind a law until
Core4 has a digest term, generic object reads and a termination bound.

### 2.2 The decisions as kernels (Isabelle/HOL, the veri7vn pattern)

Each is a HOL function with its theorem, exported with `export_code` to Standard
ML (with `Code_Target_Numeral`, or unary naturals eat the box: lane E), compiled
with the MLton inside Isabelle2026-RC1, run from a binary that reads EKOS's own
JSON. The binary is also, trivially, a grain.

Lane C (`notes/C-afp.md`) read every candidate AFP entry's ROOT and abstract. The
import list is short, and most of the work is plain HOL:

| Kernel | Statement (plain words) | AFP | Build from HOL alone |
|---|---|---|---|
| `Ledger` | a version is a guarded patch of assert/retract facts; reconstruct = fold over the `TxId`-ordered log; `diff` = union of write footprints; identical content has an empty footprint and appends nothing; retraction removes from state and never from the log | none fits | all of it |
| `Branch` | skip-if-present merge of two logs; a same-id different-signature pair is a persisted conflict, never a write; main's version is never overwritten | the shape is `LaceMerge` (Lean, minidregg) | all of it |
| `Scope` | deny wins; "none" is inside a deny and outside an allow; both ends; composition only removes; a restricted reader's answers are a function of the visible objects alone | **`Bounded_Deducibility_Security`** for the indistinguishability wrapper (`Abstract_BD_Security.secure`); **`UPF`** for the `allow`/`deny` decision type (`prod_orD` is only the lemma shape) | the RFC 0181 table, the three origin rules, scope intersection |
| `Identity` | merge iff exact normalized-name equality and not structurally keyed; the merge relation is an equivalence, its closure order-independent; fuzzy becomes a pending edge; traversal never crosses one; also state whether an exact merge is a re-key (EKOS) or an overlay (the proposal) | none | all of it (equivalence closure from `Main`) |
| `Conflicts` | detectors pure and permutation-invariant; type normalization an equivalence; **coverage**: every attribute on which members disagree yields a conflict; the survivor is independent of input order, or there is no survivor | none | all of it |
| `Impact` | dependents/impact = reachability from a seed over typed edges with pending edges removed, bounded by hops | **`Depth-First-Search`** (`dfs`, has `export_code`); `Transitive-Closure` in a side session only if whole-relation closure is wanted | the edge filter |
| `EKL` | a relational semantics for FIND/WHERE/ORDER/GROUP/COUNT/AS OF; REASON rules as stratified Datalog | copy `Stratified_Datalog`'s `Datalog.thy` (it `imports Main`); never import the session (it drags `Deriving` → `Collections`) | the algebra |
| `Time` | validity windows vs observation cuts, never conflated | `Allen_Calculus` only if the seven qualitative relations are wanted; it does not define timestamp windows | the windows |
| `Fusion` | reciprocal rank fusion is monotone in each input ranking; ties deterministic | **`List-Index`** for rank | the fusion sum |
| `Redact` | per pattern: if it matches span s, output = text minus s plus placeholder; config only adds | none (`Regex_Equivalence` decides its own regex type; EKOS's patterns are Rust regexes) | a matcher for the table; "no secret leaks" is not a theorem and will not be claimed |

Not to import, even though they look like infrastructure: `Native_Word`, `Show`,
`Deriving`, `Containers`, `Collections`, `Datatype_Order_Generator`. The AFP
snapshot at `~/isabelle/afp-2026-05-29` reports `VERSION=2025-2` in `etc/version`;
whether its sessions build under Isabelle2026-RC1 is untested.

Untrusted, by construction, and labelled so in every binary's output: SQL and
code parsing, document extraction, every model call, BM25 and vector scoring.
Their outputs are typed inputs to kernels, exactly as a recognizer's output is in
veri7vn. EKOS already takes this posture for its LLM passes; VerEKOS extends it
to the parsers.

## 3. Why two provers, and the seam between them

A single toolchain would be cheaper. Lean alone loses BD-security, `UPF`, the
export pipeline and hbox build tooling veri7vn already has
(`tools/dev/check-native`, `remote-build`). Isabelle alone means re-inventing
authority, admission, read roots, receipts and lenses that minidregg has proved.
The seam: **an exported kernel binary is a grain.** minidregg treats grains as
untrusted physical processes whose outputs are proposals; a proof inside the
grain is about the computation, the world's laws are about admission, and
neither trusts the other. The claim at the seam is modest: the grain's output
equals the HOL function's value on the same input, and the world admits only
what its laws allow.

## 4. The scoreboard

veri7vn's rule holds: a claim about behaviour comes with a number. Lane E's
warning holds too: Oracle7 shipped its panels, scorers and verdict files;
**EKOS ships none of that**, so authoring the scoreboard is phase one, not a
given.

- **Panels.** `tests/fixtures/{ecommerce,northwind,mysql_hash_comments}.sql`,
  `sample_project`, `git_fixture`, `sample_docs`; `demo/ledgersmb-linkml`;
  `evals/datasets/*.yaml` and the RFC 0126 retrieval harness; the unit tests of
  each kernel's EKOS counterpart (`merge_branch_*`, the leak suite's inputs, the
  identity and conflicts tests), read as data.
- **The control.** EKOS's own output on the same inputs: `ekos graph export
  --format ndjson [--as-of]` for objects and relationships; evidence records
  need a second path.
- **The law.** Zero *unexplained* differences. Every divergence is classified:
  EKOS defect (an upstream issue with the counterexample), VerEKOS defect, or a
  stated non-goal. The assurance scale is the five labels from the
  hyperdreggmedia audit (proved / conditional / executable property /
  cross-language / design target).
- **Not measured.** Search relevance, model-pass quality, parser coverage.

## 5. What flows back

Verified by the root at the cited lines on 2026-10-19 and filed the same day as
alexeyban/EKOS#10 to #16 (`notes/upstream-issues.md` has each link):

1. Evidence ids are random, so a cache miss forks every touched object's version.
2. `ekos_clickhouse_query` appends to the knowledge ledger.
3. Compiled semantic edges and the rollup object are written with no evidence.
4. The Runtime's read-only promise is a convention: split a read trait.
5. The human-only guards are string scans a rename evades.
6. RFC 0007 no longer describes the shipped identity algorithm.
7. `ekos_identity_review` also confirms `AuthorizedBy`; `CLAUDE.md` says `SameAs`.

Later: a stated model of P8 EKOS can cite; kernel binaries as drop-in checkers;
a persisted branch conflict (P13) instead of a printed one.

## 6. Milestones

| | Deliverable | Number that proves it |
|---|---|---|
| M0 | this design; six memos harvested; issue drafts | done except D2 |
| M0.5 | the scoreboard: panels, control dumps, the diff classifier | EKOS's own numbers reproduced on every panel first |
| M1 | `Ledger` + `Branch` kernels: theories, theorems, SML binary | `object_at`, `diff` and `merge_branch` identical to EKOS on the ecommerce fixture and the `merge_branch_*` cases |
| M2 | `Scope` kernel with the BD-security instantiation | the leak-suite inputs: identical visible sets; a disabled filter is caught |
| M3 | `Identity` kernel | identical merge groups and pending edges on all fixtures |
| M4 | `Conflicts` kernel, with coverage | identical conflict set on LedgerSMB |
| M5 | the EKOS world: schema, import family with redaction, laws (evidence required, human review), one connector as a grain, on a scratch minidregg world | an admitted commit and a refused one, with receipts |
| M6 | `EKL` + `Impact` | identical results on the ekl and impact tests |

## 7. What VerEKOS will not claim

That a parser read the schema correctly. That a model's description is true. That
a search result is relevant. That a secret of a shape the pattern table does not
name was caught. That minidregg's or breadstuffs' theorems hold (imported, not
re-proved; and breadstuffs' categorical claims are known not to be the standard
notions). That anything here is built.

## 8. What the scouts corrected (revision 1 → 2)

- **A** (`notes/A-invariants.md`): P1 split into log vs state (attribute-level
  retraction exists); object ids default to v4; Runtime read-only, pass
  determinism, evidence-for-every-conclusion and secrets-never-stored are
  convention; the human-only guards are string scans; RFC 0007 drift.
- **B** (`notes/B-minidregg-map.md`): the real minidregg names (`LinkRecord`,
  `AnnotationRecord`, `ConflictRecord`, `VersionEventRecord`, `ObserverLens`);
  a regex redaction law does not fit `Pred`; sealed-by-default disclosure; no
  `object_at` or domain-time carrier; Objective Bend is not a pass language yet.
- **C** (`notes/C-afp.md`): the AFP list cut to four imports and two side
  sessions; most properties are plain HOL; the snapshot is AFP 2025-2.
- **D1** (`notes/D1-upstream-review.md`): random evidence ids fork versions;
  `ekos_clickhouse_query` writes; evidence-less edges and rollups; the review
  tool is wider than documented.
- **E** (`notes/E-veri7vn-lessons.md`): EKOS ships no scoreboard; freeze the
  export recipe; owners end to end, not scouts; pre-register the drain.
- **F** (`notes/F-revision-system.md`): EKOS is already a patch store; it has
  branches and a merge revision 1 omitted; minidregg's content cell is mutable
  and refuses duplicates rather than ignoring them; heights are linear-log only;
  `ConflictingEvidence` is a `ConflictRecord`; `transclusion_pinned` is the
  evidence-pin law; breadstuffs' Pijul-shaped system was not imported.
