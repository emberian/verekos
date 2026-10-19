# world/ — the VerEKOS claim model in Lean

This is the Lean project for the VerEKOS "world layer": the claim and receipt
records (design 2026-10-19 §2, exploration 02 §1.2) and the first theorems about
them. Everything here is proved: no `sorry`, `admit`, `axiom` or `native_decide`.
Each theorem depends only on Lean's three standard axioms (`propext`,
`Classical.choice`, `Quot.sound`), which we checked with `#print axioms`.

All names are **ours** (new to VerEKOS) unless marked as quoted from minidregg.

## Building

```
cd /Users/ember/dev/verekos/world
nice -n 10 lake build
```

- Toolchain `leanprover/lean4:v4.30.0`, the same as minidregg's.
- minidregg is a **git** dependency on the local checkout, pinned to commit
  `dcab86da`. It is not a path dependency. minidregg's own `.lake/build` is
  older than its sources for the modules we import, so a path dependency would
  make Lake rebuild those modules *inside minidregg's tree*. With the pin, Lake
  builds them here under `.lake/packages/minidregg` (about 19 modules, 77 s,
  once).
- Mathlib and its companion packages are **symlinks** under `.lake/packages/`.
  They point to the same warm checkouts minidregg's own symlinks point to.
  Nothing is downloaded and Mathlib is not rebuilt. `lake-manifest.json` is
  written by hand to match minidregg's. If you set this up on a fresh machine,
  recreate those symlinks before the first `lake build`, or Lake will clone.
- A clean build of `World` takes about 8 s once the dependencies are built.

## What each file states

| File | What it says | Proved |
|---|---|---|
| `World/Claim.lean` | The records. **Carriers** are the abstract types, such as source ids, digests and claim ids. **ClaimKey** is (schema, subject, sources): no run, no time, no revision. **ClaimIdDerivation** turns a key into an id; no injectivity is assumed. Also **Pin** (a target plus the revision read, with a per-mille weight), **Window**, **Claim**, **Status**, **PrincipalKind**, **Schema** (`core`, `structural`, `initial`, `isFact`, `mayDecide`, `stated`), **Op**, and **Receipt** (tx, op, author, run, stage). | definitions only |
| `World/Log.lean` | `state L t` replays the receipts numbered `t` or less. `write` appends, but skips a receipt that would change nothing. `diff L a b` lists the ids touched in the window `(a, b]`. | `write_appendOnly`, `idempotentPut`, `latest_write`, `state_append_of_future`, `state_eq_latest`, `mem_diff`, `diffIsFootprint` |
| `World/Status.lean` | Status is computed from the admitted reviews in the log. If one is pinned at the claim's current core, the status is the last such decision. If reviews exist only at other cores, it is `needsReview`. Otherwise it is the schema's initial status. | `compilerCannotDecide`, `decision_has_author`, `reviewSurvives`, `reviewSurvives_put`, `needsReviewOnCoreChange`, `reviewTakesEffect`, `decided_stays_decided` |
| `World/Conflicts.lean` | `detect` takes a `Finset` of claims and returns the (schema, subject, attribute) keys on which two different claims state different values. Includes a concrete table schema with typed columns. | `mem_detect` (exact characterization), `coverage`, `soundness`, `detectList_congr` (order and repeats do not matter), `detectList_perm`, `detect_mono`; four `decide` examples |
| `World/Visible.lean` | Visibility under a reader's scope, computed on an explicit pin-depth bound. A claim is visible when it is allowed and not denied. Denial flows along pins. | `deny_wins_id`, `deny_wins_origin`, `deny_through_premise`, `conflict_hidden_of_alternative_denied`, `unpinned_hidden`, `visible_pins`, `visible_mono` |
| `World/WellFormed.lean` | The three rules. **Pins are nonempty.** **No pin cycles**: a *rank* drops from every claim to each claim it pins, so the pin graph is well founded with finite depth. **Sources are sorted and duplicate-free** (`ClaimKey.Canonical`, and `ClaimKey.normalize` to get there). | `eq_iff_of_canonical` (keys equal iff same schema, subject and source *set*), `normalize_eq_iff`, `latest_wellFormed`, `Ranked.wellFounded`, `visible_stable` (every bound above a claim's rank gives the same visibility), `visibleR_rank_irrelevant`, `visible_iff_sourcePins`, `reviewSurvives_put_acyclic` (the self-review hypothesis replaced by acyclicity) |
| `World/Traverse.lean` | Reachability from a seed over typed edge claims, within a hop bound. It crosses an edge only if the edge and both endpoints are current facts (`Schema.isFact` of their status). | `pending_edge_never_crossed`, `reach_trivial_of_all_pending`, `unreviewed_hypothesis_edge_not_crossed`, `unreviewed_hypothesis_node_blocks`, `reach_mono_confirm` (a confirming review only adds), `reach_mono_hops`, `reach_mono_hops_le` |
| `World/Identity.lean` | Identity as an overlay. A `SameAs` claim pins two claims. Current, confirmed ones link their keys. `Same` is the equivalence closure of those links, and the canonical key is the least key of a class. | `same_equivalence`, `canonical_eq_iff`, `canonical_congr` (depends only on the classes), `links_list_congr`, `fuzzy_no_link`, `fuzzy_not_crossed`, `merge_takes_effect`, `merge_reversible`, `merge_reversible_canonical` |
| `World/Minidregg.lean` | The carriers filled with minidregg's types. `claimIdDerivation` derives ids the way minidregg derives identifiers. Source-pin freshness is checked against `AtomRecord.revision`. | `claimId_injective` (from an injective encoder and digest, using minidregg's `preimageCodec_encode_injective`), `sourcePinFresh_iff`, `stale_of_moved` |
| `World/Examples.lean` | The theorems run on the table example (extended with a foreign key, a fuzzy `SameAs` and an exact `SameAs` schema, and a total order on keys), so their hypotheses are shown to be satisfiable. A human review confirms. A compiler-written review changes nothing. A core change gives `needsReview`, and restoring the core restores the decision. `diff` over-approximates. A reader denied one file does not see the conflict. The example state has a rank. The foreign key is crossed; the fuzzy candidate is not, until a human confirms it. The compiler's exact merge links two tables and is undone by retracting it. | `d₀_injective`, `ranked₀`, `keyCode_injective`, `same_empty`; about thirty examples checked by `decide` or by the theorems |

