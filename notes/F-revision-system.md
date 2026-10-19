# F. The revision system: what breadstuffs built, what minidregg kept, what it means for VerEKOS

Lane F scout memo, 2026-10-19. I only read `~/dev/minidregg` and `~/dev/breadstuffs` and wrote nothing to either. I built nothing and ran nothing (no lake, no cargo). Every "proved" below means the source states a theorem with a proof term and an axiom pin. I did not check that it currently compiles. Line numbers are from today's checkouts.

## 1. Summary

1. Breadstuffs built a patch system shaped like Pijul (Mimram–Di Giusto patch theory). The Rust crate `dregg-doc` has 18,943 lines in `src/`. The Lean side is five `Dregg2/Deos/*.lean` theories. A document is a graph of alive/dead atoms with order edges. Merge is a total union. A conflict is a stored antichain. Patches have dependencies, commutation, unrecord and cherry-pick.
2. **Minidregg did not import it.** Decision record D-0005 (2026-08-09) says it "Replaces: the parallel Breadstuffs document heaps, patch histories, transclusion demos" and caps every patch and pushout claim. What landed instead:
   - a content-addressed causal version DAG;
   - guarded store patches;
   - a merge that is deliberately not commutative and turns every multi-source field into a stored `ConflictRecord`.
3. Several pieces survived in re-derived form:
   - stable atom identity, tombstones and endpoint-death policies (`StableRanges`);
   - conflict records that carry provenance;
   - the split between I-confluent and conflict-bearing state (`Confluence`, `Pred/CoordinationDial`);
   - the LaceMerge keyset join;
   - a real commutation theorem for plans whose footprints are independent (`PlanBinding.independent_commute`).
4. **Evidence.** The document merge is *compiled* only, at maturity level S/A, and no Host code calls it. What is *deployed* is optimistic concurrency per revision: a stale edit is refused. History is a linear log indexed by height.
5. **For VerEKOS.** EKOS's fact ledger already stores each version as an assert/retract patch, so a guarded-patch model fits P1 and P2 better than the design's reading. Conflict-as-record fits `ConflictingEvidence`.
   - Patch merge is the wrong tool for compiled output: recompile from the merged sources instead.
   - It fits worse for read scope (the competing values are stored inline) and for identity merges (atoms never change identity).
   - The design missed EKOS's own branch/merge feature (RFC 0011). It also misstates where minidregg's append-only guarantee lives and how its idempotence works.

## 2. What the revision system is

### 2.1 Breadstuffs: `dregg-doc` plus `Dregg2/Deos` (the Pijul-shaped system)

**Model.** The crate header (/Users/ember/dev/breadstuffs/dregg-doc/src/lib.rs:1-14) describes the model:
- a document is "a **graph of alive/dead content atoms** with order-edges";
- an edit is a patch (`Add` / `Delete`(tombstone) / `Connect`);
- merge is "the categorical **pushout** computed as a total graph union";
- a conflict is "a *first-class STATE* … never a merge failure".

**Types.**
- `DocGraph { atoms: BTreeMap<AtomId, Atom>, edges: BTreeMap<AtomId, BTreeSet<AtomId>>, fields: BTreeMap<String, Vec<FieldAssign>> }` (/Users/ember/dev/breadstuffs/dregg-doc/src/graph.rs:46-55).
- `Op::{Add, Delete, Connect, SetField{superseding}, Resurrect, Disconnect, RetractField}` (/Users/ember/dev/breadstuffs/dregg-doc/src/patch.rs:29).
- `Status::{Alive, Dead}` with "dead wins" as the join (/Users/ember/dev/breadstuffs/dregg-doc/src/atom.rs:122-141).
- `History { patches: Vec<Patch> }` (/Users/ember/dev/breadstuffs/dregg-doc/src/history.rs:19-24).

**Merge.**
- `merge` is `union_in_place`, described as "total, commutative, associative, idempotent" (/Users/ember/dev/breadstuffs/dregg-doc/src/merge.rs:13-34; /Users/ember/dev/breadstuffs/dregg-doc/src/graph.rs:343-350).
- The three-way field merge uses the common base to tell a *superseded* assignment from a *concurrent* one: "if BOTH sides changed the field away from the base, the assignments union — a genuine concurrent divergence stays a first-class clash" (/Users/ember/dev/breadstuffs/dregg-doc/src/graph.rs:372-399).

**Patch theory proper** (/Users/ember/dev/breadstuffs/dregg-doc/src/depend.rs:1-35):
- "a patch *depends on* the patches that introduced the atoms it references";
- `commute` is true iff neither patch transitively depends on the other (:260-282);
- `unrecord` pulls a patch out together with its dependents (:291);
- `cherry_pick` brings a patch plus the dependencies it is missing (:315);
- a superseding `SetField` "depends on every earlier patch that assigned the same field name" (:170-191).

