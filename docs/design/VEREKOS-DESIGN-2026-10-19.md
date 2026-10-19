# VerEKOS design, 2026-10-19

Written by the root (Fable 5.1) after reading EKOS (`~/dev/EKOS`, 188K lines of
Rust, 207 RFCs, 281 devlogs; our checkout equals upstream `alexeyban/EKOS` main),
veri7vn (`~/dev/o7vn`) and minidregg (`~/dev/minidregg`). Five scout memos were
commissioned the same day (`../../notes/`); where they contradict this document,
the memo with the path and line number wins and this document is to be amended.

## 1. What EKOS actually promises

EKOS's product claim is not an algorithm. It is a set of properties of a ledger
and of the people and agents reading it. From `CLAUDE.md` and the RFCs, stated
as the theorems they want to be:

| # | Promise | Where EKOS keeps it today |
|---|---|---|
| P1 | The ledger only grows. An append under an existing id with different content is a new version; identical content is a no-op (content signature). | RFC 0004; both backends; no delete or tombstone exists |
| P2 | `object_at(id, t)` is the latest version written at or before `t`, and so a function of the log prefix. Diff over `(from, to]` lists exactly the ids with a version in that window. | `fact_ledger.rs`, tests |
| P3 | Every object and relationship written by `compile`/`commit` carries evidence ids that resolve to `KirEvidence` records naming a source location and fragment. | review; `evidence: Vec<KirId>` is `serde(default)`, so the empty vector is representable |
| P4 | Compiler passes are deterministic: same artifacts in, same ids and content out, in any input order. Ids are v5 of a stable key, not fresh v4. | RFC 0072/0135 Part C audit of ~134 sites; tests per pass |
| P5 | The Runtime is read-only; AI agents reach knowledge only through it (MCP). Two review tools write, nothing else. | trait shape; source-scan tests that `commands/mcp.rs` never names `apply_review`, `resolve`, lifecycle, approvals |
| P6 | Identity: two objects merge only when their normalized names are exactly equal and neither kind is structurally keyed; a fuzzy match becomes an `unconfirmed` `SameAs` edge, never a merge; pending edges are never traversed as facts. | RFC 0007/0060/0063/0135 D; `every_pipeline_custom_kind_is_registered` |
| P7 | Conflicts: when sources disagree about a stated fact, both claims are kept, normalized before comparison, and the disagreement is an object with a `Disputes` edge; detection is pure and order-independent; a review survives while the claims' signature is unchanged. | RFC 0172; reversed-input test |
| P8 | Read scope: deny wins; an object found in two sources needs both allowed; an object the compiler could not attribute is hidden from a restricted reader; relationships need both ends visible; evidence only for visible objects; a per-call scope can only remove. | RFC 0181; `ScopedStore`; the leak suite `crates/cli/tests/read_scope.rs`; `every_store_method_has_a_decision_here` |
| P9 | Secrets and PII never enter the artifact store or ledger: a built-in pattern table runs at every raw-content entry point and configuration can only extend it. | RFC 0043; three entry points, each remembering to call `ekos_common::redaction` |
| P10 | Human-only decisions (confirm/reject identity, resolve conflicts, confirm semantics, approve migrations, session lifecycle) are unreachable from any agent surface. | source-scan tests over `commands/mcp.rs` |
| P11 | Domain time (`valid_from`/`valid_until`) and observation time (`object_at`) are distinct questions and never conflated. | RFC 0047; type separation |
| P12 | Freshness: a committed manifest of (path, size, mtime[, hash]) tells whether the ledger still matches the source; session-memory anchors go stale when the anchored object changes. | RFC 0171/0151; metadata only |

Everything in the right-hand column is either a test on one implementation or a
test that greps another file's source. None of it is a statement about all
inputs. P3, P4 and P9 in particular are kept by discipline over a growing number
of call sites (RFC 0135 counts them), which is the shape of promise a model keeps
by construction and a codebase keeps by attention.

## 2. Two layers, because there are two kinds of promise

P1, P2, P3, P5, P8, P9, P10, P12 are promises about **a world**: who may write,
what a write must carry, who may read what, what a reader can conclude. P4, P6,
P7, P11 and the query language are promises about **decisions**: pure functions
from typed inputs to typed outputs. veri7vn verified decisions (kernels) and left
the world to Python. EKOS's value is mostly in the world. So VerEKOS has two
layers with two different proof styles and, probably, two provers.

### 2.1 The ledger as a world (Lean, against minidregg)

ember's question: is EKOS expressible as a minidregg system, inside its document
runtime and SPK grains, not as a privileged kernel component? Reading
`Theory/Hyperdocument.lean` and `HyperdocumentOperations.lean` beside
`kir/src/lib.rs`, the correspondence is close enough to be suspicious:

