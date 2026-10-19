# W1: the world project, built

Lane W1, 2026-10-19. Owner of `/Users/ember/dev/verekos/world/` only. Every
file builds, and every theorem is proved: no `sorry`, `admit`, `axiom`,
`native_decide` or `opaque`. `#print axioms` on all 31 load-bearing theorems
shows only `propext`, `Classical.choice` and `Quot.sound`. Build logs are in
`/Users/ember/dev/verekos/var/w1/`.

## What was built

| File | Contents |
|---|---|
| `world/lakefile.toml`, `lean-toolchain`, `lake-manifest.json` | Lean v4.30.0. minidregg is a git requirement on the local checkout, pinned at `dcab86da8f6153ed2b522fc61c5064608694fd83`. |
| `World/Claim.lean` | The records, over an abstract `Carriers` structure. No imports. |
| `World/Log.lean` | State, write and diff, with four theorems and a helper. |
| `World/Status.lean` | The `ReviewSchema`, `status` as a function of admitted reviews, and the three asked-for theorems plus four more. |
| `World/Conflicts.lean` | `detect` over a `Finset`, with exact characterization, coverage, soundness and order independence. A concrete typed-column table schema with four `decide` examples. |
| `World/Visible.lean` | Visibility on an explicit depth bound. Deny-wins theorems, conflict hiding, and depth monotonicity. |
| `World/Minidregg.lean` | The carriers instantiated with minidregg types: `claimId` injectivity derived from minidregg's own codec theorem, and source-pin freshness against `AtomRecord.revision`. |
| `World/Examples.lean` | Concrete runs that show each theorem's hypotheses can be met (13 `decide` examples). |
| `world/README.md` | Plain-words guide. |

Commits (all unsigned, in `/Users/ember/dev/verekos`), plus the one adding this memo:

- `e58ae04` world: Lean project with the claim/receipt model and the log theorems
- `8d4f357` world: first draft of the status theorems (not yet built)
- `21c1cb2` world: status theorems build
- `c3b1624` world: first draft of conflict detection (not yet built)
- `86b51c5` world: conflict detection builds
- `31d4ac6` world: first draft of visibility (not yet built)
- `1dfe79b` world: visibility builds
- `4e8d59a` world: first draft of the minidregg instantiation (not yet built)
- `69fa4e5` world: minidregg instantiation builds; draft of concrete examples
- `c342823` world: concrete examples build; every theorem uses standard axioms only
- `a6dcb86` world: README in plain words

## How the build was set up, and what it cost

**The brief's plan did not work as written. minidregg's build is not warm for
what we import.** `Theory.Hyperdocument` and 10 of the 17 modules it imports
from minidregg changed in commits after the 2026-09-26 oleans. Examples:
`TypedAuthorization.lean` in 08986094, `GuardedAdvice.lean` in 96618e70, and
`Hyperdocument.lean` itself in 3fe858ac. So with `path = "/Users/ember/dev/minidregg"`,
Lake would rebuild those modules *into minidregg's `.lake/build`*, which is
forbidden. Pointing `packagesDir` at minidregg's packages does not avoid this.
It only changes where the *other* packages live, and it would let Lake write
(update, checkout) inside minidregg's packages dir. I did not try it.

What worked:
1. I cloned minidregg myself (`git clone --no-checkout` from the local path,
   then checked out `dcab86da`) into `world/.lake/packages/minidregg`. The clone
   only reads the source repository.
2. I symlinked each Mathlib-family package (`mathlib`, `batteries`, `aesop`,
   `Qq`, `plausible`, `proofwidgets`, `importGraph`, `LeanSearchClient`, `Cli`)
   under `world/.lake/packages/` to the same target minidregg's own symlinks
   use. All nine are clean at the manifest revisions.
3. I wrote `lake-manifest.json` by hand. It has a minidregg git entry plus
   minidregg's own entries, marked inherited, so Lake had nothing to resolve.
4. `lake build --no-build` was the dry run before anything was compiled. It
   showed 585/586 Mathlib targets up to date and the 19 minidregg `Theory`
   modules to build.

Results:
- **Nothing was downloaded, and Mathlib was not rebuilt.** One oddity: the
  `LEAN_PATH` Lake computed uses
  `/Users/ember/dev/breadstuffs-codex/metatheory/.lake/packages/mathlib/...` for
  Mathlib. That is resolved through the `importGraph` symlink, which points into
  `breadstuffs-codex`. It was up to date, so nothing was built there.
- **minidregg's closure:** `nice -n 10 lake build Theory.Hyperdocument` took
  **77 s** for 18 modules, run in the background with a PID file (log:
  `var/w1/build-hyperdoc.log`).