**Two regimes.** Merge conflicts fall into two kinds (/Users/ember/dev/breadstuffs/dregg-doc/src/regime.rs:1-45):
- `Regime::Prose`: an antichain of concurrent inserts, which is legible and which either author can resolve alone;
- `Regime::Field`: a clash on a single-valued field, where `needs_consensus()` is true.

The design text says the same at /Users/ember/dev/breadstuffs/docs/deos/DOCUMENT-LANGUAGE.md:254-284.

**Lean theorems (breadstuffs), quoted.**
- `DocMerge`: `merge_comm (a b : DocGraph) : merge a b = merge b a` (/Users/ember/dev/breadstuffs/metatheory/Dregg2/Deos/DocMerge.lean:211). Also `merge_assoc`, `merge_idem` and `merge_total`.
- `merge_is_lub (a b : DocGraph) : a ⊑ merge a b ∧ b ⊑ merge a b ∧ (∀ u, a ⊑ u → b ⊑ u → merge a b ⊑ u)` (:355).
- `ConflictAt g p x y := x ≠ y ∧ g.atoms x = some .alive ∧ g.atoms y = some .alive ∧ Reaches g p x ∧ Reaches g p y ∧ ¬ Reaches g x y ∧ ¬ Reaches g y x` (:394-397).
- `prose_iconfluent` (:510) states only that atom *presence* survives a merge. `field_not_iconfluent` (:529) is a constructed pair whose merge holds `{0, 1}` at a single field name.
- `merge_isPushout (c a b) (hca : c ⊑ a) (hcb : c ⊑ b) : IsPushout c a b (merge a b)` (:659). This is a pushout in the *thin* inclusion category.
- `DocPatch`:
  - `addAtom_addAtom_comm : addAtom i (addAtom j g) = addAtom j (addAtom i g)` (/Users/ember/dev/breadstuffs/metatheory/Dregg2/Deos/DocPatch.lean:120);
  - `addAtom_tombstone_comm {i j} (h : i ≠ j) …` (:178);
  - `addEdge_is_merge : addEdge e g = merge g (singletonEdge e)` (:271), which says "apply is merge with a singleton".
- `PatchCategory`:
  - a genuine `instance categoryP : Category DocGraph` (/Users/ember/dev/breadstuffs/metatheory/Dregg2/Deos/PatchCategory.lean:147);
  - `hom_not_thin` (:182);
  - but `IsoP` (:199) only asks that patch effects round-trip, and `IsPushoutUpToIso` (:283) is a custom predicate;
  - `no_conflictFree_pushout` (:333) rests on the thin `IsPushout`.
- `BranchStitch`: `stitch_is_pushout (m b) : Stitch m b (merge m b)` restates `merge_is_lub` (/Users/ember/dev/breadstuffs/metatheory/Dregg2/Deos/BranchStitch.lean:232-245). `stitch_drop_is_below` (:303) says that an explicit drop lies below the merge.

**Proved versus asserted.** The authoritative ledger is /Users/ember/dev/HYPERDREGGMEDIA_MINIDREGG_SUBSUMPTION_AUDIT_2026-08-09.md:379-441.

What is proved:
- the join laws, least-upper-bound, the conflict witness and the thin-category pushout, all over a model where `AtomId = Nat` and atoms carry status only, with no content and no provenance (:385-395);
- the commutation results only for the simplified operations (:397-403).

What is not proved:
- `SetField` with superseding, inverse operations, dependencies, unrecord and cherry-pick have **no Lean theorem**. They are Rust tests only, in `depend.rs` around :409-473.

Defects the audit found:
- `IsoP` and `IsPushoutUpToIso` are not `CategoryTheory` isomorphisms or colimits (:409-419);
- `DocPatch.tombstone` and `PatchCategory.Op.del` give delete two different meanings (:405; compare /Users/ember/dev/breadstuffs/metatheory/Dregg2/Deos/PatchCategory.lean:101-103);
- `BranchStitch.restrict` leaves dangling edges, and `contained_branch_one_door` is vacuous (:437);
- `DocSubstrateSound` relies on a crypto-binding hypothesis that is false for the deployed sponge (:433).

Other weaknesses:
- `History` is "a plain `Vec<Patch>`" with no parent ids (:191-198);
- `replay_to` silently replays the whole history when the cursor is absent (/Users/ember/dev/breadstuffs/dregg-doc/src/history.rs:70-82);
- atom and patch ids come from `DefaultHasher`, which is "deliberately non-cryptographic" (/Users/ember/dev/breadstuffs/dregg-doc/src/atom.rs:45-56).

**What breadstuffs said it had run.** "dregg-doc 102/120 green" (/Users/ember/dev/breadstuffs/HORIZONLOG.md:12048-12053), and earlier "31 unit tests + 1 doctest green" (:15897-15898). I did not run them.

### 2.2 Minidregg: what replaced it

