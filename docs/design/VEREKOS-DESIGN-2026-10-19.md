# VerEKOS design, 2026-10-19 (revision 3, same day)

Written by the root (Fable 5.1). Revision 1 came from reading EKOS, veri7vn and
minidregg. Revision 2 folded in six scout memos (`../../notes/`, A to F). Revision 3
folds in five design explorations (`explorations/00` to `04`): the root's vision
note, the docworld integration (Opus), the claim primitive tested to breaking
(Opus), the scoreboard (Sonnet) and the amplification catalogue (Sonnet). Where a
memo or exploration and this document disagree, the one with the path and line
wins. §11 is the ledger of what each revision corrected.

Nothing here is built. Every name marked (new) is a proposal.

## 0. In one paragraph

EKOS is an enterprise knowledge compiler whose value is a short list of promises
about a ledger and its readers. minidregg is a shared world of documents, rooms,
grains and residents whose authority, receipts and history are proved in Lean.
Neither has the other's half: EKOS keeps its promises by tests, source-scanning
guard tests and convention; minidregg can say who changed what and whether it
was allowed, but not what anything means. VerEKOS puts the compiler inside the
world with no kernel change (each compiled object is one document cell; evidence
is a pinned snapshot transclusion; laws refuse the wrong writes; a lens is the
read-only Runtime), re-derives the compiler's decisions as verified kernels, and
scores both against EKOS's own fixtures with EKOS as the control. The single
record under all of it is a **claim** pinned to source or to other claims, with
a **receipt** per log entry and a status computed from review claims.

## 1. What EKOS promises, and how each promise stands

Lane A's census (`notes/A-invariants.md`) has 60 rows; these thirteen carry the
product. Status is as verified by the root at the cited lines on 2026-10-19.