- **World itself:** a clean `nice -n 10 lake build` takes **8 s** (log:
  `var/w1/build-clean-world.log`). The slowest file is `World.Minidregg` at 3 s.
- minidregg's working tree was checked before and after: no modified tracked
  files, and `.lake/build/lib/lean/Theory/Hyperdocument.olean` is still dated
  Sep 26. I wrote nothing there.

Note: the minidregg pin is HEAD as of today. Its commit 96618e70 says
"AUTHORED, NOT COMPILED" and touches `GuardedAdvice.lean`, which we import.
It compiled here.

## Theorem statements, in plain words

**Log.**
- `write_appendOnly`: `write` only ever appends.
- `idempotentPut`: a put of exactly the claim already current leaves the log
  unchanged. "Exactly" means the claims' decidable equality: same key,
  payload, pins and window.
- `latest_write`: skipping such a put loses nothing, because the latest state
  after `write` is the latest state with the receipt applied.
- `state_append_of_future`: receipts numbered after `t` do not change the state
  at `t`.
- `diffIsFootprint`: an id not listed by `diff a b` has the same value at `a`
  and at `b`. The example file shows the converse fails: a re-put of the same
  value is listed although nothing changed. So `diff` is a footprint, not an
  exact change set. The exploration's sketch defined `DiffIsFootprint` as the
  definition of `diff` itself, which would have been a tautology. This is the
  real property.

**Status** (the docstrings give each statement first, in plain words).
- `compilerCannotDecide`: **changed from the sketch, and the docstring says
  why.** The sketch said that for every claim, a compiler-authored review never
  changes status. That is false in EKOS's own model, because an exact identity
  merge is a `SameAs` that the compiler confirms. The stated form: if a claim's
  schema admits the compiler for no decision, then no list of compiler receipts
  (puts, retracts, even review claims) changes that claim's status.
- `decision_has_author`: if a claim's status is neither its initial status nor
  `needsReview`, the log holds a put of a review of it, pinned at its current
  core, with that decision, by an admitted principal kind.
- `reviewSurvives`: if `c'` has the same id and core as `c`, and the later
  receipts hold no admitted review of `c'`, then the status of `c'` afterwards
  is `c`'s status before. It needs injective ids. `reviewSurvives_put` is the
  sketch's one-put form, with one extra hypothesis: the new claim is not a
  review of itself. Pin acyclicity would rule that out, and it is not yet a law.
- `needsReviewOnCoreChange`: suppose an admitted review exists at the old
  core, the claim now has a core at which no admitted review exists, and the id
  is unchanged. Then the status is `needsReview`.
- `reviewTakesEffect`: an admitted review at the current core sets the status
  to its decision. This is the non-vacuity check.
- `decided_stays_decided`: once an admitted review exists at a core, the status
  at that core is always some admitted review's decision. It never falls back
  to the initial status or `needsReview`. This is the per-core monotonicity of
  exploration 02 §3 row K.

**Conflicts.** `mem_detect` is the exact characterization: a key is detected
iff two *different* claims in the set, with the same schema and subject, state
different values for that attribute. `coverage` and `soundness` are its two
directions. `detectList_congr` says lists with the same members give the same
result, whatever the order or repetitions; `detectList_perm` is the
permutation case. `detect_mono` says adding claims never removes a conflict.
Order independence is real but cheap, because the input is a `Finset`.
Exploration 02 already said so; the content is that no claim is ever chosen
over another.

**Visibility.** `deny_wins_id` and `deny_wins_origin` say a denied id, or a
denied origin on any source pin, hides the claim even when its id is
explicitly allowed. `deny_through_premise` says denial flows along claim pins.
`conflict_hidden_of_alternative_denied` says a claim that pins an alternative
whose source origin is denied is hidden. `unpinned_hidden` says nothing is
unattributed. `visible_pins` says a visible claim that is not id-allowed has a
pin, and every pin is visible in its own way. `visible_mono` says a bound that
is too small only ever hides more.

**One design change to note.** In exploration 02 §2e an explicitly allowed id
bypassed the pin check *including denials*, so "deny wins" would have been
false there. Here denial is computed separately and always wins. An id allow
bypasses only the allow side.

**minidregg.** `claimId_injective`: an injective key encoder plus an injective
`DigestDerivation.digestBytes` give injective claim ids, through minidregg's
`preimageCodec_encode_injective`. The digest premise is an idealization (no
real hash is injective), and minidregg deliberately attaches none.
`stale_of_moved`: if an atom a pin read now has a different
`AtomRecord.revision`, or is gone, the pin is not fresh.