**The decision record.** /Users/ember/dev/minidregg/docs/decisions/D-0005-hyperdocument-semantic-family.md:5 reads "Replaces: the parallel Breadstuffs document heaps, patch histories, transclusion demos, and UI-owned provenance stores". Its "Patch and merge claim ceiling" (:70-90) says:
- `DocMerge`'s join is worth keeping "where its invariants apply";
- `IsoP` is "state round-trip, not `CategoryTheory.Iso`";
- minidregg will either prove exact residual/commutation laws or define a justified quotient before it states any categorical result;
- "The current merge deliberately takes the conservative option".

D-0005 does not mention Pijul by name, and neither does anything else in minidregg. A grep for `pijul` and `darcs` over the whole repository returns nothing.

**Store patches (not Pijul patches).** "`Patch L := List (Op L)` is the free monoid on operations." An op is `read a observed | write a before after | allocate a v | free a before`, so "every mutation names the exact value it expects to replace" (/Users/ember/dev/minidregg/Theory/Store.lean:1-27, :252). Proved:
- `run_append : run store (left ++ right) = run (run store left) right` (:316);
- `apply_comm (s) (x r : Op L) (ne : x.address ≠ r.address) : x.apply (r.apply s) = r.apply (x.apply s)` (/Users/ember/dev/minidregg/Theory/StoreNormalize.lean:123).

A normal form makes "its write footprint … exactly the set of addresses whose value differs" (/Users/ember/dev/minidregg/Theory/StoreNormalize.lean:1-30).

**Darcs-style commutation, re-derived.** Two plans are `Independent` when neither writes an address the other read (/Users/ember/dev/minidregg/Theory/PlanBinding.lean:414). The theorem is `independent_commute (ind : Independent p q) (hp : p.Admits s) (hq : q.Admits s) : Patch.run (Patch.run s p.patch) q.patch = Patch.run (Patch.run s q.patch) p.patch` (:438). This is the minidregg form of "independent patches commute". It covers guarded state patches, not atom graphs.

**Causal version DAG.** The module "deliberately does not define a document schema, a merge algorithm, a consensus protocol, or a finality predicate" (/Users/ember/dev/minidregg/Theory/CausalVersionDag.lean:1-29).
- `ValidAppend` rejects duplicate or missing parents, replayed entries, requests or effects, and rollback (:223-251).
- Parents "need not still be current tips" (:16-21).
- `frontier` is a `Finset` (:204-212).
- `Replay` with `checkpoint_suffix_equivalence : Replay before (front ++ suffix) after ↔ ∃ checkpoint, Replay before front checkpoint ∧ Replay checkpoint suffix after` (:497).
- `concurrent_sibling_append_inhabited` (:397).

Ancestry distinguishes "a certified lowest base, explicitly ambiguous incomparable maximal bases, or absence of any common base" and "does not claim that an arbitrary DAG has a unique LCA" (/Users/ember/dev/minidregg/Theory/CausalVersionAncestry.lean:1-16).

**Hyperdocument records.**
- `AtomRecord.revision : OperationId` is "the operation that last semantically wrote the atom … a pin goes stale by comparison, with no copy or digest of the bytes stored beside the pin" (/Users/ember/dev/minidregg/Theory/Hyperdocument.lean:308-321).
- `ElementRecord.revision` plays the same role for child positions (:363-376).
- `tombstonedAt` appears on every record.
- `MergeRegime := exclusive | join | multiValue | additiveCounter | orderedSequence` (:414-420).
- `ConflictAlternative {valueType, value, author, operation}` (:466-472).
- `ConflictRecord {field, base, alternatives, regime, recordedAt}`: "Concurrent values remain representable with their provenance. Resolution is a later authority-sensitive operation, not a projection performed here" (:473-481).

**The merge** (/Users/ember/dev/minidregg/Kernel/HyperdocumentMerge.lean:1-20). It is "a first-order declaration over an ordered frontier of two or more already admitted causal parents … A singleton contribution becomes one exact typed field write; two or more contributions become a stored `ConflictRecord`. No branch is silently selected or discarded … Parent order is observable in canonical bytes … not a false commutativity claim." Quoted statements:
- `raw_pair_order_observable (left right : Parent) (distinct : left ≠ right) : [left, right] ≠ [right, left]` (:67);
- `canonicalPair_swap` (:61), the limited symmetry that does hold;
- `FieldPlan.two_sources_not_conflict_free (sourcesExact : plan.sources = first :: second :: rest) : ¬ ConflictFree (plan.ops config operation)` (:691);
- `concurrent_sibling_conflict_positive` (:723);
- `LowestCommonBase.selected_unique` (:341);
- `AmbiguousCommonBases.excludes_lowest` (:383).

There is a built three-node witness that materializes a conflict record: `conflict_is_materialized` (/Users/ember/dev/minidregg/Kernel/HyperdocumentTwoParentWitness.lean:661).

