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
| `World/Minidregg.lean` | The carriers filled with minidregg's types. `claimIdDerivation` derives ids the way minidregg derives identifiers. Source-pin freshness is checked against `AtomRecord.revision`. | `claimId_injective` (from an injective encoder and digest, using minidregg's `preimageCodec_encode_injective`), `sourcePinFresh_iff`, `stale_of_moved` |
| `World/Examples.lean` | The theorems run on the table example, so their hypotheses are shown to be satisfiable. A human review confirms. A compiler-written review changes nothing. A core change gives `needsReview`, and restoring the core restores the decision. `diff` over-approximates. A reader denied one file does not see the conflict. | `d₀_injective`; thirteen `decide` examples |

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
- **Laws are not yet in the types.** Three are missing: "pins are nonempty",
  "pins form no cycle", and "`sources` is sorted and duplicate-free". Visibility
  fails closed on an unpinned claim. `reviewSurvives_put` excludes a claim that
  reviews itself by hypothesis.
- **Reviews cannot be retracted.** Status ignores retract receipts, so a change
  of mind is a new review.
- **No traversal.** Staleness of claim pins (exploration 02 §2b, for claims),
  traversal over facts (§2d), and identity (§3 G) are not here yet. Only source
  pins have a freshness check, in `World.Minidregg`.
- **The concrete schema's core digest is a stand-in.** It is the column count.
  No theorem depends on it.
- **The visibility bound is not tied to the pin graph's depth.** That would
  need the acyclicity law. `visible_mono` shows that a bound that is too small
  only hides more.