## Vacuity check (read adversarially)

- Every hypothesis of the status and visibility theorems is met by a concrete
  `decide` example in `World/Examples.lean`. In those examples the injectivity
  premise is proved (`d₀_injective`), not assumed.
- `compilerCannotDecide`'s schema hypothesis holds for the example's
  `tableSchema` (human-only). The theorem says something because a compiler
  review *would* decide for a schema that admits the compiler. The example
  shows the human review deciding.
- `needsReviewOnCoreChange`'s two hypotheses are jointly satisfiable only when
  the core changed. The example `cA'` (drops a column) meets them.
- The order-independence theorems are the weakest content here, as noted
  above.

## What I could not do

- **Laws that are not in the types:** nonempty pins, acyclic pins, and sorted
  deduplicated `sources`. Status and visibility handle their absence by
  hypothesis or by failing closed.
- **Claim-pin staleness (§2b for claims), traversal over facts (§2d), and
  identity/`SameAs` (§3 G)** were not attempted.
- **The depth bound is not related to the pin graph's real depth**, because that
  needs acyclicity.
- **The example's core digest is the column count**, a stand-in. No theorem
  depends on it.
- **Review retraction is not modelled.** Status ignores retracts, by choice.

## Exact follow-ups

1. Add `Claim.WellFormed`: nonempty pins and sorted deduplicated `sources`.
   Add an acyclicity law on a state. Then prove `visible` at
   depth = (longest pin chain + 1) equals visibility at every larger depth, and
   remove the self-review hypothesis from `reviewSurvives_put`.
2. Claim-pin staleness: `stale σ (⟨.claim i, .core dg, _⟩) := σ i ≠ some c ∨ c.core ≠ dg`.
   Prove it agrees with `status = needsReview` for review pins.
3. `World/Identity.lean`: an exact merge is a compiler-confirmed `SameAs`, and
   structural schemas never merge.
4. Conflict claims as claims: build the `Conflict` schema's claim from
   `conflictPins` and prove its pins are exactly the disagreeing claims at their
   cores (the definition exists; the theorem does not).
5. Tie `World.Log.state` to minidregg's `run_append` and
   `checkpoint_suffix_equivalence`, as lane F planned.
6. Decide whether minidregg should be re-pinned when its `Theory/` moves. The
   pin is a deliberate commit choice, and re-pinning costs about 77 s of
   rebuild here.

## Every theorem statement, quoted from the source


### `World/Log.lean`

```lean
theorem apply_of_ne (s : View C P) (r : Receipt C P) (i : C.ClaimId)
    (h : r.op.id d ≠ i) : apply d s r i = s i

theorem apply_of_eq (s s' : View C P) (r : Receipt C P) (i : C.ClaimId)
    (h : r.op.id d = i) : apply d s r i = apply d s' r i

theorem foldl_apply_at (i : C.ClaimId) :
    ∀ (L : List (Receipt C P)) (s s' : View C P), s i = s' i →
    (L.foldl (apply d) s) i =
    ((L.filter (fun r => decide (r.op.id d = i))).foldl (apply d) s') i

theorem write_appendOnly [∀ s, DecidableEq (P s)] (r : Receipt C P) :
    AppendOnly (fun L => write d L r)

theorem idempotentPut [∀ s, DecidableEq (P s)] (L : List (Receipt C P))
    (r : Receipt C P) (c : Claim C P) (hop : r.op = .put c)
    (hcur : latest d L (c.id d) = some c) : write d L r = L

theorem latest_write [∀ s, DecidableEq (P s)] (L : List (Receipt C P))
    (r : Receipt C P) : latest d (write d L r) = apply d (latest d L) r

theorem state_append_of_future (L₁ L₂ : List (Receipt C P)) (t : Nat)
    (h : ∀ r ∈ L₂, t < r.tx) : state d (L₁ ++ L₂) t = state d L₁ t

theorem state_eq_latest (L : List (Receipt C P)) (t : Nat)
    (h : ∀ r ∈ L, r.tx ≤ t) : state d L t = latest d L

theorem mem_diff (L : List (Receipt C P)) (a b : Nat) (i : C.ClaimId) :
    i ∈ diff d L a b ↔ ∃ r ∈ L, a < r.tx ∧ r.tx ≤ b ∧ r.op.id d = i

theorem diffIsFootprint (L : List (Receipt C P)) (a b : Nat) (hab : a ≤ b)
    (i : C.ClaimId) (hi : i ∉ diff d L a b) : state d L a i = state d L b i

```

### `World/Status.lean`