**Keyset and lattice layer** (written by the distributed-semantics co-tenant, /Users/ember/dev/minidregg/GOAL.md:23).
- `LaceMerge.merge B Δ := B ++ newEvents B Δ` (skip-if-present, /Users/ember/dev/minidregg/Theory/LaceMerge.lean:85-89).
- `merge_converges (binding : scheme.BindingPremise) : SameView (merge B C) (merge C B)` (:206).
- `crossCanonical_is_the_gap` (:322) and `merge_drops_at_collision` (:329), the second being "at the colliding address the merge discards a DIFFERENT event".
- `IConfluent I := ∀ x y, I x → I y → I (x ⊔ y)` (/Users/ember/dev/minidregg/Theory/Confluence.lean:75).
- `merge_is_coproduct` (:120) and `subtype_lub_does_not_imply_iconfluent` (:212).
- `overdraft_pair_has_no_colimit` (/Users/ember/dev/minidregg/Theory/ViewMerge.lean:240).
- `tier1_requires_iconfluent` (/Users/ember/dev/minidregg/Theory/Finality.lean:301).

The design summary is at /Users/ember/dev/minidregg/docs/DISTRIBUTED-DESIGN.md:21-29, which says "a document merge that is deliberately anti-commutative (`Kernel/HyperdocumentMerge`, `raw_pair_order_observable`)". At :279-286 it adds that HyperdocumentMerge's "conservative conflict-retaining join is NOT a semilattice and is not made one".

### 2.3 What minidregg kept, dropped and re-derived

| Breadstuffs piece | Minidregg | Where |
|---|---|---|
| atoms with stable identity, tombstones (`Dead`) | kept as records with `tombstonedAt`; "Moving or regrouping an atom changes `run`; it never changes `atom`" | /Users/ember/dev/minidregg/Theory/StableRanges.lean:36-38 |
| marks anchored to atoms (Peritext style) | kept and strengthened: `StablePoint` names a neighbour atom, a bias and an `EndpointDeathPolicy` | /Users/ember/dev/minidregg/Theory/Hyperdocument.lean:387-412 |
| field clash kept with provenance | kept as `ConflictRecord` | Hyperdocument.lean:466-481 |
| two regimes (prose antichain vs field clash) | re-derived as I-confluence plus a coordination dial over `Pred` | /Users/ember/dev/minidregg/Theory/Confluence.lean:75; /Users/ember/dev/minidregg/docs/DISTRIBUTED-DESIGN.md:218-236 |
| LaceMerge join | ported; the collision gap is now derived from `BindingPremise` | /Users/ember/dev/minidregg/Theory/LaceMerge.lean:1-35 |
| patch commutation | re-derived over guarded store patches (`apply_comm`, `independent_commute`), not over atom graphs | PlanBinding.lean:438 |
| order-edge graph and antichain prose conflicts | **dropped**: runs and containers are ordered *lists* (`RunRecord.atoms : List AtomId`, `ElementBody.container (children : List ElementId)`) | Hyperdocument.lean:337-362 |
| total union merge | **dropped**: the merge orders its parents and is not a semilattice | HyperdocumentMerge.lean:51-73 |
| three-way "superseded vs concurrent" field logic | **dropped**: `base` is recorded but never consulted; every source of two or more becomes a conflict | HyperdocumentMerge.lean:165-175 |
| dependencies, `unrecord`, `cherry_pick`, `invert` | **dropped**, no counterpart | grep of minidregg |
| one-click resolution patches | **not built**: no action resolves a `ConflictRecord` | Hyperdocument.lean:473-474; no resolve action in Kernel/ContentResource.lean |
| `MergeRegime` behaviours | **data only**: the enum is encoded (/Users/ember/dev/minidregg/Compiler/HyperdocumentCell.lean:187-199), and nothing gives `join`/`additiveCounter`/`orderedSequence` a semantics | grep |

## 3. How it touches the rest of minidregg

**Hyperdocument cells.**
- The content cell is mutable: "Every namespace of this mutable cell is RAM; the separate event log uses `appendOnly`" (/Users/ember/dev/minidregg/Theory/Hyperdocument.lean:901-908).
- Version events live in a separate append-only cell (/Users/ember/dev/minidregg/Kernel/HyperdocumentEventLog.lean:1-12).
- A merge `Body` is `parents`, `fields` and `overlays` (marks and annotations) only (/Users/ember/dev/minidregg/Kernel/HyperdocumentMerge.lean:118-121). **Concurrent atom, run or element edits therefore cannot be merged at all.** Only fields and overlays can.
- The merge has **no coverage obligation**. `ParentContentEvidence` checks that each declared source is real (:464-489). Nothing requires every field on which the parents differ to be declared. A declaration that lists only one of two diverging sources produces a plain write (:171-172). So "No branch is silently selected" (:8-9) holds only for what the author chose to declare.

