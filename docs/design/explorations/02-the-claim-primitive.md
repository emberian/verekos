# 02. The claim primitive: one record, tested until it bends

Design lane, 2026-10-19. Read-only everywhere; nothing built or run. Every EKOS and
minidregg name below is cited at `path:line` from today's checkouts. Every name marked
**(new)** is a proposal. "Read, not run" means I traced the code by eye and did not execute it.

**Summary.**
1. **The hypothesis survives, in amended form.** It needs **two records, not one**: a `Claim` (the world's content) and a `Receipt` (one log entry). Provenance and observation time belong on the receipt. If they sit on the claim, every re-run forks a version, which is exactly upstream issue #10.
2. **Status is not a field of the claim.** It is a function of the claim set: the latest authorized *review*, which is itself a claim pinned to the reviewed claim's core digest. That one change turns EKOS's three hand-written `carry_forward`s into a definition.
3. **Pins must be able to target claims as well as source ranges.** Edges, conflicts, reviews, session anchors and proposals are all pinned to *claims*. "Unpinned authored claims" do not exist in EKOS: a session note pins its inbox line.
4. **EKOS's `KirObject` is not a claim. It is a view**: the join of the per-source claims about one subject. The claim's identity is v5 of (schema, subject key, the set of source *documents*), never of ranges, revisions or the run.
5. The "monotone status lattice" half of the hypothesis **fails**. EKOS lets a decision be reversed, and a changed claim demotes `confirmed` to `needs_review`. What holds is authority monotonicity: only a permitted principal's review changes status, and the compiler never does.
6. In minidregg, a claim fits as an **element of a compiled document** whose pins are snapshot transclusions and whose reviews are revision-anchored annotations. All six verbs it needs exist (`Kernel/ContentResource.lean:249-285`), so no kernel change is needed. The cost question is cells: one document per cell (`ContentResource.lean:14-15`).

---

## 1. The record

### 1.1 What EKOS actually stores, read against the hypothesis

| EKOS shape | Where | What it already is |
|---|---|---|
| `KirObject {id, name, kind, properties, evidence, created_at}` | `/Users/ember/dev/EKOS/ekos/crates/kir/src/lib.rs:193-202` | a payload plus evidence ids. The id defaults to v4 (`:14-16`) |
| `KirRelationship {…, from, to, …, valid_from, valid_until}` | `kir/src/lib.rs:382-404` | a payload naming two other ids, with a domain window. Its v5 id comes from `deterministic` (`:433-444`) |
| `KirEvidence {id, location, fragment, confidence: f32, created_at}` | `kir/src/lib.rs:355-361` | a pin (`location`), a copy of the bytes (`fragment`) and a weight. The id is v4 (`:366`) |
| `KirEvent {id, kind, subject, payload, evidence, occurred_at}` | `kir/src/lib.rs:508-516` | two different things: domain occurrences, and review receipts (§3, row E) |
| version = `diff(old_facts,new_facts)` of `FactOp::{Assert,Retract}` | `/Users/ember/dev/EKOS/ekos/crates/ledger/src/fact.rs:50-53`, `:377-400`; `fact_ledger.rs:722-736` | an attribute-level patch per object version, ordered by `TxId` (`fact.rs:38-40`) |
| `WriteContext {run_id, stage, source_artifact_id}` | `/Users/ember/dev/EKOS/ekos/crates/ledger/src/provenance.rs:35-47` | per-*transaction* provenance in a sidecar (`fact_ledger.rs:742-745`), outside the signature |
| conflict `status ∈ {open,resolved,dismissed}`, `REVIEW_FIELDS`, `carry_forward` | `/Users/ember/dev/EKOS/ekos/crates/semantic/src/conflicts.rs:29-48`, `:506-535` | review fields stored *inside* the claim and copied across compiles by hand |
| semantics `hypothesis → confirmed → needs_review`, its own `carry_forward` | `/Users/ember/dev/EKOS/ekos/crates/semantic/src/semantics_review.rs:3-7`, `:28-44`, `:115-140`; `HYPOTHESIS` at `business_semantics.rs:50` | the same pattern again, with a per-kind `core_fields` signature (`:48-90`) |
| `SessionClaim`: `tier: "T0"`, `review_status: "unconfirmed"`, an evidence on the inbox line, `AnchoredTo` carrying a fingerprint | `/Users/ember/dev/EKOS/ekos/crates/session/src/map.rs:16-17`, `:88-140`; `anchor.rs:82-128` | an authored claim **pinned to its inbox line** and to *other objects* through a projection digest |
| `MigrationProposal`, `status: "proposed"`, `evidence = source.evidence.clone()` | `/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/migrate_logic.rs:408-433` | a claim about one source object that inherits that object's pins |
| fuzzy `SameAs`, `status: "unconfirmed"`, `confidence`, with an evidence whose path is `"ekos compile (identity resolution)"` | `/Users/ember/dev/EKOS/ekos/crates/semantic/src/lib.rs:239-275` | a claim about two claims. Its "evidence" is a *stage name*, not a pin |
| identity review writes `status` and `reviewed_at` into the edge, plus a v4 `Merged`/`Modified` event | `/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/mcp.rs:2275-2319` | a decision with no reviewer identity and no check of the prior status |
| session lifecycle `Actor::Human`, `reviewed_by: "human"`, a `ClaimStatusChanged` event | `/Users/ember/dev/EKOS/ekos/crates/session/src/lifecycle.rs:17-21`, `:40-75` | "named principal" is the literal string `human` |

So EKOS has the hypothesis's shape in five places, written five ways. Four of them have
hand-copied review state: `conflicts::carry_forward`, `semantics_review::carry_forward`,
`commit.rs::preserve_claim_review_status` (`/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/commit.rs:464-495`),
and session anchors' fingerprints.

### 1.2 The definition (Lean 4, prover-neutral; every name here is **new**)

In plain words:
- A **claim** is a typed payload about one subject. Its identity comes from (schema, subject key, the source documents asserting it), and it carries one or more pins and a domain validity window.
- A **pin** is a target plus the revision it was read at. The target is either a range of an imported source, or another claim. A source revision is minidregg's per-atom `OperationId` list. A claim revision is the premise's core digest.
- A **receipt** is one log entry: the transaction number, a put or a retract of a claim value, who wrote it, and in which run and stage.
- **Status is not stored.** It is computed from *review claims*, which are claims whose single pin targets the reviewed claim at its core digest.

```lean
-- Abstract carriers; §4 instantiates them with minidregg's real types.
variable (SchemaId SourceId Range Digest Time RunId Stage KeyPart : Type)
variable (AtomRev : Type)            -- minidregg: AtomId × OperationId

structure ClaimKey where              -- "what is it v5 of?"
  schema  : SchemaId
  subject : List KeyPart              -- structural key (path, index…) or normalized name
  sources : List SourceId             -- sorted, deduplicated source DOCUMENTS; no ranges, no revisions
  deriving DecidableEq

opaque ClaimId : Type
opaque claimId : ClaimKey → ClaimId   -- premise: injective (minidregg states this as a premise too:
                                      -- `DigestDerivation`, Theory/Hyperdocument.lean:161-163)

inductive PinTarget where
  | source (doc : SourceId) (range : Option Range)   -- none = the whole document
  | claim  (id : ClaimId)                             -- edges, conflicts, reviews, anchors

inductive PinRevision where
  | atoms (read : List AtomRev)       -- the atoms of the range at the revisions read
  | core  (digest : Digest)           -- the premise claim's core digest when read

structure Pin where
  target   : PinTarget
  revision : PinRevision
  weight   : Nat                      -- per-mille; was `KirEvidence.confidence : f32`

structure Window where                -- domain time (P11); never TxId
  validFrom  : Option Time
  validUntil : Option Time

structure Claim (Payload : SchemaId → Type) where
  key     : ClaimKey
  payload : Payload key.schema
  pins    : List Pin                  -- law: nonempty
  valid   : Window

inductive Status where
  | observed | hypothesis | proposed | open | unconfirmed   -- the initial states, chosen per schema
  | confirmed | rejected | needsReview | resolved | dismissed

inductive PrincipalKind where | compiler | agent | human

structure Schema (Payload : SchemaId → Type) (s : SchemaId) where
  core       : Payload s → Digest              -- what a review and a staleness check compare
  structural : Bool                            -- custom_kinds.rs `structurally_keyed`
  initial    : Status
  isFact     : Status → Bool                   -- may traversal cross it?
  mayDecide  : PrincipalKind → Status → Bool   -- who may move a claim of this schema to what
  stated     : Payload s → List (Digest × Digest)  -- (attribute, normalized value): stated facts only

inductive Op (Payload : SchemaId → Type) where
  | put     (c : Claim Payload)
  | retract (id : ClaimId)

structure Receipt (Payload : SchemaId → Type) where   -- the second record
  tx     : Nat                        -- EKOS TxId (fact.rs:40)
  op     : Op Payload
  author : PrincipalKind × Digest     -- kind and named principal
  run    : RunId
  stage  : Stage
```

A **review** is the claim schema `Review` (new). Its payload is `{decision : Status}`. Its
single pin is `⟨.claim c, .core d, _⟩`, and its subject key is `(c, reviewer)`. Status is then a
fold:

```lean
/-- The status of claim `c` in log `L`: the latest review by a principal allowed to decide,
pinned at `c`'s *current* core digest; else needsReview if any review exists at an older
digest; else the schema's initial state. -/
def status (L : List (Receipt P)) (c : Claim P) : Status := …   -- (new)
```

### 1.3 Every EKOS kind as an instance

| EKOS kind | `schema` | `subject` | `sources` | pins | `initial` | who decides |
|---|---|---|---|---|---|---|
| `Table` | Table | `[normalized schema.table]` | the files that define it | one `source` range per `CREATE` | observed | none |
| `KirRelationship` `ForeignKey` | ForeignKey | `[from key, to key, disc]` | the DDL file | `claim from`, `claim to`, a `source` range | observed | none |
| `KirEvidence` | **not a claim** | | | it *is* a `Pin`. `fragment` is derivable by rendering the pin. `confidence` is `weight` | | |
| `KirEvent` (domain: `DeadEnd`, a simulated action, a git commit) | the event's kind | `[subject key, occurred_at]` | the source | a source range | observed | none. The window is `[t,t]` |
| `KirEvent` (review receipts `Merged`, `ClaimStatusChanged`) | **not a claim** | | | | | these are `Receipt`s of `Review` claims |
| `ConflictingEvidence` | Conflict | `[subject key, attribute]` (= `conflicts.rs:184`) | union of the members' | one `claim` pin per disagreeing claim, each at its core | open | human |
| `SessionClaim` | SessionNote | `[entry_id]` (= `map.rs:36-38`) | the inbox | a `source` pin on the inbox line, plus `claim` pins for anchors (`anchor_fingerprint` becomes `core`) | unconfirmed | human |
| `BusinessConcept` hypothesis | BusinessConcept | `[table, name]` | the predicate carriers | `source` ranges | hypothesis | human |
| `MigrationProposal` | MigrationProposal | `[source object key]` (= `proposal_id(source)`) | the source's | `claim source` at its core (not a copy of its evidence ids) | proposed | human |
| `SameAs` candidate | SameAs | `[canonical key, member key]` | union | two `claim` pins. The stage name moves to `Receipt.stage` | unconfirmed | agent or human (the tool is agent-reachable by design) |
| exact merge | SameAs | as above | union | as above | **confirmed by `compiler`** | compiler (rule) |
| a human review decision | Review | `[reviewed id, reviewer]` | the reviewed claim's | one `claim` pin at its core | the decision itself | whoever the reviewed schema's `mayDecide` admits |

## 2. The theorems one record makes possible

Each is stated once over `Claim`/`Receipt`. Statements only; nothing here is proved.

**(a) Append-only, and state is a fold.** The log only grows. The state at `t` is the fold of
the receipts with `tx ≤ t`, where `put` installs and `retract` removes. A put whose value
equals the current value appends nothing.
```lean
def state (L : List (Receipt P)) (t : Nat) : ClaimId → Option (Claim P) :=
  (L.filter (·.tx ≤ t)).foldl apply (fun _ => none)          -- (new)
def AppendOnly (step : List (Receipt P) → List (Receipt P)) : Prop := ∀ L, L <+: step L
def IdempotentPut : Prop := ∀ L c, state L ⊤ (claimId c.key) = some c → write L (.put c) = L
def DiffIsFootprint : Prop := ∀ L a b, diff L a b = ((L.filter (fun r => a < r.tx ∧ r.tx ≤ b)).map (·.op.id)).dedup
```
The EKOS realizer is `fold_state` (`fact_ledger.rs:1676-1694`). Lane F maps it to minidregg's
`run_append` and `checkpoint_suffix_equivalence`.

**(b) Pin staleness is decidable and honest.** A source pin is stale iff some atom it read now
has a different revision. A claim pin is stale iff the premise's current core differs from the
digest read. Rendering a stale source pin shows the pinned bytes or says `moved`, never other
bytes. That is minidregg's `transclusion_pinned` (`/Users/ember/dev/minidregg/Kernel/ContentResource.lean:2570-2579`),
with `pins : List (AtomId × OperationId)` (`:92-97`), used unchanged.
```lean
def stale (σ : World) : Pin → Bool
  | ⟨.source d _, .atoms read, _⟩ => read.any (fun (a, r) => σ.revisionOf d a ≠ some r)
  | ⟨.claim c,    .core dg,   _⟩ => σ.coreOf c ≠ some dg
  | _                             => true            -- ill-typed pin: stale, never fresh
```

**(c) Status changes only by an authorized review, and a review lasts while the core does.**
Compiler writes never change any claim's status. A review counts only if its author's kind is
admitted by the schema. While the reviewed claim's core digest is unchanged, its status is the
review's decision. When the core changes, the status becomes `needsReview` and the old review is
kept. This is EKOS `carry_forward` (`conflicts.rs:506-535`, `semantics_review.rs:115-140`) as a
**definition**, not a copy.
```lean
def CompilerCannotDecide : Prop := ∀ L r, r.author.1 = .compiler → isReview r → status (L ++ [r]) = status L
def ReviewSurvives : Prop := ∀ L c c', claimId c.key = claimId c'.key →
  core c = core c' → status (L ++ [put c']) c' = status L c
```
The hypothesis's "monotone in the lattice" **is not stated, because it is false of EKOS**. See §3 row K.

**(d) Traversal crosses only facts.** Every edge a traversal uses has endpoints and an edge
claim whose current status satisfies `isFact`, unless the caller asks for hypotheses. This also
covers nodes. EKOS checks only edges, through `is_pending_review` (`kir/src/lib.rs:480-485`),
which reads a *missing* status as confirmed. Here status is always defined, because it starts
at `Schema.initial`. So D2's "hypothesis `ExplainedBy` edges carry no status" cannot happen by
construction.

**(e) Visibility is decided by pins, and deny wins.** A claim is visible iff every pin is
visible. A source pin is visible iff its (source, path) origin is allowed and not denied. A
claim pin is visible iff the premise is visible. An object named by a deny rule is hidden
whatever else holds.
```lean
def visible (σ) (S : Scope) : Claim P → Prop
  | c => ¬ S.deniesId (claimId c.key) ∧ (S.allowsId (claimId c.key) ∨
         ∀ p ∈ c.pins, match p.target with
           | .source d r => S.allowsOrigin (d, r) ∧ ¬ S.deniesOrigin (d, r)
           | .claim i    => ∃ c', σ i = some c' ∧ visible σ S c')
```
The well-foundedness of this recursion is the acyclicity of the pin graph. That is a law, not a
given. Corollaries that EKOS proves by separate code paths: "relationship needs both ends"
(`scope.rs:446-452`), "evidence only through a visible object" (`:669-676`), and "a conflict is
hidden from a reader denied either side". The last one closes lane F's inline-alternatives
problem. EKOS's "unattributed is hidden" (`scope.rs:207-222`) becomes the law "pins are
nonempty": nothing is unattributed.

**(f) Conflicts are a pure function of the claim set.** For every subject and attribute, if two
current claims about that subject *state* different normalized values for it, there is exactly
one Conflict claim with that key. Its pins are exactly those claims at their cores. The set of
conflicts does not depend on input order, because the input is a `Finset` keyed by id.
```lean
def Coverage : Prop := ∀ σ subj a v₁ v₂ c₁ c₂, c₁ ≠ c₂ → about c₁ subj → about c₂ subj →
  (a, v₁) ∈ stated c₁ → (a, v₂) ∈ stated c₂ → v₁ ≠ v₂ → ∃ k, detect σ k ∧ k.key.subject = [subj, a]
def PermInvariant : Prop := ∀ (cs : Finset (Claim P)) …, detect cs = detect cs   -- trivial on Finset; the content is that `detect` takes one
```
There is **no survivor**. With per-source identity (§1.2), the two definitions of `orders`
are two claims. EKOS's last-read survivor (`conflicts.rs:310-323`) disappears, rather than being
proved order-independent.

**(g) Ids do not depend on the run.** `claimId` is a function of `ClaimKey` alone, and
`ClaimKey` contains no `RunId`, no time, no range and no revision. Pins carry no ids at all. So
EKOS's random evidence id forking every touched version (design §1 P4, `kir/src/lib.rs:366`)
cannot be written down.

## 3. Trying to break it

| | Pressure | Verdict |
|---|---|---|
| A | **Edges need two endpoints with different lifetimes.** | Handled. An edge is pinned to `claim from` and `claim to`. If either endpoint is retracted the edge pin dangles, and a law (new) chooses `invalidate`, as in minidregg's `EndpointDeathPolicy.invalidate` (`Theory/Hyperdocument.lean:387-394`). EKOS never meets this case because nothing retracts at object level (design §1). |
| B | **Evidence confidence is a float.** | Handled. `KirEvidence.confidence` is per pin (`kir/src/lib.rs:359`) and is `weight : Nat` per-mille. `SameAs.confidence` (`semantic/src/lib.rs:267-268`) is a payload field. This is the same scaled-natural move the design's §2.1 makes. |
| C | **EAV facts vs whole payloads: does a claim version per attribute or per object?** | Per *claim* (that is, per subject per source), with the attribute patch as the log's encoding. EKOS already keeps three equalities apart: storage (`content_signature`, `ledger/src/lib.rs:47-53`), review (`semantics_review::signature`, `:61-90`), and anchor (`anchor_fingerprint`, `session/src/anchor.rs:82-128`). The record names two of them: payload equality (dedup) and `Schema.core` (review and staleness). Attribute-level *conflicts* use `Schema.stated`. So no per-attribute claim is needed. |
| D | **`content_signature` excludes `created_at`.** | Handled by construction: no time is in the claim. Observation time is `Receipt.tx`, and domain time is `valid`. EKOS overloads `created_at`: the session mapper sets it to the note's `recorded_at` (`map.rs:82`, `:148`). |
| E | **Events are not claims; receipts have no status.** | **A second record is genuinely needed.** Domain events are claims with a point window and status `observed`. Review and status-change events (`mcp.rs:2304-2312`, `lifecycle.rs:66-73`) are the log. The log is `Receipt`. Provenance (`WriteContext`) goes there too, because it is per transaction in EKOS (`fact_ledger.rs:742-745`), and putting `run_id` in the claim would reproduce issue #10. |
| F | **`KirRelationship` validity window.** | Generalized. `valid : Window` is on every claim. EKOS today never writes one from the compile: `ckm_rel_to_kir` hard-codes `None, None` (`commit.rs:918-921`). |
| G | **Identity merges re-key.** | Handled by making the canonical object a view. An exact merge is a `SameAs` claim confirmed by the compiler principal. The canonical object is the equivalence class, represented by its least key (new: an order-free choice). Edges keep their original endpoint keys and are read through the class. This repairs an id drift found while reading: `apply_merges` rewrites `from`/`to` (`semantic/src/lib.rs:201-208`) but keeps the id that `deterministic` seeded with the **pre-merge** endpoint (`kir/src/lib.rs:439-441`), so the id no longer equals `deterministic(kind, from', to, disc)`. The merge also becomes reversible, which lane F already argued for. |
| H | **The `structurally_keyed` registry.** | Handled. It becomes `Schema.structural` (`kir/src/custom_kinds.rs:51`), and Identity's gate is "merge only non-structural schemas" (lane A row 24). The scan test `every_pipeline_custom_kind_is_registered` becomes "every claim has a schema", which is a type. |
| I | **Retraction.** | Handled, and it fixes "an object no longer emitted stays current forever". Because `sources` is in the key, the compile of source *S* owns exactly the claims keyed with *S*: whatever it last put and no longer emits, it retracts. Claims with several sources (edges between files, conflicts) are owned by the derived stage. Attribute-level `Retract` stays an encoding detail. |
| J | **"Authored claims have no pins."** | **False of EKOS**, and better false. A session note pins its inbox line (`map.rs:88-98`), and a review pins its claim. Amend: pins are always nonempty. "Authored" means pinned into a document the principal wrote. |
| K | **A monotone status lattice.** | **Fails.** `ekos_identity_review` sets any decision over any prior one and records no reviewer (`mcp.rs:2282-2301`). Semantics turns `confirmed` into `needs_review` when the signature changes (`semantics_review.rs:3-7`). EKOS's vocabularies are four sets under two property names: `status` for edges, conflicts and semantics, and `review_status` for session and architecture claims (`map.rs:137`, `commit.rs:486-489`). So the theorem is (c), authority and core-pinning, not order. What *is* monotone: per core digest, "undecided → decided" never returns to undecided. |
| L | **Per-source identity vs EKOS's single object id.** | It changes the data model, and it is the point. EKOS collapses same-id objects to the last-read one (`conflicts.rs:294-325`). Claims keep each source's assertion. The scoreboard must compare EKOS objects with the **join view**, not with claims. |

Read, not run (findings for the scoreboard; none is filed upstream):

1. **Backends disagree on A→B→A.** SQLite dedups on `(id, sig)` over all history (`ledger/src/lib.rs:520-531`). A return to A therefore repoints `current_objects` to A's old row (`:594-597`), while `object_at(now)` orders by `written_at` and returns B (`:789-794`). The fact backend compares only the current signature (`fact_ledger.rs:722-725`) and appends a third version. Under the record, a version is a receipt, so the fact backend is right.
2. **Probable: a confirmed same-source `SameAs` resets on the next commit.** The compile re-emits it with `status: "unconfirmed"` and a v4 evidence (`semantic/src/lib.rs:248-269`), and `write_relationships` has no review carry-forward (`commit.rs:67-87`). I did not check whether `resolve` skips pairs already confirmed in the ledger. A test should decide this before anything is filed.
3. **Scope origins are a cross product** of sources × paths (`ledger/src/scope.rs:290-311`). A two-source object is therefore judged on (source, path) pairings that never occurred. This fails closed, but paired pins (§2e) will diverge: under some scopes VerEKOS is more permissive. Classify on the scoreboard, and confirm whether EKOS can recover the pairing.
4. **Edge visibility ignores the edge's own evidence** (`scope.rs:446-452`). Under (e) an edge whose own pin is denied is hidden even when both ends are visible. That is a deliberate divergence, and stricter.

## 4. Against minidregg's records

| minidregg record | What it has of a claim | What it lacks |
|---|---|---|
| `AnnotationRecord {document, anchor, body, author, operation, visibilityPolicy, tombstonedAt}` (`Theory/Hyperdocument.lean:613-621`), anchor `atom (atom) (revision)` (`:598-602`) | a pin at an exact revision, an author, retraction, a visibility policy | one anchor only. Its id is caller-supplied (`AnnotatePayload.id`, `Theory/HyperdocumentOperations.lean:72-78`). No typed payload except `body := reference doc`. No status |
| `LinkRecord {sourceDocument, source, target, relation, author, operation, tombstonedAt}` (`:544-552`) | an edge as a typed, retractable record | no revision on its `source` range (`StableRange` has none, `:409-412`). It cannot pin an endpoint's *version* |
| `TransclusionRecord` + `TranscludeRequest.pins : List (AtomId × OperationId)` (`:557-564`; `ContentResource.lean:92-97`) | **exactly a source pin**, with `transclusion_pinned`, and disclosure decided by the reader's own read (`ContentResource.lean:46-53`) | it is a pin, not a claim |
| `ConflictAlternative {valueType, value, author, operation}` / `ConflictRecord {field, base, alternatives, regime, recordedAt}` (`:466-481`) | conflict keyed by `FieldKey {owner, name}` (`:452-455`) = (subject, attribute) | written only by `HyperdocumentMerge` (`Kernel/HyperdocumentMerge.lean:172`). Its value can be `.reference .document` (`FieldType`, `:422-437`), which would make alternatives *references to claims*, but no deployed action writes the `conflicts` or `fields` namespace |
| `FieldRecord {…, writtenBy, writtenAt}` (`:458-464`) | the natural home for a status | **no field-write action** in either six-verb vocabulary (`HyperdocumentOperations.lean:80-86`; `ContentResource.lean:249-285`). The only writer is the merge |
| `ResidentActivityRevision.Activity/Revision`, `apply`, `fold` (`/Users/ember/dev/minidregg/Kernel/ResidentActivityRevision.lean:21-62`, `:99-131`) | the shape of `status` as a fold: `other_author_cannot_revise` (`:64`), `stale_revision_cannot_revise` (`:73`), invalid revisions counted rather than dropped (`:104-128`) | research-only (`ResearchWip`, lane F §4) |

**Closest single record:** `AnnotationRecord`. **Closest composite, and the recommendation:**
a claim is an **element** of a compiled document (new schema digest per claim schema):
- `createContainer` + `createAtom` hold the payload. The **core** goes in its own atom, so that atom's `revision` changes iff `Schema.core` changes. Volatile keys (`ai_*`, `description`, line numbers: the `is_volatile` list, `anchor.rs:58-77`) go in a second atom.
- `transclude` writes the source pins.
- `link` writes claim-to-claim pins. Because `LinkRecord` lacks a revision, the pinned premise core goes in a transclusion of the premise's core atom instead.
- `annotate` on the core atom at its revision is a **review**. It is refused with `staleAtom` when the core moved (`ContentResource.lean:259-260`, `:444-445`), which is (c) at admission.
- `editElement` remove plus a tombstone is a retraction.

Laws (new, `Pred` over the request): the element id equals the derivation of `ClaimKey`; a
compiled claim has at least one transclusion (P3, closing the evidence-less edges); a review
annotation on a human-only schema needs a reviewer capability (`AuthenticatedPrincipal`,
`Theory/Hyperdocument.lean:244-267`). **No kernel change.** Status needs no field write,
because it is a fold over annotations.

**The open cost:** one document per cell (`ContentResource.lean:14-15`). Claims-as-elements in
one compiled document per *source* make per-source claims share a cell. Cell read grants then
coincide with source scope, which is a gift for (e). Multi-source claims need a derived document
whose transclusions each require the reader's own read. I could not measure how many elements
a cell holds in practice, or what transclusions cost per claim at EKOS scale.

## 5. What it buys the kernels (design §2.2)

| Kernel | Becomes one theorem over the record | Stays per kind |
|---|---|---|
| `Ledger` | (a) over `Receipt`, in place of four append paths (objects, relationships, evidence, events) and two backends | nothing |
| `Branch` | skip-if-present over receipts, with a same-id different-value pair stored as a Conflict **claim** (P13's printed report, persisted) | nothing |
| `Scope` | (e) once. Both ends, evidence through visible, conflict hiding and unattributed-hidden are corollaries | the origin matcher (glob semantics) |
| `Identity` | "merge = confirmed `SameAs`, canonical = class view, structural schemas never merge" | `normalize`/`name_for_similarity` per kind (`identity/src/lib.rs:609-636`), thresholds |
| `Conflicts` | (f) coverage and order-freedom, generic over `Schema.stated` | normalization tables (`normalize_type`, `conflicts.rs:62-86`), the label-mismatch rule (`:355-441`) |
| review lifecycle (absent from §2.2; propose adding it) | (c) replaces `conflicts::carry_forward`, `semantics_review::carry_forward`, `preserve_claim_review_status`, the session fingerprint, and the four mcp.rs string scans (as `mayDecide`) | each schema's `core` and `mayDecide` table, as data |
| `Impact` | (d): the edge filter is `isFact ∘ status`, for nodes too | the typed-edge set per query, `is_doc_mention` |
| `Time` | `valid` on every claim, never compared with `tx` | nothing |
| `EKL`, `Fusion`, `Redact` | nothing | everything |

## 6. What I could not verify

- Whether `resolve` consults the ledger before re-emitting a confirmed `SameAs` (finding 2).
- Whether review relationships from `review_candidates_for` reach `model.relationships`. I read the call at `semantic/src/lib.rs:761`, not the path into the CKM.
- How `MergeProposal.canonical_id` is chosen, and whether that choice is order-free.
- Whether EKOS can recover which source each evidence path belongs to (finding 3).
- minidregg cell capacity at EKOS scale, and whether any deployed path writes `fields`/`conflicts` other than `HyperdocumentMerge.lean:172` (grep found only that site in `Kernel/`).
- Nothing was built. The Lean above is a sketch whose names are all new and which has not been elaborated.