| # | Promise | Stands? |
|---|---|---|
| P1 | The log only grows; a version is a diff of assert/retract facts; identical content appends nothing | holds; the log/state distinction (attribute retraction) is undocumented |
| P2 | `object_at` is a fold of the log prefix; `diff` is the union of write footprints | holds on the linear `TxId` order |
| P3 | Every compiled object and relationship cites evidence | **fails**: semantic edges and rollups are written with empty evidence (EKOS#12) |
| P4 | Passes are deterministic | **fails on a cache miss**: evidence ids are random v4 and sit inside the object's content signature (EKOS#10) |
| P5 | The Runtime is read-only | convention: the trait it holds has the write methods (EKOS#13); `ekos_clickhouse_query` writes (EKOS#11) |
| P6 | Merge iff exact normalized names; fuzzy is a pending edge; traversal skips pending edges | holds for `SameAs`; hypothesis `ExplainedBy` edges carry no status and are walked (EKOS#17) |
| P7 | Conflicts are kept, normalized, pure, order-independent | holds; the surviving object is the last read, by caller path order |
| P8 | Read scope: deny wins, both ends, unattributed hidden, per-call scope only removes | holds; the leak suite is the strongest empirical check in the repo |
| P9 | Secrets never enter: redaction at every raw-content entry point | **fails** for two readers added after RFC 0043 (EKOS#18, #19); one span reader skips exclusions (#20) |
| P10 | Human-only decisions are unreachable from agents | holds against omission; string scans a rename evades (EKOS#14) |
| P11 | Domain time and observation time are distinct | holds; the compile never writes a validity window |
| P12 | Freshness manifest and session anchors detect staleness | holds, as metadata |
| P13 | Branch merge is skip-if-present; divergence is reported, never overwritten | holds; the report is printed, not stored, and merged history is flattened |

Also true and undocumented: an object a later compile no longer emits stays
current forever; object ids default to random v4 with stable v5 keys only where
an analyzer assigns one.

## 2. The model: claim and receipt

Exploration 02 tested the root's hypothesis that EKOS has one primitive and came
back with two records and four amendments. This is the model both layers below
are instances of.

- A **claim** is a typed payload about one subject. Its identity is v5 of
  (schema, subject key, the set of source *documents* asserting it): never of a
  range, a revision or a run. It carries one or more **pins** and a domain
  validity window.
- A **pin** is a target plus the revision it was read at. The target is a range
  of an imported source, or another claim. Evidence is a pin, not a claim; the
  fragment is derivable by rendering the pin.
- A **receipt** is one log entry: transaction number, put or retract of a claim,
  author (principal kind and name), run and stage. Provenance and observation
  time live here, never on the claim, or every re-run would fork a version.
- **Status is not stored.** It is a fold over **review claims**, each pinned to
  the reviewed claim's core digest. A review holds while the core is unchanged;
  when the core changes the status becomes `needsReview` and the old review is
  kept. EKOS's three hand-written `carry_forward`s and the session fingerprint
  become one definition.
- The EKOS **object is a view**: the join of the per-source claims about one
  subject. There is no last-read survivor; two definitions of `orders` are two
  claims and a conflict is a claim pinned to both.

What the one record makes impossible to write down: a random evidence id
(there are no ids on pins), a status-less hypothesis edge (status starts at the
schema's initial state), an unattributed object (pins are nonempty by law), a
compiler that advances a status (only a permitted principal's review does).
What failed: a *monotone* status lattice. EKOS reverses decisions and demotes
`confirmed` to `needs_review`; what holds is authority monotonicity. What stays
per kind: normalization tables, identity name rules, EKL, rank fusion,
redaction.

## 3. The world layer (Lean, against minidregg, no kernel change)

Exploration 01 read the deployed `Kernel/ContentResource.lean` and corrected four
scout claims (§11). The embedding that survives:

**Records (all schemas new, as `DocumentRecord.schema` digests).**
- `ekos/source/v1`: one imported file; one `text` atom per statement with the
  redacted bytes; a header atom with source key, path, redaction-table digest
  and pipeline versions. **The client chooses the `AtomId`**, so the importer
  derives it from a structural key (`create-table:customers`), and a re-import of
  an unchanged file submits nothing (an empty command is refused anyway). A pin
  moves exactly when its statement changed. This is the stable identity across
  re-imports that revision 2 flagged as missing.
- `ekos/object/v1`: one cell per compiled object (one document per cell is a
  `ContentLaw` constraint). Properties in an `inlineObject` atom (not
  `FieldRecord`s: no deployed action writes one). One container per evidence
  record holding a meta atom and a **snapshot transclusion** of the source
  statement. One container per outgoing edge holding an edge atom (kind,
  properties, validity window, status), its own evidence containers and a
  `LinkRecord` anchored on the edge atom. This closes a gap no scout raised:
  `LinkRecord` has neither properties nor evidence, and `KirRelationship` has
  both. Backlinks come from the deployed `LinkIndex`, so depth-1
  `ekos_dependents` exists today.
- `ekos/manifest/v1`: the compile's current set, as external links keyed by
  logical key. Replaces `.ekos/semantics/current.json` and fixes "stays current
  forever": the compile unlinks what it no longer emits, history kept.
- `ekos/conflict/v1`: one per (subject, attribute); alternatives are
  transclusions, never inline values; **no `chosen` field**.
- `ekos/review/v1`: each human decision is an appended container holding a
  decision atom and a snapshot transclusion of the reviewed thing's header atom.
  **The transclusion is the carry-forward rule**: by `transclusion_pinned` the
  pin shows the same bytes or says `moved`, so a resolution holds exactly while
  the conflict's signature is unchanged and reopens when it changes. RFC 0172's
  `carry_forward` and RFC 0151's staleness are one kernel theorem.
- `ekos/compile-run/v1` and `ekos/replay-attestation/v1`: input pins with read
  heights, compiler identity, output list, SHA-256 of the command bytes; a
  **verifier** principal replays and attests. Determinism is not admitted
  without a kernel change; it is attested, and a lens labels a cell
  `replayedDeterministic` only when an attestation by a principal other than
  the compiler exists. A replay that differs is a counterexample to P4.

**Laws**, in the deployed `doc new --law` `Pred` shape: L-src (only importers
write source cells), L-obj (only the compiler writes compiled cells; no
annotations or marks; **a birth must carry at least one transclusion**, a count
form of P3), L-rev (only named human reviewers write review cells, append-only),
L-run (append-only audit). `Pred` reads integer slots only, so redaction stays a
client obligation, now at one entry instead of four, and a pass that reads
outside the world is detectable by the replay. Whoever holds `installPolicy` on
a review cell can replace its law, so the human-only guarantee rests on the
compiler and residents never holding that capability.

**The Runtime is an `ObserverLens`** whose dependencies are the cells the
manifest lists and the reader's scope admits. Read-only is the type of a lens.
`project_eq_of_clean` makes the scope-keyed result cache correct by
construction. **Session isolation is a one-line theorem**: exclude session-note
cells from the dependencies and `locality` says no note can change any answer,
replacing EKOS's guard test.

**Read scope is enforced twice.** At admission: transcluded bytes render only
through the reader's own read of the source, and single-source compiled cells
take their source room's audience. In the lens: origins (source cells named by
transclusions, crossed with header paths) feed the Isabelle `Scope` kernel, and
`scope_noninterference` (new) is `locality` specialized to `dependencies ⊆ Vis`.
Honest limit: computing `Vis` reads origin metadata of hidden objects, so this
is noninterference relative to origins, not breadstuffs' `FogOfWar` standard
where a hidden cell is structurally absent. Reaching that is open. A conflict is
visible only if every alternative's origin is visible, so a one-source reader
sees no conflict, stricter than EKOS today and a correction to it.

**Identity**: an exact merge is a `SameAs` link with `status: confirmed`
canonicalized by the lens, reversible; atoms never change identity, so a re-key
is impossible by construction. **Connectors**: a grain does not submit
declarations (there is no path by which it signs a command); it fetches and
parses, a principal's client turns the result into a command, and one
`ekos-connectors` grain with several routes is right, never one grain per
connector. Filesystem sources need no grain.

**Where it lives**: a separate Lean project `~/dev/verekos/world/` (new)
requiring minidregg as a Lake dependency pinned to one commit. Three things
would be kernel changes and are minidregg's call: a compile effect family
admitted by re-execution (the Objective Bend publication precedent), a resolve
action for `ConflictRecord`, a field-write action.

**Retracted mismatch.** Revision 2's "sealed-by-default disclosure fights a
broadly readable corpus" was wrong: `DisclosureDecision` governs what a receipt
reveals, not encryption; readers read cells through observe grants and the
Runtime needs grants, not keys. Encryption is opt-in per atom.

## 4. The decision kernels (Isabelle/HOL)

Each is a HOL function with its theorem, exported with `export_code` and
`Code_Target_Numeral` to Standard ML, compiled with the MLton inside
Isabelle2026-RC1, run from a binary that reads EKOS's own JSON. Lane C trimmed
the AFP imports to `Bounded_Deducibility_Security` (the indistinguishability
wrapper for Scope), `UPF` (the allow/deny type), `Depth-First-Search` (impact,
has `export_code`) and `List-Index` (rank), with `Transitive-Closure` and
`Allen_Calculus` in side sessions if wanted. Never import anything that drags
`Deriving`/`Collections`/`Containers`; copy `Stratified_Datalog`'s `Main`-only
`Datalog.thy` if REASON needs it. The snapshot is AFP 2025-2; whether it builds
under RC1 is untested.

| Kernel | One theorem over the claim/receipt record | Stays per kind |
|---|---|---|
| `Ledger` | append-only; state is a fold; identical content has an empty footprint; `diff` is the footprint union | nothing |
| `Branch` | skip-if-present over receipts; a same-id different-value pair is a persisted Conflict claim | nothing |
| `Scope` | visibility is decided by pins, deny wins; both ends, evidence-through-visible and conflict hiding are corollaries | the origin matcher (globs) |
| `Identity` | merge = compiler-confirmed `SameAs`; canonical = class view; structural schemas never merge | `normalize`, `name_for_similarity`, thresholds |
| `Conflicts` | **coverage** (every disagreement yields exactly one conflict) and permutation invariance; no survivor | normalization tables, the label-mismatch rule |
| `Review` (new, absent from revision 2) | status is a fold over authorized reviews; compiler writes never change it; a review survives while the core does | each schema's `core` and `mayDecide`, as data |
| `Impact` | reachability from a seed over edges whose status and endpoints are facts | the typed-edge set, `is_doc_mention` |
| `Time` | windows on every claim, never compared with `tx` | nothing |
| `EKL`, `Fusion`, `Redact` | nothing | everything; "no secret leaks" is not a theorem and will not be claimed |

Untrusted, labelled so in every output: parsers, document extraction, model
calls, BM25 and vector scoring. veri7vn's recognizer rule.

## 5. The seam between two provers

An exported kernel binary is a grain, or a process the importer, compiler and
lens host call. minidregg treats grain output as a proposal; a proof inside the
binary is about the computation, the world's laws are about admission, and
neither trusts the other. The claim at the seam: the binary's output equals the
HOL function's value on the same input, and the world admits only what its laws
allow. Whether the Isabelle layer is permanent or scaffolding to remove once the
world layer exists is an open question the root holds (exploration 00).

## 6. The scoreboard (M0.5, before any theorem)

EKOS ships no panels, scorers or verdict files (lane E), and `ekos graph export`
is a thin control: nodes and edges only, no relationship ids, no edge properties
(a pending `SameAs` looks like a fact), no evidence, no versions (exploration 03).
So:

- **Panels** under `panels/` (new): fixtures run through the real pipeline
  (`tests/fixtures/*.sql`, `sample_project`, `git_fixture`, `sample_docs`,
  `demo/ledgersmb-linkml`); EKOS unit tests transcribed by hand with a drift
  checker (`merge_branch_*`, the scope and leak-suite inputs, identity and
  conflicts tests); `evals/datasets` reported as "not measured".
- **Control**: the real `ekos` binary for what it prints, plus a
  `scoreboard-dump` binary (new, its own Cargo workspace in
  `tools/scoreboard/control-dump/` with path dependencies on a pinned EKOS
  checkout) calling the library functions behind each kernel. It recomputes
  `content_signature` and self-checks against stored signatures rather than
  asking upstream to export it. Events have no control in M0.5. The Branch
  control also runs on SQLite, where `merge_branch` lives.
- **The law**: zero *unexplained* differences; every difference is EKOS defect,
  VerEKOS defect or stated non-goal, recorded in a signed manifest keyed by the
  difference's hash. Assurance labels: proved / conditional / executable
  property / cross-language / design target. The scoreboard compares EKOS
  objects with the model's **join view**, not with claims.
- **First checkpoint**: EKOS's own output reproduced on every panel, with
  non-reproducible fields named.

## 7. What flows back, and what we found and did not file

Filed 2026-10-19 as alexeyban/EKOS#10 to #20 (`notes/upstream-issues.md`), each
verified by the root at its lines. Six further read-only findings from
exploration 02 (backends disagree on A→B→A; merged edges keep pre-merge ids; a
confirmed same-source `SameAs` probably resets on recommit; scope origins are a
cross product; edge visibility ignores the edge's own evidence; the compile never
writes a validity window) are recorded there, not filed: ember asked to quiet
upstream and recenter on our own work. They feed the scoreboard's classifier.

## 8. Build order

| | Deliverable | Number that proves it |
|---|---|---|
| M0 | design, seven memos, five explorations, eleven upstream issues | done |
| M0.5 | the scoreboard (§6) | EKOS's numbers reproduced on every panel |
| M1a | **reader-local compile** (exploration 04's build-first): a friend's client reads their own documents with their own signed reads, runs EKOS over the copies, and gets find, two-hop impact and a disagreement list, each answer ending in a pin that re-checks as `same bytes` or `moved`. No node or kernel change; the ledger is the reader's | find/impact/disagree identical to EKOS on the same copies; pin checks measured |
| M1b | **slice 1 step 0**: does `transclude` work on a current Host build (J12C failed on 2026-09-30, the action landed later, no recorded run) | one recorded run, pass or fail |
| M2 | **slice 1** (exploration 01 §5): `ecommerce.sql` plus a 6-line `legacy_customers.sql` conflicting on `customers.email`, five principals, two rooms, four laws, six steps | seven receipts: a birth with a pinned transclusion; refusals for no evidence, for a compiler writing a review, for citing an unread source; a pin that says `moved` and a reopened conflict; a one-source reader who sees no conflict; a byte-identical replay |
| M3 | `Ledger` + `Branch` kernels | `object_at`, `diff`, `merge_branch` identical to EKOS on the fixtures |
| M4 | `Scope` kernel + `scope_noninterference` in the world | leak-suite inputs: identical visible sets; a disabled filter is caught |
| M5 | `Review`, `Identity`, `Conflicts` kernels | identical groups, pending edges and conflict sets; coverage holds |
| M6 | residents grounded in compiled knowledge; the `obend` analyzer reading the front end's own output | blocked on Hermes on a real node |

## 9. Traps (exploration 04, agreed by 01)

Writing EKOS passes in Objective Bend (Core4 has no digest term, no generic
object reads, no termination bound; the front end is a trusted boundary). Putting
the compiled ledger on the agreement mesh (consensus cost to carry a derived
value). One SPK grain per connector (root broker, generations, recovery per
grain; and it hides parsing from admission). Sealing the compiled corpus.
Letting a resident resolve conflicts.

## 10. What VerEKOS will not claim

That a parser read the schema correctly. That a model's description is true.
That a search result is relevant. That a secret of a shape the pattern table
does not name was caught. That minidregg's or breadstuffs' theorems hold
(imported, not re-proved; breadstuffs' categorical claims are known not to be
the standard notions). That `Vis`-relative noninterference is the `FogOfWar`
standard. That anything here is built.

## 11. Corrections ledger

**Revision 1 → 2** (scouts A to F): the log/state split and attribute
retraction; object ids default to v4; four promises are convention; the real
minidregg record names; a regex law does not fit `Pred`; no `object_at` or
domain-time carrier; the AFP cut to four imports; EKOS is a patch store with
branches revision 1 omitted; the content cell is mutable and refuses
duplicates; heights are linear-log only; `ConflictingEvidence` is a
`ConflictRecord`; `transclusion_pinned` is the evidence-pin law; breadstuffs'
Pijul-shaped system was not imported.

**Revision 2 → 3** (explorations 00 to 04):
- 01: properties cannot be `FieldRecord`s (no deployed action writes one);
  evidence cannot be an annotation on the source (`annotate` anchors only to
  the document being written), so it is a snapshot transclusion as revision 1
  said; "sealed by default" is receipt disclosure, not encryption, so the
  mismatch is retracted; a grain does not submit declarations; the client
  chooses `AtomId`, which gives stable re-import identity; `LinkRecord` lacks
  properties and evidence and the per-edge container supplies them; the
  manifest document fixes "stays current forever"; carry-forward is
  `transclusion_pinned`; determinism is attested, not admitted; session
  isolation and scope noninterference are `locality`; depth-1 dependents is the
  deployed `LinkIndex`.
- 02: two records, not one; status is a fold over review claims; pins target
  claims too; the EKOS object is a view; the monotone lattice is false of EKOS;
  a `Review` kernel is added to §4; the scoreboard compares the join view.
- 03: `graph export` is a thin control; a `scoreboard-dump` binary is needed;
  events have no control in M0.5.
- 04: build the reader-local compile first; the three traps; one connectors
  grain.
- 00: the three ambitions (checker, sibling, a world that knows itself) and the
  open question whether the Isabelle layer is permanent.