## Quoted from minidregg (never redefined)

`Digest` (`Theory/TypedAuthorization.lean`); `DocumentId`, `AtomId`,
`OperationId`, `ElementId`, `StableRange`, `AtomRecord`, `AtomRecord.revision`,
`DigestDerivation`, `deriveIdentifier`, `IdPreimage`, `encodePreimage`,
`preimageCodec_encode_injective` (`Theory/Hyperdocument.lean`).

## What is not proved, or not yet modelled

- **Ids are injective only by assumption.** Theorems that need it take
  `Function.Injective d.claimId` as a hypothesis. `claimId_injective` shows what
  would discharge it: an injective key encoder plus an injective digest. A real
  hash is not injective, so that premise is an idealization. minidregg itself
  attaches no injectivity to `DigestDerivation`.
- **The rules are predicates, not types.** `Claim.WellFormed` (nonempty pins
  and canonical sources) and `Ranked` (no pin cycles) are hypotheses that
  theorems use. Nothing makes an ill-formed claim impossible to write.
  `latest_wellFormed` shows a log that puts only well-formed claims keeps a
  well-formed state. No theorem yet shows that a log keeps its pin graph
  ranked, because a put can pin anything.
- **No ranks are computed.** A rank is supplied as a witness. Nothing computes
  one from a state, or proves one exists for every acyclic finite state.
- **Reviews cannot be retracted.** Status ignores retract receipts, so a change
  of mind is a new review.
- **Traversal and identity take their candidates as given.** Traversal works
  over what the state holds. Identity works over a finite candidate set
  (`cands`) that a caller supplies, such as the manifest. The canonical key is
  noncomputable, because it uses classical choice to filter a class; the
  examples prove canonical keys rather than evaluate them.
- **Several hypotheses are specific to one operation.**
  - `reach_mono_confirm` needs the review put under a fresh id, pinned at the
    current core, with a decision that is a fact. Without each one the theorem
    is false; the docstring gives the counterexample.
  - `merge_reversible` needs fresh distinct ids for the merge and its review,
    and a review that no candidate pins.
- **Claim-pin staleness is not checked.** It is only implicit in `status`.
- **The example schemas' core digests are stand-ins.** They are the column
  count, or `0`.