| EKOS | minidregg | Note |
|---|---|---|
| `KirObject` with `properties` | a document whose elements are `inlineObject (schema)` atoms | the `Custom(kind)` registry is a schema digest |
| `KirRelationship` (typed, directed, with properties, validity window) | a link record between two documents, typed by schema | both ends must exist; P8's "both ends visible" is a view rule |
| `KirEvidence` = (`SourceLocation`, `fragment`, `confidence`) | a **snapshot transclusion** of a range of a *source document* pinned at the revision read | this is the big one: EKOS stores the fragment text as a copy; minidregg stores a durable reference whose pin goes stale by revision comparison with no copy beside it. Freshness (P12) and session anchors fall out of the document model instead of being a manifest |
| content signature idempotence, versions | typed digest identifiers with domains (`IdDomain`), `revision : OperationId` on every record | P1/P4 by construction; the domain separation is stronger than EKOS's single uuid space |
| `object_at` | causal history + canonical cells; a derived view at a height | P2 |
| connector (`Observer`) | an SPK grain: untrusted, sandboxed, produces a *proposal* | the grain cannot write the ledger; its output is admitted or refused |
| redaction at the entry point (P9) | a **law** the kernel checks at admission over the proposed atoms | prevention control that cannot be forgotten by a new entry point, because there is only one entry: admission |
| compiler pass determinism (P4) | admission by re-execution: the receiver re-runs the front end and compares | minidregg already does this for Objective Bend packages |
| human-only review (P10) | a capability whose lineage names a human principal; the mark is an `annotate`/`mark` action signed by it | enforced by authority, not by a grep over `mcp.rs` |
| `ConflictingEvidence` + `Disputes` | an annotation on the disputed atom carrying both claims' transclusions | |
| Runtime, read-only (P5) | a canonical reactive view | the view is derived; nothing it exposes can write |
| `ReadScope` (P8) | read roots + the reader's capability | deny-wins and "attributed to no source means hidden" need to be stated as the view's law |
| MCP tools | Hermes/resident tools over the authorized view | |