```lean
theorem statusAt_append_of_no_review (L L₂ : List (Receipt C P)) (k : ClaimKey C)
    (dg : C.Digest) (h : ∀ r ∈ L₂, reviewOf R reg d k r = none) :
    statusAt R reg d (L ++ L₂) k dg = statusAt R reg d L k dg

theorem reviewOf_eq_some (k : ClaimKey C) (r : Receipt C P) (dg : C.Digest) (s : Status) :
    reviewOf R reg d k r = some (dg, s) ↔
    ∃ c', r.op = .put c' ∧ asReview R c' = some (d.claimId k, dg, s) ∧
    (reg k.schema).mayDecide r.author.1 s = true

theorem compilerCannotDecide (L L₂ : List (Receipt C P)) (c : Claim C P)
    (hschema : ∀ s, (reg c.key.schema).mayDecide .compiler s = false)
    (hcomp : ∀ r ∈ L₂, r.author.1 = .compiler) :
    status R reg d (L ++ L₂) c = status R reg d L c

theorem decision_has_author (L : List (Receipt C P)) (c : Claim C P) (s : Status)
    (hs : status R reg d L c = s) (hinit : s ≠ (reg c.key.schema).initial)
    (hnr : s ≠ .needsReview) :
    ∃ r ∈ L, ∃ c', r.op = .put c' ∧ asReview R c' = some (c.id d, c.core reg, s) ∧
    (reg c.key.schema).mayDecide r.author.1 s = true

theorem reviewSurvives (hinj : Function.Injective d.claimId)
    (L L₂ : List (Receipt C P)) (c c' : Claim C P)
    (hid : c.id d = c'.id d) (hcore : c.core reg = c'.core reg)
    (hrest : ∀ r ∈ L₂, reviewOf R reg d c'.key r = none) :
    status R reg d (L ++ L₂) c' = status R reg d L c

theorem reviewSurvives_put (hinj : Function.Injective d.claimId)
    (L : List (Receipt C P)) (c c' : Claim C P) (r : Receipt C P)
    (hop : r.op = .put c') (hnotrev : asReview R c' = none)
    (hid : c.id d = c'.id d) (hcore : c.core reg = c'.core reg) :
    status R reg d (L ++ [r]) c' = status R reg d L c

theorem needsReviewOnCoreChange (hinj : Function.Injective d.claimId)
    (L : List (Receipt C P)) (c c' : Claim C P) (hid : c.id d = c'.id d)
    (hold : ∃ r ∈ L, ∃ s, reviewOf R reg d c.key r = some (c.core reg, s))
    (hnone : ∀ r ∈ L, ∀ s, reviewOf R reg d c'.key r ≠ some (c'.core reg, s)) :
    status R reg d L c' = .needsReview

theorem reviewTakesEffect (L : List (Receipt C P)) (c : Claim C P) (r : Receipt C P)
    (s : Status) (hrev : reviewOf R reg d c.key r = some (c.core reg, s)) :
    status R reg d (L ++ [r]) c = s

theorem decided_stays_decided (L L₂ : List (Receipt C P)) (k : ClaimKey C)
    (dg : C.Digest) (s : Status) (r : Receipt C P) (hr : r ∈ L)
    (hrev : reviewOf R reg d k r = some (dg, s)) :
    ∃ s', statusAt R reg d (L ++ L₂) k dg = s' ∧
    ∃ r' ∈ L ++ L₂, reviewOf R reg d k r' = some (dg, s')

```

### `World/Conflicts.lean`

```lean
theorem mem_disagreeOn (c₁ c₂ : Claim C P) (a : C.Digest) :
    a ∈ disagreeOn reg c₁ c₂ ↔
    ∃ v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧ v₁ ≠ v₂

theorem mem_detect (cs : Finset (Claim C P)) (k : ConflictKey C) :
    k ∈ detect reg cs ↔
    ∃ c₁ ∈ cs, ∃ c₂ ∈ cs, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
    ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧ v₁ ≠ v₂ ∧
    k = (c₁.key.schema, c₁.key.subject, a)

theorem coverage (cs : Finset (Claim C P)) (c₁ c₂ : Claim C P)
    (h₁ : c₁ ∈ cs) (h₂ : c₂ ∈ cs) (hne : c₁ ≠ c₂) (hsame : sameSubject c₁ c₂)
    (a v₁ v₂ : C.Digest) (hv₁ : (a, v₁) ∈ c₁.stated reg) (hv₂ : (a, v₂) ∈ c₂.stated reg)
    (hv : v₁ ≠ v₂) : (c₁.key.schema, c₁.key.subject, a) ∈ detect reg cs

theorem soundness (cs : Finset (Claim C P)) (k : ConflictKey C) (hk : k ∈ detect reg cs) :
    ∃ c₁ ∈ cs, ∃ c₂ ∈ cs, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
    ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧ v₁ ≠ v₂ ∧
    k = (c₁.key.schema, c₁.key.subject, a)

theorem detectList_congr (l₁ l₂ : List (Claim C P)) (h : ∀ c, c ∈ l₁ ↔ c ∈ l₂) :
    detectList reg l₁ = detectList reg l₂

theorem detectList_perm (l₁ l₂ : List (Claim C P)) (h : l₁.Perm l₂) :
    detectList reg l₁ = detectList reg l₂

theorem detect_mono (cs cs' : Finset (Claim C P)) (h : cs ⊆ cs') :
    detect reg cs ⊆ detect reg cs'

theorem here depends on it. -/
def tableSchema : Schema C₀ Cols Sch.table where
    core

```