**What is actually deployed** (`Kernel/ContentResource`, command grammar v8).
- Edits are checked against "the revision of the container its author read" (/Users/ember/dev/minidregg/Kernel/ContentResource.lean:20-28).
- Stale edits are refused (`staleAtom`, `staleElement`, `staleMark`, :444-476).
- A snapshot transclusion is pinned: `transclusion_pinned` shows the pinned bytes "or says `moved` — never other bytes" (:2565-2578).
- Readers see transcluded bytes only through their own read of the source, "current or `at` the opening's height" (:52-55).
- The two-friend journey J21 is written as "amy's second push is refused and the refusal names line 3" (/Users/ember/dev/minidregg/native/resource-client/journey.d/jdocuverse.sh:1-40).

**SPK grains.**
- An application is a four-field record `{generation, phase, packageVersion, snapshotVersion}`, all `Int` counters (/Users/ember/dev/minidregg/Kernel/ApplicationGrain.lean:1-12, :36-41).
- `accepted_snapshot_advance_requires_content` (/Users/ember/dev/minidregg/Kernel/ApplicationGrainLaws.lean:133) and `only_checkpoint_changes_snapshot` (:169).
- Snapshots are linear and opaque. There is no patch or merge of volumes.
- On export and import, "the restored grain is always a new application resource" (/Users/ember/dev/minidregg/native/spk-host/src/grain_export.rs:1-12).
- `GrainForkSettlement` forks branches from one `CanonicalHead`. Its `MergeConflict` is an address that two incidences both write under disjoint composition, and a commit proves there is none (/Users/ember/dev/minidregg/Assurance/GrainForkSettlement.lean:1-19, :247-271). Grain settlement therefore *refuses* overlap where document merge *records* it. The hyperdreggmedia audit warns: "Do **not** use its generic 'no field/resource collision' predicate as the document content model" (/Users/ember/dev/HYPERDREGGMEDIA_MINIDREGG_SUBSUMPTION_AUDIT_2026-08-09.md:499-511).
- One deployed-schema witness carries a hyperdocument link turn through grain settlement (/Users/ember/dev/minidregg/Assurance/GrainHyperdocumentSettlementWitness.lean:1-19).

**Views.**
- `CanonicalReactiveView`: a view is dirty exactly when its declared dependencies intersect the verified footprint (/Users/ember/dev/minidregg/Theory/CanonicalReactiveView.lean:1-22).
- `ViewMerge` (views form a join-semilattice, and merge is the colimit) is imported only by `Theory.lean`. `LaceMerge` is imported only by `Theory.lean` (import grep). So neither is consumed by any kernel or view code.

**Agreement and finality.**
- D-0005 says "Consensus/finality may order semantic receipts but does not define document merge semantics" (/Users/ember/dev/minidregg/docs/decisions/D-0005-hyperdocument-semantic-family.md:99).
- Commit tiers join over written cells (`commitTier`, `commitTier_eq_causal_iff`, /Users/ember/dev/minidregg/Kernel/HyperedgeTier.lean:58, :74).
- In practice, "physical global journal order currently serializes even logically commuting writes" (/Users/ember/dev/minidregg/docs/research/2026-10-02-private-objects/agreement.md:11).

**Read roots and sealed imports.**
- Read roots: a plan binds the values at the addresses it read, no longer the whole cell root (/Users/ember/dev/minidregg/Theory/PlanBinding.lean:1-12). That is the binding that makes commutation possible.
- "Sealed imports" belong to Objective Bend source packages, not to document revisions (/Users/ember/dev/minidregg/docs/BEND-WORLD-LANGUAGE-20261003.txt:45).

**Durable history.**
- The log is linear: `durable_log(height, record, tag)`, hash-chained, with checkpoints. Opening the store replays the suffix after a checkpoint (/Users/ember/dev/minidregg/docs/DURABLE-STORE.md:15, :23-34, :52-64).
- The causal DAG lives only in Lean (S/A). On disk, history is one chain.

## 4. Evidence class per component (minidregg's vocabulary, /Users/ember/dev/minidregg/README.md:63-65)