Where minidregg forces things EKOS does not have: principals and signatures on
every write, funding and tariffs, encrypted (`sealedObject`) fragments, receipts.
For an enterprise knowledge ledger the first and last are features (an audit
trail is RFC 0135's unfinished Part B); funding is a burden to be set to a
free tariff; sealed fragments are what P9 wants to become eventually (a fragment
the reader cannot decrypt is one the reader cannot leak).

The mismatches to resolve (lane B will sharpen these):

1. **Evidence as copy vs evidence as reference.** EKOS's `fragment` is the text
   itself, redacted, and the source may be gone. A snapshot transclusion needs the
   source to be a document in the world, so connectors must first *import* source
   files as documents (sealed, if they are not for every reader), then compile
   over them. That is more storage and a real ingestion step, and it makes P9 a
   law over the import, which is where it belongs.
2. **Scale and query.** A minidregg world is built for rooms and documents;
   EKOS ledgers hold hundreds of thousands of objects and need BM25, vector search
   and rank fusion (RFC 0118-0126). Those are *views*, and can stay in Rust as
   untrusted indexes over the admitted world, with the fused ranking a kernel
   (see 2.2). The question is only whether the world's read path is fast enough
   to be the source of truth the indexes are built from.
3. **Objective Bend is not a compiler-pass language yet.** Identity resolution and
   conflict detection are plain functions over finite graphs; they belong as Lean
   functions behind laws (or as exported Isabelle binaries in grains, below), not
   as Objective Bend programs, until Core4 has what a pass needs.

Decision for this design: **model EKOS as a minidregg world, as a law package plus
a document schema plus grains, with no change to minidregg's kernel.** Lane B's
memo decides whether that is written inside `~/dev/minidregg` (a world
definition) or here as a Lean project that imports its theories.

### 2.2 The decisions as kernels (Isabelle/HOL, the veri7vn pattern)

Each is a HOL function with its theorem, exported with `export_code` to Standard
ML, compiled with the MLton inside Isabelle2026-RC1, run from a binary that
reads EKOS's own JSON. The binary is also, trivially, an SPK grain.

| Kernel | Statement (plain words) | AFP to lean on | EKOS control |
|---|---|---|---|
| `Ledger` | append-only log of the four primitives; `object_at` is a function of the prefix; content-signature idempotence; `diff` exact | HOL-Library; `Nano_JSON` for canonical bytes | a JSONL dump of a ledger built from `tests/fixtures/ecommerce.sql`, compared answer by answer |
| `Scope` | deny wins; composition only removes; both ends; "none" is inside a deny and outside an allow; a restricted reader's answers are a function of the visible objects alone (a BD-security / noninterference statement) | `Bounded_Deducibility_Security`, `BD_Security_Compositional`, `UPF` for the policy combinators | the inputs of `crates/cli/tests/read_scope.rs`, which must keep failing when a filter is disabled |
| `Identity` | merge iff exact normalized-name equality and not structurally keyed; the merge relation is an equivalence and its closure is order-independent; fuzzy becomes a pending edge; traversal never crosses a pending edge | `Transitive-Closure`, equivalence closure from HOL | `ekos-identity` tests, `DefaultResolver` on the fixtures |
| `Conflicts` | detectors are pure and permutation-invariant; type normalization is an equivalence; a signature is stable under line moves | HOL | `semantic/src/conflicts.rs` tests, LedgerSMB demo |
| `Impact` | dependents/impact = reachability over typed edges with pending edges removed, bounded by hops | `Transitive-Closure`, `Relational_Paths` | `ekos_impact` on fixtures |
| `EKL` | a relational semantics for FIND/WHERE/ORDER/GROUP/COUNT/AS OF; a REASON rules planner as stratified Datalog | `Stratified_Datalog`, `Query_Optimization` for the algebra | `ekl` tests |
| `Time` | validity windows vs observation cuts; the two never conflated | `Allen_Calculus` | RFC 0047 tests |
| `Fusion` | reciprocal rank fusion is monotone in each input ranking and ties are deterministic | HOL | `retrieval.rs` tests |
| `Redact` | no string matching a baseline pattern survives; extension cannot disable | `Regex_Equivalence` or a hand-written matcher for the pattern table | the RFC 0043 tests |

Lane C's memo is the authority on which AFP entries fit and what the snapshot at
`~/isabelle/afp-2026-05-29` needs to build under Isabelle2026-RC1.

Untrusted, by construction, and labelled so in every binary's output: SQL and
code parsing (sqlparser, tree-sitter), document extraction, every model call,
BM25 and vector scoring. Their outputs are typed inputs to kernels, exactly as a
recognizer's output is in veri7vn. EKOS already takes this posture for its LLM
passes (a model's answer is a `T0` proposal); VerEKOS extends it to the parsers.

## 3. Why two provers, and the seam between them

A single toolchain would be cheaper. Lean alone loses the AFP entries in 2.2 and
veri7vn's working export pipeline and hbox build tooling (`tools/dev/check-native`,
`remote-build`). Isabelle alone means re-inventing authority, admission, read
roots and receipts, which minidregg has spent a year proving. The seam that lets
both exist without sharing a logic: **an exported kernel binary is a grain.**
minidregg treats grains as untrusted physical processes whose outputs are
proposals; a proof inside the grain is about the computation, the world's laws
are about admission, and neither needs to trust the other. VerEKOS's claim at
the seam is modest and checkable: the grain's output equals the HOL function's
value on the same input (export_code correctness), and the world admits only
what its laws allow.

## 4. The scoreboard

veri7vn's rule holds: a claim about behaviour comes with a number. The control is
EKOS itself on the same inputs.

- **Panels.** `tests/fixtures/{ecommerce,northwind,mysql_hash_comments}.sql`,
  `sample_project`, `git_fixture`, `sample_docs`; `demo/ledgersmb-linkml`;
  `evals/datasets/*.yaml` (adversarial, architecture, code, dependencies, history,
  lineage, security) and the RFC 0126 retrieval harness.
- **The law.** Zero *unexplained* differences. Every divergence between a kernel
  and EKOS is classified: EKOS defect (becomes an upstream issue or PR with the
  counterexample), VerEKOS defect, or a stated non-goal of the model.
- **Not measured by this.** Search relevance, model-pass quality, parser
  coverage. Those stay EKOS's.

## 5. What flows back

- Guard tests EKOS can adopt now, found by lane D's review, each with its
  counterexample: evidence-less writes, fresh-v4 ids in a pass, a read path that
  opens the store without `ScopedStore`, a hypothesis-status edge that traversal
  walks as fact.
- RFC amendments where the text and the code disagree (lane A).
- A stated model of P8 that EKOS can cite instead of the leak suite alone.
- Later: kernel binaries as drop-in checkers (`ekos doctor --verify-scope`).

## 6. Milestones

| | Deliverable | Number that proves it |
|---|---|---|
| M0 | this design; five memos harvested; the EKOS ledger JSON dump path found | memos in `notes/`, each with paths |
| M1 | `Ledger` kernel: theories, theorems, SML binary | `object_at` and `diff` identical to EKOS on the ecommerce fixture, every id |
| M2 | `Scope` kernel + the noninterference statement | the leak-suite inputs: identical visible sets; a disabled filter is caught |
| M3 | `Identity` kernel | identical merge groups and pending edges on all fixtures |
| M4 | `Conflicts` kernel | identical conflict set on LedgerSMB |
| M5 | the EKOS world: schema, laws (evidence-required, redaction, human-review), one connector as a grain, on a scratch minidregg world | an admitted commit and a refused one, with receipts |
| M6 | `EKL` + `Impact` | identical results on the ekl and impact tests |

## 7. What VerEKOS will not claim

That a parser read the schema correctly. That a model's description is true. That
a search result is relevant. That a secret of a shape the pattern table does not
name was caught. That minidregg's own theorems hold (we import them, we do not
re-prove them). That anything here is built: see the README.