### `World/Visible.lean`

```lean
theorem deny_wins_id (n : Nat) (c : Claim C P) (h : S.deniesId (c.id d) = true) :
    visible d σ S n c = false

theorem deny_wins_origin (n : Nat) (c : Claim C P) (p : Pin C) (hp : p ∈ c.pins)
    (doc : C.SourceId) (r : Option C.Range) (ht : p.target = .source doc r)
    (h : S.deniesOrigin doc r = true) : visible d σ S n c = false

theorem deny_through_premise (n : Nat) (c : Claim C P) (p : Pin C) (hp : p ∈ c.pins)
    (i : C.ClaimId) (ht : p.target = .claim i) (c' : Claim C P) (hσ : σ i = some c')
    (h : denied d σ S n c' = true) : visible d σ S (n + 1) c = false

theorem conflict_hidden_of_alternative_denied (n : Nat) (k : Claim C P)
    (p : Pin C) (hp : p ∈ k.pins) (i : C.ClaimId) (ht : p.target = .claim i)
    (alt : Claim C P) (hσ : σ i = some alt)
    (q : Pin C) (hq : q ∈ alt.pins) (doc : C.SourceId) (r : Option C.Range)
    (hqt : q.target = .source doc r) (hden : S.deniesOrigin doc r = true) :
    visible d σ S (n + 2) k = false

theorem unpinned_hidden (n : Nat) (c : Claim C P) (hpins : c.pins = [])
    (hid : S.allowsId (c.id d) = false) : visible d σ S n c = false

theorem visible_pins (n : Nat) (c : Claim C P) (hv : visible d σ S (n + 1) c = true)
    (hid : S.allowsId (c.id d) = false) :
    c.pins ≠ [] ∧ ∀ p ∈ c.pins,
    (∀ doc r, p.target = .source doc r →
    S.allowsOrigin doc r = true ∧ S.deniesOrigin doc r = false) ∧
    (∀ i, p.target = .claim i → ∃ c', σ i = some c' ∧ visible d σ S n c' = true)

theorem denied_anti : ∀ (n : Nat) (c : Claim C P),
    denied d σ S (n + 1) c = true → denied d σ S n c = true

theorem allowed_mono : ∀ (n : Nat) (c : Claim C P),
    allowed d σ S n c = true → allowed d σ S (n + 1) c = true

theorem visible_mono (n : Nat) (c : Claim C P) (h : visible d σ S n c = true) :
    visible d σ S (n + 1) c = true

```

### `World/Minidregg.lean`

```lean
theorem in `World.Status` that needs injective ids takes it as a hypothesis,
and this theorem says what would discharge it. -/
theorem claimId_injective (dd : DigestDerivation) (encode : ClaimKey carriers → List UInt8)
    (hdd : Function.Injective dd.digestBytes) (henc : Function.Injective encode) :
    Function.Injective (claimIdDerivation dd encode).claimId

theorem sourcePinFresh_iff (lookup : AtomId → Option AtomRecord)
    (read : List (AtomId × OperationId)) :
    sourcePinFresh lookup read = true ↔
    ∀ ar ∈ read, ∃ rec, lookup ar.1 = some rec ∧ rec.revision = ar.2

theorem stale_of_moved (lookup : AtomId → Option AtomRecord)
    (read : List (AtomId × OperationId)) (a : AtomId) (r : OperationId)
    (hread : (a, r) ∈ read) (hmoved : ∀ rec, lookup a = some rec → rec.revision ≠ r) :
    sourcePinFresh lookup read = false

```

### `World/Examples.lean`

```lean
theorem Sch.code_injective : Function.Injective Sch.code

theorem d₀_injective : Function.Injective d₀.claimId

```