| Component | Class | Basis |
|---|---|---|
| breadstuffs `dregg-doc` | executed in breadstuffs (their claim) | /Users/ember/dev/breadstuffs/HORIZONLOG.md:12048-12053 |
| breadstuffs `Deos/Doc*.lean` | compiled (their claim; the headers say `lake build` is green) | /Users/ember/dev/breadstuffs/metatheory/Dregg2/Deos/DocPatch.lean:1-36 |
| `Theory/{Store,StoreNormalize,CausalVersionDag,CausalVersionAncestry,StableRanges,Confluence,ViewMerge,LaceMerge,Finality,PlanBinding}` | compiled: in the default `Minidregg` target through `Theory.lean` | /Users/ember/dev/minidregg/lakefile.toml:2; /Users/ember/dev/minidregg/Minidregg.lean:10 |
| `Kernel/HyperdocumentMerge*` and `TwoParentWitness` | compiled; both poles built on closed data; "Consumed only inside `Kernel/`" | /Users/ember/dev/minidregg/docs/KERNEL-TWIN-AUDIT.md:57-58, :614-619, :704 |
| plan footprint binding | compiled. The `BD` journey ("disjoint plans commute, overlap refused") is authored but recorded SKIPPED | /Users/ember/dev/minidregg/native/resource-client/journey.d/bind.sh:1-14; /Users/ember/dev/minidregg/docs/evidence/2026-10-01-p-story/journey-result.json:241 |
| deployed documents (new/show/append/edit/link/backlinks) | deployed | /Users/ember/dev/minidregg/README.md:69 |
| stale-revision refusal | executed and integrated (J12 row 77 refused `staleAtom`) | /Users/ember/dev/minidregg/docs/evidence/2026-09-30-shell-docs/j12.tsv:78 |
| transclusion in the deployed kernel | compiled (`transclusion_pinned`). J12C **FAILED** on 2026-09-30 because the cell "has no transclusion action"; the action has landed since (ContentResource.lean:267). The JDV/J12W drivers are authored with no recorded run | /Users/ember/dev/minidregg/docs/evidence/2026-09-30-shell-docs/journey-result.json:162-166 |
| SPK grains (install/start/export) | integrated on development worlds | /Users/ember/dev/minidregg/README.md:76 |
| `GrainForkSettlement` | compiled, with a built witness | /Users/ember/dev/minidregg/Assurance/GrainHyperdocumentSettlementWitness.lean:1-19 |
| agreement mesh | compiled safety theorem; executed | /Users/ember/dev/minidregg/README.md:80 |
| `Kernel/ResidentActivityRevision` | authored only, inside opt-in `ResearchWip` ("This target may fail") | /Users/ember/dev/minidregg/ResearchWip.lean:1-3, :110 |

## 5. What it means for VerEKOS

**EKOS is already a patch store.**
- A version is `let ops = diff(&old_facts, &new_facts)`, a list of `FactOp::{Assert, Retract}` facts (/Users/ember/dev/EKOS/ekos/crates/ledger/src/fact_ledger.rs:736; /Users/ember/dev/EKOS/ekos/crates/ledger/src/fact.rs:36-52, :377).
- `TxId` is "the ordering authority … Wall-clock time is metadata" (fact.rs:36-40).
- Writing identical content returns `Ok(false); // logically identical — no new version` (fact_ledger.rs:724).

**EKOS also has branches and a merge, and the design never mentions them.**
- `ekos branch create/merge` (/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/branch.rs:81-90).
- `merge_stores` uses skip-if-present. A divergent version is "recorded in the report, **not** auto-resolved", and the report is only printed (/Users/ember/dev/EKOS/ekos/crates/ledger/src/lib.rs:1606-1621, :1900; /Users/ember/dev/EKOS/docs/rfcs/0011-optimizer.md:203-214).
- This is `LaceMerge.merge` plus a divergence detector, with the `merge_drops_at_collision` shape (main wins, branch dropped).
- Merged objects are re-appended at merge time (`Utc::now()`, fact_ledger.rs:738). So the branch's own history is flattened.

**Construct by construct.**

| EKOS construct | Is the patch-theoretic model better than the plain causal history? |
|---|---|
| Append-only versions, content-signature idempotence (P1) | **Better.** State a version as a guarded patch. Then "identical content is a no-op" becomes "the normalized patch has an empty write footprint" (/Users/ember/dev/minidregg/Theory/StoreNormalize.lean:1-30). Minidregg does *not* give this by construction: a duplicate event is **refused** (`no_entry_replay`, /Users/ember/dev/minidregg/Theory/CausalVersionDag.lean:329). An identical re-edit is a new operation with a new event, so it must be a law. |
| `object_at`, `diff` (P2) | **Better on a linear `TxId`:** a fold of patches, with `Replay` and `checkpoint_suffix_equivalence` (CausalVersionDag.lean:497). `diff` over `(from, to]` is the union of the write footprints, derived from syntax (/Users/ember/dev/minidregg/Theory/Store.lean:258-276). **Worse on a DAG:** with sibling tips, "latest version at or before t" is a frontier, not one version (CausalVersionDag.lean:204-212). Keep P2 over the linearized log and model RFC 0011 branches separately. |
| Evidence pins and staleness (P3, P12, session anchors) | **Better.** Use `revision` pins with stale-by-comparison and `transclusion_pinned` ("same bytes or `moved`", ContentResource.lean:2565-2578). Stable atom identity (Pijul) keeps anchors valid across unrelated edits, which `SourceLocation{path,line}` (/Users/ember/dev/EKOS/ekos/crates/kir/src/lib.rs:44-47) cannot do. But it needs an importer that reuses atom ids for unchanged spans. That is the `Doc::edit` LCS idea (/Users/ember/dev/breadstuffs/dregg-doc/src/lib.rs:33-38), and minidregg's only diff-to-actions code is the Rust `doc push` client (journey.d/j12w.sh:1-20). |
| Identity merges (P6) | **Worse if modelled as patches that re-key.** Atoms never change identity (StableRanges.lean:36-38). Model an exact merge as an overlay link (a `SameAs`-relation `LinkRecord`) plus canonicalization at view time. Then it is reversible, which EKOS's exact merges are not; only fuzzy matches are kept reversible today (EKOS CLAUDE.md `identity` row). |
| ConflictingEvidence (P7) | **Better fit as `ConflictRecord`** (Hyperdocument.lean:473-481): read each source as a parent branch and the compile as their merge. Every EKOS attribute is single-valued, so it is in the *Field* regime and every disagreement is a real conflict, while relationship and evidence sets are grow-only. Three gaps either way: (1) EKOS keeps the **last-read** member as the surviving object (`members[members.len() - 1]`, /Users/ember/dev/EKOS/ekos/crates/semantic/src/conflicts.rs:310-323), the shape breadstuffs' LaceMerge note warned of ("output order on the tied blocks is a function of the INPUT order", /Users/ember/dev/breadstuffs/metatheory/Dregg2/Distributed/LaceMerge.lean:336-345). (2) Minidregg's merge has no coverage obligation (§3). EKOS's `compare_members` is actually more complete, so VerEKOS's Conflicts theorem must state coverage. (3) There is no resolution action in minidregg. |
| Read scope, deny wins (P8) | **Worse as is.** `ConflictAlternative.value` sits inline in the cell (Hyperdocument.lean:466-472), so one reader of the conflict sees every source's claim. Under deny-wins, each alternative must be either a transclusion reference resolved by the reader's own read (ContentResource.lean:52-55) or a `sealedObject` fragment. A reader who sees one source sees no conflict at all, so the conflict view is per reader. |
| Human-only review (P10) | **Better.** A resolution is an authored patch under a human-held capability. The dependency rule "a superseding SetField depends on every earlier patch that assigned the same field" (depend.rs:170-191) models "a review survives while the claims' signature is unchanged": a new claim re-opens the clash. Neither system has built it. |
| Compiler determinism (P4) | **Patch merge does not apply.** Compiled facts are a function of sources, so a branch merge should re-run the compile over the merged sources (admission by re-execution), not merge the output patches. Patch theory belongs to the *authored* layers: reviews, resolutions, session notes, semantics confirmations and imported source documents. |

**What the design document got wrong, by section** (/Users/ember/dev/verekos/docs/design/VEREKOS-DESIGN-2026-10-19.md).

- **§1, P1/P2:**
  - It reads EKOS versions as snapshots. They are assert/retract patches over EAV facts (fact.rs:1-30).
  - It omits RFC 0011 branch/merge, which is a second history shape and has its own invariant: a conflict is reported, never overwritten.
- **§2.1, row "content signature idempotence, versions → … `revision : OperationId` on every record, P1/P4 by construction"** (:57). It is wrong in three ways:
  - (a) the hyperdocument content cell is RAM and overwrites under guard (Hyperdocument.lean:901-908). Only the event log and the durable log are append-only;
  - (b) duplicates are refused, not no-ops;
  - (c) idempotence of identical content is not by construction.
- **§2.1, row "`object_at` → causal history + canonical cells; a derived view at a height"** (:58). Heights exist only in the linear durable log (DURABLE-STORE.md:23-27). The causal DAG has frontiers, not heights. The row should say "fold over the linearized log", with DAG branches as a separate statement.
- **§2.1, row "`ConflictingEvidence` → an annotation … carrying both claims' transclusions"** (:63). Minidregg has a purpose-built `conflicts` namespace (Hyperdocument.lean:860). Use it, with its three gaps (no coverage obligation, no resolution action, alternatives stored inline).
- **§2.1, row "`KirEvidence` → snapshot transclusion"** (:56). It is right, and stronger than stated (`transclusion_pinned`). But transclusion was missing from the deployed cell on 2026-09-30 (J12C FAIL) and has no recorded deployed run.
- **§2.1, mismatch 1:** it must add stable atom identity across re-imports, otherwise every re-import of a source file moves every pin.
- **§2.2, `Ledger` kernel:** state it over fact-op patches with "reconstruct = fold" and "diff = footprint". Add a `Branch` kernel: skip-if-present merge, divergence persisted as a conflict rather than printed.
- **§2.2, `Conflicts` kernel:** add coverage, and independence of the survivor from input order (or no survivor at all, as in minidregg).
- **§2.2, `Identity` kernel:** say whether an exact merge is a re-key or an overlay.
- **§3:** fine.
- **§6:** M1 and M4 have no branch/merge panel. EKOS's own tests `merge_branch_*` (/Users/ember/dev/EKOS/ekos/crates/ledger/src/lib.rs:2861-2897) can serve as one.

## 6. Nuggets

- **`PlanBinding.no_toctou` and `independent_commute`** (/Users/ember/dev/minidregg/Theory/PlanBinding.lean:375, :438). This is the exact statement for "two compile passes or reviewers whose footprints don't overlap can land in either order". EKOS could use it for concurrent `commit` steps.
- **`ResidentActivityRevision`.** "A revision is another signed stream append, not a rewrite of historic bytes … A malformed/stale/other-author revision remains historic data but cannot change the current context projection" (/Users/ember/dev/minidregg/Kernel/ResidentActivityRevision.lean:1-5). It has `stale_revision_cannot_revise` (:73) and a fold that counts invalid revisions instead of dropping them (:99-130). This is the closest existing model of EKOS supersession and session-memory lifecycle. It is in opt-in `ResearchWip` only.
- **`transclusion_pinned`** (ContentResource.lean:2565). This is the evidence-pin law VerEKOS needs, already proved.
- **Noninterference precedents for P8:**
  - breadstuffs `FogOfWar.noninterference`: "a hidden cell is STRUCTURALLY ABSENT (not a redacted entry — the viewer cannot even distinguish occupied-vs-empty)" (/Users/ember/dev/breadstuffs/metatheory/Dregg2/Deos/FogOfWar.lean:1-30, :149);
  - minidregg `accountCut_noninterference` (/Users/ember/dev/minidregg/Compiler/CanonicalAccountView.lean:25);
  - `PrivacyPortal.compose_noninterference` (/Users/ember/dev/minidregg/Theory/PrivacyProfile.lean:94). This is the "per-call scope can only remove" composition.
- **`DocMergeComposed.boundary_layout_child_disjoint`** (/Users/ember/dev/breadstuffs/metatheory/Dregg2/Deos/DocMergeComposed.lean:345): merge of a family indexed by cell, where an edit inside one component can never conflict with another. The EKOS reading: partition conflicts per source and per project.
- **`subtype_lub_does_not_imply_iconfluent`** (/Users/ember/dev/minidregg/Theory/Confluence.lean:212). A tooth against claiming "conflicts merge cleanly" just because lawful states have joins.
- **Named failure modes:**
  - the anonymously carried `CrossCanonical` (/Users/ember/dev/breadstuffs/metatheory/Dregg2/Distributed/LaceMerge.lean:24-31). In EKOS terms: equal id sets across ledgers do not mean equal content; `merge_stores` detects this by signature, and that detection is the realizer;
  - a sort with ties makes output depend on input order (:336-345);
  - "Rust tests remain executable evidence, not semantics or refinement theorems" (D-0005:84);
  - the audit's five assurance labels, proved / conditional / executable property / cross-language / design target (/Users/ember/dev/HYPERDREGGMEDIA_MINIDREGG_SUBSUMPTION_AUDIT_2026-08-09.md:443-455). They are a ready scale for VerEKOS's scoreboard.
- **Performance targets** for any history model: "Merge/settlement … proportional to compared frontier/delta, not full history" (/Users/ember/dev/minidregg/docs/HYPERDOCUMENT_PERFORMANCE_PLAN.md:34-36). Breadstuffs' dependency computation was O(n²) with re-hashing (/Users/ember/dev/breadstuffs/dregg-doc/src/depend.rs:119-123).

## 7. What I could not find or verify

- **No Pijul import in minidregg.** Zero `pijul` or `darcs` matches anywhere in the repository. The link exists only as D-0005's replacement and claim cap, and ATLAS's "DocMerge as LUB / pushout products" (/Users/ember/dev/minidregg/ATLAS.md:135-138), which planned a `Deos/` library that was never created (/Users/ember/dev/minidregg/docs/KERNEL-TWIN-AUDIT.md:585-586).
- **Builds and tests.** I did not check whether any cited Lean currently builds, or whether the `dregg-doc` tests pass.
- **`import_binds_stop_receipt`.** It is named in grain_export.rs:10-12 as "K-SPK, `ApplicationGrainExport`", but no Lean declaration with that name exists (grep).
- **JDV and J12W.** I found no recorded run, so `doc show --at H` and live/snapshot transclusion on a real Host are unverified.
- **EKOS identity merges.** I did not trace whether `apply_merges` leaves orphaned last versions of merged-away ids in the ledger. That is an open question for lane A/D.
- **Breadstuffs beyond the files cited.** I did not read `Transclusion.lean`, `AnchoredQuote.lean` or `Rehydration.lean` beyond the audit's summary of them, nor the `dregg-doc` forge modules (`pull_request.rs`, `check.rs`).
