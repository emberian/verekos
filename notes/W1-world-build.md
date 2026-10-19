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

---

## 2026-10-19, second quest: well-formedness, traversal, identity

All four steps are done, built and pushed to `origin/dev`. Nothing written into
minidregg (re-checked: no modified tracked files). A clean build of `World`
now takes **18 s** (`var/w1/build-clean-world-q2.log`). The slowest modules
are `World.Minidregg` (10 s), `World.Conflicts` (7.7 s), `World.WellFormed`
(6.4 s) and `World.Identity` (5.0 s); the Mathlib imports dominate. All 45 new
theorems were checked with `#print axioms` (full output below). Each uses at
most `propext`, `Classical.choice` and `Quot.sound`; six use no axioms at all.

### Step 1: the three rules (`World/WellFormed.lean`)

- **Pins nonempty** is `Claim.PinsNonempty`. It is used by
  `visible_iff_sourcePins`: a claim pinned only to sources is visible exactly
  when every origin is allowed and none is denied. Without the rule, the "if"
  direction would hold vacuously for an unpinned claim.
- **Sources sorted and deduplicated** is `ClaimKey.Canonical` (strictly
  increasing sources under a `LinearOrder` on source ids).
  `ClaimKey.normalize` sorts and deduplicates. `eq_iff_of_canonical` says
  canonical keys are equal iff schema, subject and source *set* agree.
  `normalize_eq_iff` says normalization identifies exactly the keys with the
  same source set. `Claim.WellFormed` combines the two rules.
  `latest_wellFormed` says a log that puts only well-formed claims has only
  well-formed claims in its state.
- **No pin cycles** is `Ranked σ rank`: a number per claim that strictly drops
  from every claim to each claim it pins in state `σ`. `Ranked.wellFounded`
  says the premise relation is well founded. I used a rank rather than bare
  well-foundedness because the brief asked for the bounded `visible` to
  stabilize "at or below the pin-graph depth". A rank *is* a depth bound,
  while well-foundedness alone gives no finite bound.
  - `visible_stable`: every bound above a claim's rank gives the same answer.
  - `visibleR` is visibility at rank + 1, and `visible_eq_visibleR` shows it is
    the limit.
  - `visibleR_rank_irrelevant`: two ranks for the same state give the same
    `visibleR`, so the unbounded visibility is well defined.
- **Self-review hypothesis removed.** `reviewSurvives_put_acyclic` replaces
  "`c'` is not a review of itself" with "the state after the put has a rank".
  A review of itself would pin its own id, which `latest_append_put` shows is
  present after the put, so it would be its own premise, which a rank forbids.
  The old `reviewSurvives_put` is kept: it is still true and is the weaker
  special case.
- `ranked₀` gives a concrete rank for the example state, and `visibleR` is
  evaluated with it.

### Step 2: traversal over facts (`World/Traverse.lean`)

`Reach L n x z`: `z` is reachable from seed `x` within `n` hops. A hop
crosses edge `e` from `a` to `b` (`Crosses`) only when:
- `e` is the current claim under its id;
- its schema is one of the requested types `T`;
- `EdgeView.ends e = some (a, b)`;
- the edge's status is a fact for its schema;
- both endpoints hold claims whose status is a fact.

The EKOS lines are confirmed by reading, as cited in the module docstring:
`is_pending_review` returns `false` for a missing status
(`kir/src/lib.rs:480-485`), and `tool_dependents` checks only the edge
(`mcp.rs:1933-1961`).

The theorems:
- `pending_edge_never_crossed`, and its global form
  `reach_trivial_of_all_pending`: if every edge of the requested types is
  pending, only the seed is reachable.
- `unreviewed_hypothesis_edge_not_crossed`: the statement the coordinator
  asked for. An edge whose schema's initial status is not a fact, with no
  admitted review, is not crossed.
- `unreviewed_hypothesis_node_blocks`: the same for endpoints, which EKOS does
  not check.
- **`reach_mono_confirm` is not "any confirming review only adds".** That
  statement is false of the model, so it carries three hypotheses, each
  explained in its docstring:
  - the review is put under a **fresh id**, because putting it over an existing
    claim replaces that claim in the state;
  - it is pinned at the target's **current core**, because a review at an old
    core turns the status into `needsReview`;
  - its decision is a **fact** for the target's schema.

  The conclusion is the full one: every `Reach` before is a `Reach` after.
  The proof needed `latest_id` (the state stores each claim under its own
  id), proved by induction over the replay.
- `reach_mono_hops` and `reach_mono_hops_le`: a larger hop bound only adds.

### Step 3: identity as an overlay (`World/Identity.lean`)

- `Same ls` is the equivalence closure (`Relation.EqvGen`) of a finite link
  set. `same_equivalence` says it is an equivalence relation.
- `classOf` and `canonical` (the least member of the class, under a
  `LinearOrder`) are **noncomputable**, because the class is a classical filter
  of the links' support.
  - `mem_classOf` is the exact characterization.
  - `canonical_eq_iff`: two keys share a canonical key iff they are `Same`.
  - `canonical_congr`: the canonical key depends only on the equivalence. Any
    two link sets with the same classes give the same canonical key, whatever
    links realized them and in whatever order. That is the order-independence
    content; `links_list_congr` adds that the order of candidate claims does
    not matter.
- `linkOf` gives a `SameAs` claim's link when it is current, its status is
  `confirmed`, and both pinned claims are present (as the pair of their keys).
  `links` is the union over a finite candidate set.
- `fuzzy_no_link` and `fuzzy_not_crossed`: an unconfirmed-initial `SameAs`
  with no admitted review makes no link, and traversal does not cross it.
- `merge_takes_effect`: an exact merge (a `SameAs` of a schema admitting the
  compiler, plus a compiler review confirming it at its core) links the two
  keys.
- **`merge_reversible`**: put the merge, put its review, retract the merge, and
  the link set is *equal* to the one before, so every class and canonical key
  is restored (`merge_reversible_canonical`). This needed hypotheses I had not
  foreseen, each stated and justified in the docstring:
  - fresh, distinct ids for the merge and its review;
  - the review targets the merge's id;
  - the merge is not itself a review;
  - the review is not a `SameAs` claim and is not pinned by any candidate.

  The review stays in the log. It just has no claim left to decide.
- Concrete run (`World/Examples.lean`, extended `Sch` with `fk`, `sameAs`,
  `sameAsExact`):
  - no links before;
  - `{(A, C)}` after the compiler's exact merge, with A's key canonical for C;
  - the same empty link set after retraction, with C its own canonical key;
  - `¬ Same A C` after retraction;
  - the fuzzy A–B candidate is not crossed after a compiler "confirmation", and
    is crossed after a human one.

### What I could not do in this round

- **The rules are predicates, not types.** Making `Claim` carry proofs would
  push obligations into every constructor and every `decide` example. I kept
  them as hypotheses that the theorems use.
- **No theorem preserves `Ranked` across a write.** A put can pin anything, so
  acyclicity has to be a law checked at admission (an L-obj style law in
  minidregg).
- **No function computes a rank from a finite acyclic state.** The rank is a
  supplied witness.
- **`canonical` is noncomputable.** A computable class (iterate the closure up
  to the support's size) with a proof of agreement is a follow-up.

### Follow-ups (in order)

1. An admission law: a put is accepted only if the resulting state stays
   ranked. Prove that a rank extends (new claim's rank = 1 + the maximum of its
   premises' ranks).
2. A computable `canonical`, proved equal to the classical one.
3. Identity combined with traversal: read edges through the class view, so an
   edge to a merged-away key reaches the class. That is design §3's "edges
   keep their original endpoint keys and are read through the class".
4. Claim-pin staleness as a separate checkable predicate, tied to
   `needsReview`.

### Every new theorem statement, quoted from the source


#### `World/WellFormed.lean`

```lean
theorem ClaimKey.normalize_canonical (k : ClaimKey C) : k.normalize.Canonical

theorem ClaimKey.mem_normalize (k : ClaimKey C) (s : C.SourceId) :
    s ∈ k.normalize.sources ↔ s ∈ k.sources

theorem ClaimKey.eq_iff_of_canonical (k₁ k₂ : ClaimKey C) (h₁ : k₁.Canonical)
    (h₂ : k₂.Canonical) :
    k₁ = k₂ ↔ k₁.schema = k₂.schema ∧ k₁.subject = k₂.subject ∧
    ∀ s, s ∈ k₁.sources ↔ s ∈ k₂.sources

theorem ClaimKey.normalize_eq_iff (k₁ k₂ : ClaimKey C) :
    k₁.normalize = k₂.normalize ↔ k₁.schema = k₂.schema ∧ k₁.subject = k₂.subject ∧
    ∀ s, s ∈ k₁.sources ↔ s ∈ k₂.sources

theorem ClaimKey.normalize_of_canonical (k : ClaimKey C) (h : k.Canonical) :
    k.normalize = k

theorem foldl_apply_wellFormed (d : ClaimIdDerivation C) :
    ∀ (L : List (Receipt C P)) (s : View C P),
    (∀ i c, s i = some c → c.WellFormed) → LogWellFormed L →
    ∀ i c, (L.foldl (apply d) s) i = some c → c.WellFormed

theorem latest_wellFormed (d : ClaimIdDerivation C) (L : List (Receipt C P))
    (h : LogWellFormed L) (i : C.ClaimId) (c : Claim C P)
    (hc : latest d L i = some c) : c.WellFormed

theorem Ranked.wellFounded {σ : C.ClaimId → Option (Claim C P)} {rank : Claim C P → Nat}
    (hr : Ranked σ rank) : WellFounded (PremiseOf σ)

theorem Ranked.not_self {σ : C.ClaimId → Option (Claim C P)} {rank : Claim C P → Nat}
    (hr : Ranked σ rank) (c : Claim C P) : ¬ PremiseOf σ c c

theorem any_congr_mem {α : Type} (l : List α) (f g : α → Bool)
    (h : ∀ a ∈ l, f a = g a) : l.any f = l.any g

theorem all_congr_mem {α : Type} (l : List α) (f g : α → Bool)
    (h : ∀ a ∈ l, f a = g a) : l.all f = l.all g

theorem denied_stable (hr : Ranked σ rank) :
    ∀ (n m : Nat) (c : Claim C P), rank c < n → rank c < m →
    denied d σ S n c = denied d σ S m c

theorem allowed_stable (hr : Ranked σ rank) :
    ∀ (n m : Nat) (c : Claim C P), rank c < n → rank c < m →
    allowed d σ S n c = allowed d σ S m c

theorem visible_stable (hr : Ranked σ rank) (n m : Nat) (c : Claim C P)
    (hn : rank c < n) (hm : rank c < m) : visible d σ S n c = visible d σ S m c

theorem visible_eq_visibleR (hr : Ranked σ rank) (n : Nat) (c : Claim C P)
    (hn : rank c < n) : visible d σ S n c = visibleR d σ S rank c

theorem visibleR_rank_irrelevant {rank' : Claim C P → Nat} (hr : Ranked σ rank)
    (hr' : Ranked σ rank') (c : Claim C P) :
    visibleR d σ S rank c = visibleR d σ S rank' c

theorem visible_iff_sourcePins (n : Nat) (c : Claim C P) (hne : c.PinsNonempty)
    (hsrc : ∀ p ∈ c.pins, ∃ doc r, p.target = .source doc r)
    (hid : S.allowsId (c.id d) = false) (hdid : S.deniesId (c.id d) = false) :
    visible d σ S (n + 1) c = true ↔
    ∀ p ∈ c.pins, ∀ doc r, p.target = .source doc r →
    S.allowsOrigin doc r = true ∧ S.deniesOrigin doc r = false

theorem asReview_pins (c : Claim C P) (i : C.ClaimId) (dg : C.Digest) (s : Status)
    (h : asReview R c = some (i, dg, s)) : ∃ w, c.pins = [⟨.claim i, .core dg, w⟩]

theorem latest_append_put (L : List (Receipt C P)) (r : Receipt C P) (c : Claim C P)
    (hop : r.op = .put c) : latest d (L ++ [r]) (c.id d) = some c

theorem reviewSurvives_put_acyclic [∀ s, DecidableEq (P s)]
    (hinj : Function.Injective d.claimId)
    (L : List (Receipt C P)) (c c' : Claim C P) (r : Receipt C P) (hop : r.op = .put c')
    {rank : Claim C P → Nat} (hacyc : Ranked (latest d (L ++ [r])) rank)
    (hid : c.id d = c'.id d) (hcore : c.core reg = c'.core reg) :
    status R reg d (L ++ [r]) c' = status R reg d L c

```

#### `World/Traverse.lean`

```lean
theorem pending_edge_never_crossed (L : List (Receipt C P)) (e : Claim C P)
    (a b : C.ClaimId) (h : (reg e.key.schema).isFact (status R reg d L e) = false) :
    ¬ Crosses R reg d E T L e a b

theorem reach_trivial_of_all_pending (L : List (Receipt C P))
    (hall : ∀ e, T e.key.schema = true → E.ends e ≠ none →
    (reg e.key.schema).isFact (status R reg d L e) = false)
    {n : Nat} {x z : C.ClaimId} (h : Reach R reg d E T L n x z) : x = z

theorem status_of_no_reviews (L : List (Receipt C P)) (c : Claim C P)
    (h : admittedReviews R reg d L c.key = []) :
    status R reg d L c = (reg c.key.schema).initial

theorem unreviewed_hypothesis_edge_not_crossed (L : List (Receipt C P)) (e : Claim C P)
    (a b : C.ClaimId)
    (hinit : (reg e.key.schema).isFact (reg e.key.schema).initial = false)
    (hnone : admittedReviews R reg d L e.key = []) :
    ¬ Crosses R reg d E T L e a b

theorem unreviewed_hypothesis_node_blocks (L : List (Receipt C P)) (e c : Claim C P)
    (a b : C.ClaimId) (hb : latest d L b = some c)
    (hinit : (reg c.key.schema).isFact (reg c.key.schema).initial = false)
    (hnone : admittedReviews R reg d L c.key = []) :
    ¬ Crosses R reg d E T L e a b

theorem reach_mono_hops (L : List (Receipt C P)) {n : Nat} {x z : C.ClaimId}
    (h : Reach R reg d E T L n x z) : Reach R reg d E T L (n + 1) x z

theorem reach_mono_hops_le (L : List (Receipt C P)) {n m : Nat} (hnm : n ≤ m)
    {x z : C.ClaimId} (h : Reach R reg d E T L n x z) : Reach R reg d E T L m x z

theorem foldl_apply_id : ∀ (L : List (Receipt C P)) (s : View C P),
    (∀ i c, s i = some c → c.id d = i) →
    ∀ i c, (L.foldl (apply d) s) i = some c → c.id d = i

theorem latest_id (L : List (Receipt C P)) (i : C.ClaimId) (c : Claim C P)
    (h : latest d L i = some c) : c.id d = i

theorem latest_append_fresh (L : List (Receipt C P)) (r : Receipt C P) (rv : Claim C P)
    (hop : r.op = .put rv) (j : C.ClaimId) (hj : j ≠ rv.id d) :
    latest d (L ++ [r]) j = latest d L j

theorem reach_mono_confirm (L : List (Receipt C P)) (r : Receipt C P) (rv t : Claim C P)
    (s : Status) (hop : r.op = .put rv) (hfresh : latest d L (rv.id d) = none)
    (ht : latest d L (t.id d) = some t)
    (hrev : reviewOf R reg d t.key r = some (t.core reg, s))
    (hfact : (reg t.key.schema).isFact s = true)
    {n : Nat} {x z : C.ClaimId} (h : Reach R reg d E T L n x z) :
    Reach R reg d E T (L ++ [r]) n x z

```

#### `World/Identity.lean`

```lean
theorem same_equivalence (ls : Finset (α × α)) : Equivalence (Same ls)

theorem same_eq_or_support (ls : Finset (α × α)) {x y : α} (h : Same ls x y) :
    x = y ∨ (x ∈ support ls ∧ y ∈ support ls)

theorem mem_classOf (ls : Finset (α × α)) (x y : α) : y ∈ classOf ls x ↔ Same ls x y

theorem classOf_nonempty (ls : Finset (α × α)) (x : α) : (classOf ls x).Nonempty

theorem same_canonical (ls : Finset (α × α)) (x : α) : Same ls x (canonical ls x)

theorem canonical_le (ls : Finset (α × α)) (x y : α) (h : Same ls x y) :
    canonical ls x ≤ y

theorem classOf_eq_of_same (ls : Finset (α × α)) (x y : α) (h : Same ls x y) :
    classOf ls x = classOf ls y

theorem canonical_eq_iff (ls : Finset (α × α)) (x y : α) :
    canonical ls x = canonical ls y ↔ Same ls x y

theorem canonical_congr (l₁ l₂ : Finset (α × α)) (h : ∀ a b, Same l₁ a b ↔ Same l₂ a b)
    (x : α) : canonical l₁ x = canonical l₂ x

theorem links_congr (L L' : List (Receipt C P)) (cands : Finset (Claim C P))
    (h : ∀ c ∈ cands, linkOf R reg d V L c = linkOf R reg d V L' c) :
    links R reg d V L cands = links R reg d V L' cands

theorem links_list_congr (L : List (Receipt C P)) (l₁ l₂ : List (Claim C P))
    (h : ∀ c, c ∈ l₁ ↔ c ∈ l₂) :
    links R reg d V L l₁.toFinset = links R reg d V L l₂.toFinset

theorem fuzzy_no_link (L : List (Receipt C P)) (c : Claim C P)
    (hinit : (reg c.key.schema).initial ≠ .confirmed)
    (hnone : admittedReviews R reg d L c.key = []) : linkOf R reg d V L c = none

theorem fuzzy_not_crossed (T : C.SchemaId → Bool) (L : List (Receipt C P)) (c : Claim C P)
    (a b : C.ClaimId)
    (hinit : (reg c.key.schema).isFact (reg c.key.schema).initial = false)
    (hnone : admittedReviews R reg d L c.key = []) :
    ¬ Crosses R reg d (sameAsEdges V) T L c a b

theorem latest_snoc (L : List (Receipt C P)) (r : Receipt C P) :
    latest d (L ++ [r]) = apply d (latest d L) r

theorem merge_takes_effect (L : List (Receipt C P)) (cands : Finset (Claim C P))
    (m rv ca cb : Claim C P) (a b : C.ClaimId) (r₁ r₂ : Receipt C P)
    (hm : m ∈ cands) (h₁ : r₁.op = .put m) (h₂ : r₂.op = .put rv)
    (hends : asSameAs V m = some (a, b))
    (hrev : reviewOf R reg d m.key r₂ = some (m.core reg, .confirmed))
    (hne : rv.id d ≠ m.id d)
    (ha : latest d L a = some ca) (hb : latest d L b = some cb)
    (ha' : a ≠ m.id d ∧ a ≠ rv.id d) (hb' : b ≠ m.id d ∧ b ≠ rv.id d) :
    (ca.key, cb.key) ∈ links R reg d V (L ++ [r₁, r₂]) cands ∧
    Same (links R reg d V (L ++ [r₁, r₂]) cands) ca.key cb.key

theorem merge_reversible (L : List (Receipt C P)) (cands : Finset (Claim C P))
    (m rv : Claim C P) (r₁ r₂ r₃ : Receipt C P)
    (h₁ : r₁.op = .put m) (h₂ : r₂.op = .put rv) (h₃ : r₃.op = .retract (m.id d))
    (hmFresh : latest d L (m.id d) = none) (hrvFresh : latest d L (rv.id d) = none)
    (hne : rv.id d ≠ m.id d)
    (hmNotRev : asReview R m = none)
    (hrvOf : ∃ dg s, asReview R rv = some (m.id d, dg, s))
    (hrvNotSameAs : asSameAs V rv = none)
    (hends : ∀ c ∈ cands, ∀ a b, asSameAs V c = some (a, b) → a ≠ rv.id d ∧ b ≠ rv.id d) :
    links R reg d V (L ++ [r₁, r₂, r₃]) cands = links R reg d V L cands

theorem merge_reversible_canonical [LinearOrder (ClaimKey C)]
    (L : List (Receipt C P)) (cands : Finset (Claim C P))
    (m rv : Claim C P) (r₁ r₂ r₃ : Receipt C P)
    (h₁ : r₁.op = .put m) (h₂ : r₂.op = .put rv) (h₃ : r₃.op = .retract (m.id d))
    (hmFresh : latest d L (m.id d) = none) (hrvFresh : latest d L (rv.id d) = none)
    (hne : rv.id d ≠ m.id d)
    (hmNotRev : asReview R m = none)
    (hrvOf : ∃ dg s, asReview R rv = some (m.id d, dg, s))
    (hrvNotSameAs : asSameAs V rv = none)
    (hends : ∀ c ∈ cands, ∀ a b, asSameAs V c = some (a, b) → a ≠ rv.id d ∧ b ≠ rv.id d)
    (k : ClaimKey C) :
    canonical (links R reg d V (L ++ [r₁, r₂, r₃]) cands) k =
    canonical (links R reg d V L cands) k

```

#### `World/Examples.lean` (new theorems)

```lean
theorem ranked₀ : Ranked σ₀ rank₀

theorem same_empty {α : Type} [DecidableEq α] (x y : α) (h : Same (∅ : Finset (α × α)) x y) :
    x = y

theorem keyCode_injective : Function.Injective keyCode

```

### `#print axioms`, verbatim

```
'World.ClaimKey.normalize_canonical' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.ClaimKey.mem_normalize' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.ClaimKey.eq_iff_of_canonical' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.ClaimKey.normalize_eq_iff' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.ClaimKey.normalize_of_canonical' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.foldl_apply_wellFormed' depends on axioms: [propext]
'World.latest_wellFormed' depends on axioms: [propext]
'World.Ranked.wellFounded' does not depend on any axioms
'World.Ranked.not_self' does not depend on any axioms
'World.any_congr_mem' does not depend on any axioms
'World.all_congr_mem' does not depend on any axioms
'World.denied_stable' depends on axioms: [propext, Quot.sound]
'World.allowed_stable' depends on axioms: [propext, Quot.sound]
'World.visible_stable' depends on axioms: [propext, Quot.sound]
'World.visible_eq_visibleR' depends on axioms: [propext, Quot.sound]
'World.visibleR_rank_irrelevant' depends on axioms: [propext, Quot.sound]
'World.visible_iff_sourcePins' depends on axioms: [propext, Quot.sound]
'World.asReview_pins' depends on axioms: [propext]
'World.latest_append_put' depends on axioms: [propext, Quot.sound]
'World.reviewSurvives_put_acyclic' depends on axioms: [propext, Quot.sound]
'World.pending_edge_never_crossed' depends on axioms: [propext]
'World.reach_trivial_of_all_pending' depends on axioms: [propext]
'World.status_of_no_reviews' depends on axioms: [propext]
'World.unreviewed_hypothesis_edge_not_crossed' depends on axioms: [propext]
'World.unreviewed_hypothesis_node_blocks' depends on axioms: [propext]
'World.reach_mono_hops' depends on axioms: [propext]
'World.reach_mono_hops_le' depends on axioms: [propext]
'World.foldl_apply_id' does not depend on any axioms
'World.latest_id' does not depend on any axioms
'World.latest_append_fresh' depends on axioms: [propext, Quot.sound]
'World.reach_mono_confirm' depends on axioms: [propext, Quot.sound]
'World.same_equivalence' depends on axioms: [propext, Quot.sound]
'World.same_eq_or_support' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.mem_classOf' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.classOf_nonempty' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.same_canonical' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.canonical_le' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.classOf_eq_of_same' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.canonical_eq_iff' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.canonical_congr' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.links_congr' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.links_list_congr' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.fuzzy_no_link' depends on axioms: [propext]
'World.fuzzy_not_crossed' depends on axioms: [propext]
'World.latest_snoc' depends on axioms: [propext, Quot.sound]
'World.merge_takes_effect' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.merge_reversible' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.merge_reversible_canonical' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.Example.keyCode_injective' depends on axioms: [propext, Quot.sound]
'World.Example.same_empty' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.Example.ranked₀' depends on axioms: [propext, Quot.sound]
```

---

## 2026-10-19, third quest: admission, computed rank, the document shape

All four items are done, built and pushed to `origin/dev`. A clean build of
`World` takes **13 s** (`var/w1/build-clean-world-q3.log`). minidregg is
untouched (no modified tracked files). `#print axioms` on all 30 new
theorems (output below) shows only `propext`, `Classical.choice` and
`Quot.sound`, or no axioms. There is no `sorry`, `admit` or `native_decide`.

### 1. The admission law (`World/Admission.lean`)

A put of `c` is `admissible` against the log before it when:
- every claim pin of `c` names an id that is present in the state and is not
  `c`'s own id; and
- if `c`'s id has a recorded rank `k`, then `c`'s computed rank is `≤ k`.

The computed rank (`newRank`) is `1 +` the largest recorded rank among the
pinned ids, or 0 with no claim pins. The recorded ranks (`rankMap`) are
replayed from the log like the state: a put records its claim's rank, a
retract keeps the record.

**Why the second condition, which the coordinator's version did not have.**
"Every claim pin names a present id of lower rank" is not enough. A claim `x`
pins `i`. Then `i` is retracted (so `x`'s pin dangles), and `i` is re-put
pinning `x`. Every pin of the new `i` names a present id, yet `i → x → i` is a
cycle. Keeping the record across the retraction, and forbidding the rank at an
id to rise, closes that. The cost is that a claim cannot be re-put under its
own id with deeper premises. The README states this limit; the fuller law
would re-rank dependents.

Theorems:
- `AdmLog L` (every receipt admissible against its prefix) is decidable, with
  an instance, and `admLog_snoc` splits it at the last receipt.
- `ranked_of_admLog`: an admissible log yields `Ranked (latest d L) (rankN d L)`.
  The proof keeps an invariant `RankInv` through each write (`rankInv_snoc`):
  - every claim in the state has a recorded rank at least its computed rank;
  - every claim pin of a claim in the state names an id with a recorded rank.
- `rankOf_some_of_admLog`: `rankOf` (which is `none` exactly when a claim pins
  an id the log never put) gives `some (rankN d L c)` for every claim in the
  state.
- `not_admissible_self_pin`, `not_admissible_absent_pin`: the two refusals.

### 2. A computed rank

`rankN`/`rankOf` are computed by **structural recursion over the log**, not
over fuel equal to "the state's size". A state here is a function, which has
no size; the log is what makes it finite, and the replay is the bounded
recursion. In `World/Examples.lean` the example state is now the replay of a
two-receipt log, and the hand-written rank `rank₀` is gone:
- `admLσ : AdmLog d₀ Lσ` is checked by `decide`;
- `ranked₀ : Ranked σ₀ (rankN d₀ Lσ)` comes from `ranked_of_admLog`;
- `visibleR` uses the computed rank, and the computed ranks are 0 for tables
  and 1 for the conflict;
- two refusals, by `decide`: a claim pinning not-yet-present ids, and file A's
  table re-put pinning file B's (its rank would rise);
- one acceptance, by `decide`.

Every earlier example still passes.

### 3. The document shape (`World/Document.lean`)

`Cell` holds:
- `header`: the key;
- `properties`: the payload;
- `window`;
- `evidence`: a list of `Evidence`, each an `EvidenceMeta` (weight per mille,
  range) plus a `SnapshotPin` (source document, atoms with revisions);
- `premises`: a list of `PremiseLink` (target id, core read, weight).

`ObjectDocument` is an object `Cell` plus `EdgeContainer`s, each holding the
edge's cell and its `link`. Premise links are our addition to exploration
01 §2.1: objects there pin only sources, but reviews, conflicts and edges pin
claims. A pin of the wrong shape is refused by `encode`. A field originally
named `meta` was renamed `info` because `meta` is a Lean keyword.

Round trips:
- `decode_encode`: the claim comes back with the same key, payload and window,
  and its pins permuted (source pins first).
- `encode_decode`: the cell comes back **exactly**.
- `cellAtomPins_encode` and `claimAtomPins_decode`: the (source document,
  atom revision) pins are kept both ways.
- `toDocument_atomPins` and `fromDocument_atomPins` say the same for whole
  documents with their outgoing edges.

Live names from K12T: `TranscludeRefusal.sourceNotCovered` and `.staleOpening`
(`admitEvidence_none` characterizes admission), and
`PinView.noGrant n` (the placeholder), `.moved` and `.sameBytes`.
- `viewEvidence_noGrant`: a reader without a grant gets only the placeholder.
- `viewEvidence_sameBytes`: with a grant, the same bytes exactly when every
  atom is at its pinned revision, otherwise `moved`.

The view takes grants and current revisions as functions; it does not model
heights, so K12T's `moved:27:live` (moved *since height 27*) appears here as
plain `moved`.

**Audience.**
- `readerScope readable` allows exactly the origins in the readable sources,
  denies nothing, and allows no id outright.
- `visibleR_iff_readable`: for a claim with at least one pin, all of them
  source pins, `visibleR` under the reader's scope is true exactly when every
  evidence container's source is readable.
- `visibleR_iff_room`: with sources assigned to rooms and readability "holds
  the room's grant", a claim pinned only into room `ρ` is visible exactly when
  the reader holds `ρ`'s grant.
- Both need two hypotheses, stated in the docstring:
  - **at least one pin**: otherwise the claim is hidden while "every source is
    readable" holds vacuously;
  - **source pins only**: a claim pin adds the premise's visibility, which the
    claim's own evidence containers do not show.
- The example file applies `visibleR_iff_room` to a table pinned to two atoms
  of file A, in room 1.

### What I could not do

- **Only the object cell is modelled.** The source, manifest, conflict,
  review and compile-run documents of exploration 01 §2.1 are not.
- **Grants, heights and audience rosters are abstracted** to functions. The
  audience theorem is about the scope a grant induces, not about minidregg's
  `audienceEpoch`/`audienceRoster`.
- **A field-for-field equality with minidregg's `TransclusionRecord` is not
  stated.** `SnapshotPin` instantiated in `World.Minidregg` is
  `DocumentId × List (AtomId × OperationId)`, the same shape as
  `TranscludeRequest.pins`.

### Follow-ups

1. A re-ranking admission law (allow a rank to rise when no present claim pins
   the id), with `ranked_of_admLog` re-proved.
2. `encode` into minidregg's own records: a `World.Minidregg` function from
   `Cell` to `DocumentRecord`, `AtomRecord` and `TransclusionRecord` values,
   with the atom-pin theorem against `TranscludeRequest.pins`.
3. Audience for claims with claim pins (conflicts and reviews), via
   `visibleR` recursion on the rank. Exploration 01 §2.5 says a conflict is
   visible only if every alternative's origin is visible, which
   `conflict_hidden_of_alternative_denied` already gives in one direction.

### Every new theorem statement, quoted from the source


#### `World/Admission.lean`

```lean
theorem lt_maxPinRank (m : RankMap C) (ps : List (Pin C)) (p : Pin C) (hp : p ∈ ps)
    (j : C.ClaimId) (ht : p.target = .claim j) : (m j).getD 0 < maxPinRank m ps

theorem maxPinRank_mono (m m' : RankMap C) (ps : List (Pin C))
    (h : ∀ p ∈ ps, ∀ j, p.target = .claim j → (m' j).getD 0 ≤ (m j).getD 0) :
    maxPinRank m' ps ≤ maxPinRank m ps

theorem maxPinRank_congr (m m' : RankMap C) (ps : List (Pin C))
    (h : ∀ p ∈ ps, ∀ j, p.target = .claim j → m' j = m j) :
    maxPinRank m' ps = maxPinRank m ps

theorem admLog_snoc (L : List (Receipt C P)) (r : Receipt C P) :
    AdmLog d (L ++ [r]) ↔ AdmLog d L ∧ admissible d L r = true

theorem rankMap_snoc (L : List (Receipt C P)) (r : Receipt C P) :
    rankMap d (L ++ [r]) = rstep d (rankMap d L) r

theorem latest_snoc' (L : List (Receipt C P)) (r : Receipt C P) :
    latest d (L ++ [r]) = apply d (latest d L) r

theorem rankInv_snoc (L : List (Receipt C P)) (r : Receipt C P) (hinv : RankInv d L)
    (hadm : admissible d L r = true) : RankInv d (L ++ [r])

theorem rankInv_of_admLog : ∀ (L : List (Receipt C P)), AdmLog d L → RankInv d L

theorem ranked_of_admLog (L : List (Receipt C P)) (h : AdmLog d L) :
    Ranked (latest d L) (rankN d L)

theorem rankOf_some_of_admLog (L : List (Receipt C P)) (h : AdmLog d L)
    (i : C.ClaimId) (c : Claim C P) (hc : latest d L i = some c) :
    rankOf d L c = some (rankN d L c)

theorem not_admissible_self_pin (L : List (Receipt C P)) (r : Receipt C P) (c : Claim C P)
    (hop : r.op = .put c) (p : Pin C) (hp : p ∈ c.pins) (ht : p.target = .claim (c.id d)) :
    admissible d L r = false

theorem not_admissible_absent_pin (L : List (Receipt C P)) (r : Receipt C P) (c : Claim C P)
    (hop : r.op = .put c) (p : Pin C) (hp : p ∈ c.pins) (j : C.ClaimId)
    (ht : p.target = .claim j) (habs : latest d L j = none) :
    admissible d L r = false

```

#### `World/Document.lean`

```lean
theorem toEvidence_map (p : Pin C) (h : p.wellTyped = true) :
    (p.toEvidence).map Evidence.toPin = if p.isSource then some p else none

theorem toPremise_map (p : Pin C) (h : p.wellTyped = true) :
    (p.toPremise).map PremiseLink.toPin = if p.isSource then none else some p

theorem filterMap_map_eq_filter {α β : Type} (f : α → Option β) (g : β → α) (q : α → Bool)
    (l : List α) (h : ∀ a ∈ l, (f a).map g = if q a then some a else none) :
    (l.filterMap f).map g = l.filter q

theorem decode_encode (c : Claim C P) (cell : Cell C P) (h : encode c = some cell) :
    ∃ ps, decode cell = { c with pins

theorem encode_decode (cell : Cell C P) : encode (decode cell) = some cell

theorem claimAtomPins_perm (c c' : Claim C P) (h : c'.pins.Perm c.pins) (x : C.SourceId × C.AtomRev) :
    x ∈ claimAtomPins c' ↔ x ∈ claimAtomPins c

theorem claimAtomPins_decode (cell : Cell C P) (x : C.SourceId × C.AtomRev) :
    x ∈ claimAtomPins (decode cell) ↔ x ∈ cellAtomPins cell

theorem cellAtomPins_encode (c : Claim C P) (cell : Cell C P) (h : encode c = some cell)
    (x : C.SourceId × C.AtomRev) : x ∈ cellAtomPins cell ↔ x ∈ claimAtomPins c

theorem encodeEdges_atomPins (from_ : C.ClaimId) :
    ∀ (es : List (Claim C P)) (ecs : List (EdgeContainer C P)),
    encodeEdges E from_ es = some ecs → ∀ x,
    x ∈ ecs.flatMap (fun ec => cellAtomPins ec.edge) ↔ ∃ e ∈ es, x ∈ claimAtomPins e

theorem toDocument_atomPins (c : Claim C P) (outgoing : List (Claim C P))
    (D : ObjectDocument C P) (h : toDocument d E c outgoing = some D)
    (x : C.SourceId × C.AtomRev) :
    x ∈ docAtomPins D ↔ x ∈ claimAtomPins c ∨ ∃ e ∈ outgoing, x ∈ claimAtomPins e

theorem fromDocument_atomPins (D : ObjectDocument C P) (x : C.SourceId × C.AtomRev) :
    x ∈ docAtomPins D ↔
    x ∈ claimAtomPins (fromDocument D).1 ∨ ∃ e ∈ (fromDocument D).2, x ∈ claimAtomPins e

theorem viewEvidence_noGrant (readable : C.SourceId → Bool)
    (current : C.SourceId → C.AtomRev → Bool) (e : Evidence C) :
    readable e.pin.source = false ↔ viewEvidence readable current e = .noGrant e.pin.atoms.length

theorem viewEvidence_sameBytes (readable : C.SourceId → Bool)
    (current : C.SourceId → C.AtomRev → Bool) (e : Evidence C)
    (hr : readable e.pin.source = true) :
    viewEvidence readable current e = .sameBytes ↔ ∀ a ∈ e.pin.atoms, current e.pin.source a = true

theorem admitEvidence_none (writerReads : C.SourceId → Bool)
    (held : C.SourceId → C.AtomRev → Bool) (e : Evidence C) :
    admitEvidence writerReads held e = none ↔
    writerReads e.pin.source = true ∧ ∀ a ∈ e.pin.atoms, held e.pin.source a = true

theorem visibleR_iff_readable (rank : Claim C P → Nat) (readable : C.SourceId → Bool)
    (c : Claim C P) (cell : Cell C P) (hc : encode c = some cell)
    (hne : c.PinsNonempty) (hsrc : ∀ p ∈ c.pins, ∃ doc r, p.target = .source doc r) :
    visibleR d σ (readerScope readable) rank c = true ↔
    ∀ e ∈ cell.evidence, readable e.pin.source = true

theorem visibleR_iff_room {Room : Type} (rank : Claim C P → Nat) (roomOf : C.SourceId → Room)
    (grants : Room → Bool) (ρ : Room) (c : Claim C P) (cell : Cell C P)
    (hc : encode c = some cell) (hne : c.PinsNonempty)
    (hroom : ∀ p ∈ c.pins, ∃ doc r, p.target = .source doc r ∧ roomOf doc = ρ) :
    visibleR d σ (readerScope fun doc => grants (roomOf doc)) rank c = true ↔
    grants ρ = true

```

#### `World/Examples.lean` (new and changed theorems)

```lean
theorem admLσ : AdmLog d₀ Lσ

theorem ranked₀ : Ranked σ₀ (rankN d₀ Lσ)

```

### `#print axioms`, verbatim

```
'World.lt_maxPinRank' depends on axioms: [propext, Quot.sound]
'World.maxPinRank_mono' depends on axioms: [propext, Quot.sound]
'World.maxPinRank_congr' depends on axioms: [propext, Quot.sound]
'World.admLog_snoc' depends on axioms: [propext, Quot.sound]
'World.rankMap_snoc' depends on axioms: [propext, Quot.sound]
'World.latest_snoc'' depends on axioms: [propext, Quot.sound]
'World.rankInv_snoc' depends on axioms: [propext, Quot.sound]
'World.rankInv_of_admLog' depends on axioms: [propext, Quot.sound]
'World.ranked_of_admLog' depends on axioms: [propext, Quot.sound]
'World.rankOf_some_of_admLog' depends on axioms: [propext, Quot.sound]
'World.not_admissible_self_pin' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.not_admissible_absent_pin' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.toEvidence_map' depends on axioms: [propext]
'World.toPremise_map' depends on axioms: [propext]
'World.filterMap_map_eq_filter' depends on axioms: [propext]
'World.decode_encode' depends on axioms: [propext, Quot.sound]
'World.encode_decode' depends on axioms: [propext, Quot.sound]
'World.claimAtomPins_perm' depends on axioms: [propext, Quot.sound]
'World.claimAtomPins_decode' depends on axioms: [propext, Quot.sound]
'World.cellAtomPins_encode' depends on axioms: [propext, Quot.sound]
'World.encodeEdges_atomPins' depends on axioms: [propext, Quot.sound]
'World.toDocument_atomPins' depends on axioms: [propext, Quot.sound]
'World.fromDocument_atomPins' depends on axioms: [propext, Quot.sound]
'World.viewEvidence_noGrant' depends on axioms: [propext]
'World.viewEvidence_sameBytes' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.admitEvidence_none' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.visibleR_iff_readable' depends on axioms: [propext, Quot.sound]
'World.visibleR_iff_room' depends on axioms: [propext, Quot.sound]
'World.Example.admLσ' does not depend on any axioms
'World.Example.ranked₀' depends on axioms: [propext, Quot.sound]
```

---

## 2026-10-19, fourth quest: the other shapes, carry-forward, the manifest

All four items are done, built and pushed to `origin/dev`. A clean build of
`World` takes **14 s** (`var/w1/build-clean-world-q4.log`). minidregg is
untouched. `#print axioms` on all 37 new theorems (below) shows only
`propext`, `Classical.choice` and `Quot.sound`, or no axioms.
`notes/W17-slice1.md` did not exist while I worked, so the shapes follow
exploration 01 as written. If W17 records approximations the deployed client
forced, these shapes should be compared against them.

### 1. The other shapes (`World/Shapes.lean`)

Each shape has:
- a content record (what it means);
- `encode`/`decode`;
- `decode (encode x) = x`;
- `encode (decode D) = D` for every document whose derived fields are
  consistent, so the derived fields are the only thing a document can get
  wrong;
- atom-pin preservation where the shape pins atoms.

The shapes:
- **source**: atom ids derived from structural keys (`WellKeyed`).
  - `reimport_unchanged`: re-importing an unchanged file changes nothing,
    given distinct keys.
  - `reimport_rev_iff`: **a pin moves exactly when its statement changed**.
    An atom keeps its revision iff its bytes are unchanged, at a fresh
    revision.
- **manifest**:
  - `mem_current_compile`: after a compile, the current set is exactly what
    was emitted;
  - `history_kept`: every entry is still there, live or unlinked.
- **conflict**: the derived field is the signature over the attribute and the
  members' (value, source), with lines left out as in EKOS's `signature`
  (`conflicts.rs:162-171`). `Disputes` points at the subject. There is no
  `chosen` field. `atomPins_encodeConflict` says every member keeps its pins.
- **review**: each decision container pins exactly one header atom revision
  (decoding refuses any other). `append_prefix` says the document is
  append-only.
- **compile-run / replay-attestation**:
  - these hold no derived fields, so their round trip is structural; I say so
    rather than invent one;
  - `not_replayed_by_compiler`: the compiler cannot attest its own
    determinism;
  - `not_replayed_if_outputs_differ`: a differing replay never earns
    `replayedDeterministic`;
  - input pins keep their read heights (`mem_atomPins_compileRun`).
- Field renames forced by Lean keywords: `attribute` became `attr`, EKOS's
  `open` became `EStatus.isOpen` (the earlier `meta` became `info`).

### 2. The transclusion is the carry-forward rule (`World/CarryForward.lean`)

- `compileHeader` rewrites the conflict header atom, at a fresh revision, only
  when the signature changes. `compileHeader_rev_eq_iff` says the revision
  moves exactly when the signature changes.
- `pin_sameBytes_iff` and `pin_moved_iff` describe the review's snapshot pin
  of the header. It reads same bytes iff **every** compile since the review
  had the reviewed signature, and `moved` iff some compile changed it.
  `renderHeaderPin_eq_viewEvidence` ties this to `World.Document.viewEvidence`.
- EKOS `carry_forward` (`conflicts.rs:506-535`) is modelled line by line in
  `ekosCompile`:
  - an open conflict stays open (its early `return` on `OPEN`);
  - a decided one keeps its review iff `reviewed_signature ==` the fresh
    `signature`;
  - otherwise it reopens as `open`, with `previous_review` kept.

  `ekos_holds_iff`: after a review, it holds iff every later compile had the
  reviewed signature.
- **`pin_agrees_with_ekos`**: the pin reads same bytes iff EKOS's review holds.
  The design's claim holds exactly.
- **Two corrections to the brief's wording, both stated in docstrings.**
  - **"Same bytes iff the signature is unchanged" means unchanged throughout
    the history since the review**, not merely "equal again now". Both the pin
    and EKOS stay reopened after A → B → A.
  - **The agreement with `World.Status` needs the conflict schema's `core` to
    be the header atom's *revision*, not the signature.**
    `status_core_rev_agrees`: with `core` = revision (through an injective
    digest), one admitted review at the revision read gives the decision
    exactly when EKOS's review holds, and `needsReview` exactly when EKOS
    reopened. EKOS spells the reopened state `open` with `previous_review`;
    World spells it `needsReview` with the old review kept in the log.
  - **`core_sig_diverges`**: with `core` = the signature, a history A → B → A
    makes World.Status report the old decision (the review sits at the
    current core A), while the pin says `moved` and EKOS is open. The revision
    is the right core because it never comes back; the signature can.
- **Examples** (`decide`): an unchanged signature keeps the review in both the
  pin and EKOS; A → B → A leaves both reopened.

### 3. The manifest theorem

`not_current_after_unemit`: `e ∉ emitted → e ∉ (M.compile emitted).current`,
one line over `mem_current_compile`. The example compiles a two-entry manifest
that stops emitting `orders`: the current set is `[customers]` and both
entries are still in the document.

### What I could not do

- **No mapping into minidregg's own records** (`DocumentRecord`,
  `AtomRecord`, `TransclusionRecord`, `LinkRecord`). The shapes are Lean data
  with the same parts.
- **Revisions are `Nat` counters.** Their freshness, a write takes a revision
  larger than any before, is built in here. minidregg's `OperationId`
  freshness is the same property, but no theorem connects them yet.
- **Not checked against what the deployed client can express**, because W17's
  memo was not there yet.

### Follow-ups

1. Read `notes/W17-slice1.md` when it lands, and adjust any shape the client
   could not express.
2. Set the conflict schema's `core` to the header revision in any concrete
   registry that W17 or the scoreboard uses, per `status_core_rev_agrees`.
3. Map `World.Shapes` into minidregg records in `World.Minidregg`, with the
   atom-pin theorems restated against `TranscludeRequest.pins`.

### Every new theorem statement, quoted from the source


#### `World/Shapes.lean`

```lean
theorem statements_importSource (h : SourceHeader C) (stmts : List (Statement C)) (r : Nat) :
    (importSource atomOf h stmts r).statements = stmts

theorem importSource_wellKeyed (h : SourceHeader C) (stmts : List (Statement C)) (r : Nat) :
    (importSource atomOf h stmts r).WellKeyed atomOf

theorem importSource_statements (D : SourceDoc C A) (r : Nat) (hk : D.WellKeyed atomOf)
    (hr : ∀ a ∈ D.atoms, a.rev = r) : importSource atomOf D.header D.statements r = D

theorem atomPins_importSource (h : SourceHeader C) (stmts : List (Statement C)) (r : Nat)
    (x : A × Nat) :
    x ∈ (importSource atomOf h stmts r).atomPins ↔ ∃ s ∈ stmts, x = (atomOf s.key, r)

theorem reimport_unchanged (D : SourceDoc C A) (r : Nat) (hk : D.WellKeyed atomOf)
    (hnd : (D.atoms.map (·.key)).Nodup) : reimport atomOf D D.statements r = D

theorem reimport_rev_iff (D : SourceDoc C A) (r : Nat)
    (hfresh : ∀ a ∈ D.atoms, a.rev < r) (s : Statement C) (a : TextAtom C A)
    (ha : D.atoms.find? (fun b => b.key == s.key) = some a) :
    (match D.atoms.find? (fun b => b.key == s.key) with
    | some a => if a.bytes = s.bytes then a else ⟨atomOf s.key, s.key, r, s.bytes⟩
    | none => ⟨atomOf s.key, s.key, r, s.bytes⟩ : TextAtom C A).rev = a.rev ↔
    a.bytes = s.bytes

theorem current_ofCurrent (es : List (List C.KeyPart × C.ClaimId)) :
    (Manifest.ofCurrent es).current = es

theorem mem_current (M : Manifest C) (e : List C.KeyPart × C.ClaimId) :
    e ∈ M.current ↔ ∃ l ∈ M.links, l.live = true ∧ (l.key, l.cell) = e

theorem unlinkIfGone_spec (emitted : List (List C.KeyPart × C.ClaimId)) (l : ManifestLink C) :
    (Manifest.unlinkIfGone emitted l).key = l.key ∧ (Manifest.unlinkIfGone emitted l).cell = l.cell ∧
    ((Manifest.unlinkIfGone emitted l).live = true ↔
    l.live = true ∧ (l.key, l.cell) ∈ emitted)

theorem mem_current_compile (M : Manifest C) (emitted : List (List C.KeyPart × C.ClaimId))
    (e : List C.KeyPart × C.ClaimId) :
    e ∈ (M.compile emitted).current ↔ e ∈ emitted

theorem not_current_after_unemit (M : Manifest C) (emitted : List (List C.KeyPart × C.ClaimId))
    (e : List C.KeyPart × C.ClaimId) (h : e ∉ emitted) : e ∉ (M.compile emitted).current

theorem history_kept (M : Manifest C) (emitted : List (List C.KeyPart × C.ClaimId))
    (l : ManifestLink C) (hl : l ∈ M.links) :
    ∃ l' ∈ (M.compile emitted).links, l'.key = l.key ∧ l'.cell = l.cell

theorem decode_encodeConflict (k : Conflict C) : decodeConflict (encodeConflict sigOf k) = k

theorem encodeConflict_consistent (k : Conflict C) : (encodeConflict sigOf k).Consistent sigOf

theorem encode_decodeConflict (D : ConflictDoc C) (h : D.Consistent sigOf) :
    encodeConflict sigOf (decodeConflict D) = D

theorem atomPins_encodeConflict (k : Conflict C) (x : C.SourceId × C.AtomRev) :
    x ∈ (encodeConflict sigOf k).atomPins ↔ ∃ m ∈ k.members, x ∈ m.pin.atoms.map (m.pin.source, ·)

theorem toEntry_toContainer (e : ReviewEntry C) : e.toContainer.toEntry = some e

theorem decode_encodeReview (reviewed : C.ClaimId) (es : List (ReviewEntry C)) :
    decodeReview (encodeReview reviewed es) = some es

theorem encode_decodeReview (D : ReviewDoc C) (es : List (ReviewEntry C))
    (h : decodeReview D = some es) : encodeReview D.reviewed es = D

theorem append_prefix (D : ReviewDoc C) (e : ReviewEntry C) :
    D.decisions <+: (D.append e).decisions

theorem atomPins_encodeReview (reviewed : C.ClaimId) (es : List (ReviewEntry C))
    (x : C.SourceId × C.AtomRev) :
    x ∈ (encodeReview reviewed es).atomPins ↔ ∃ e ∈ es, x = (e.headerDoc, e.headerRead)

theorem not_replayed_by_compiler (run : CompileRunDoc C) (atts : List (ReplayAttestation C))
    (h : ∀ a ∈ atts, a.verifier = run.compiler) : ¬ replayedDeterministic run atts

theorem not_replayed_if_outputs_differ (run : CompileRunDoc C) (atts : List (ReplayAttestation C))
    (h : ∀ a ∈ atts, a.outputs ≠ run.outputs) : ¬ replayedDeterministic run atts

theorem mem_atomPins_compileRun (D : CompileRunDoc C) (x : C.SourceId × C.AtomRev × Nat) :
    x ∈ D.atomPins ↔ ∃ i ∈ D.inputs, ∃ a ∈ i.pin.atoms, x = (i.pin.source, a, i.height)

```

#### `World/CarryForward.lean`

```lean
theorem compileHeader_rev_eq_iff (h : HeaderAtom C) (s : C.Digest) :
    (compileHeader h s).rev = h.rev ↔ s = h.sig

theorem rev_le_compileAll (h : HeaderAtom C) (hist : List C.Digest) :
    h.rev ≤ (compileAll h hist).rev

theorem compileAll_rev_eq_iff (h : HeaderAtom C) (hist : List C.Digest) :
    (compileAll h hist).rev = h.rev ↔ ∀ s ∈ hist, s = h.sig

theorem compileAll_sig (h : HeaderAtom C) (hist : List C.Digest) :
    (compileAll h hist).sig = hist.getLastD h.sig

theorem pin_sameBytes_iff (h : HeaderAtom C) (hist : List C.Digest) :
    renderHeaderPin h.rev (compileAll h hist) = .sameBytes ↔ ∀ s ∈ hist, s = h.sig

theorem pin_moved_iff (h : HeaderAtom C) (hist : List C.Digest) :
    renderHeaderPin h.rev (compileAll h hist) = .moved ↔ ∃ s ∈ hist, s ≠ h.sig

theorem renderHeaderPin_eq_viewEvidence (pinOf : Nat → C.AtomRev)
    (hinj : Function.Injective pinOf) (doc : C.SourceId) (m : EvidenceMeta C)
    (read : Nat) (h : HeaderAtom C) :
    viewEvidence (fun _ => true) (fun _ a => decide (a = pinOf h.rev))
    ⟨m, ⟨doc, [pinOf read]⟩⟩ = renderHeaderPin read h

theorem ekosAll_open (r : Option C.Digest) (g : C.Digest) (hist : List C.Digest) :
    (ekosAll ⟨.isOpen, r, g⟩ hist).status = .isOpen

theorem ekos_holds_iff (cur : EConflict C) (s : Status) (hist : List C.Digest) :
    (ekosAll (ekosReview cur s) hist).status = .decided s ↔ ∀ x ∈ hist, x = cur.sig

theorem pin_agrees_with_ekos (h : HeaderAtom C) (cur : EConflict C) (hsig : cur.sig = h.sig)
    (s : Status) (hist : List C.Digest) :
    renderHeaderPin h.rev (compileAll h hist) = .sameBytes ↔
    (ekosAll (ekosReview cur s) hist).status = .decided s

theorem statusAt_single (L : List (Receipt C P)) (k : ClaimKey C) (dg₀ : C.Digest)
    (s₀ : Status) (h : admittedReviews R reg d L k = [(dg₀, s₀)]) (dg : C.Digest) :
    statusAt R reg d L k dg = if dg = dg₀ then s₀ else .needsReview

theorem status_core_rev_agrees (revDigest : Nat → C.Digest) (hinj : Function.Injective revDigest)
    (L : List (Receipt C P)) (k : ClaimKey C) (h : HeaderAtom C) (cur : EConflict C)
    (hsig : cur.sig = h.sig) (s₀ : Status)
    (hrev : admittedReviews R reg d L k = [(revDigest h.rev, s₀)]) (hist : List C.Digest) :
    statusAt R reg d L k (revDigest (compileAll h hist).rev) =
    if (ekosAll (ekosReview cur s₀) hist).status = .decided s₀ then s₀ else .needsReview

theorem core_sig_diverges (L : List (Receipt C P)) (k : ClaimKey C) (a b : C.Digest)
    (hab : a ≠ b) (r : Nat) (s₀ : Status)
    (hrev : admittedReviews R reg d L k = [(a, s₀)]) (cur : EConflict C) (hsig : cur.sig = a) :
    statusAt R reg d L k (compileAll ⟨r, a⟩ [b, a]).sig = s₀ ∧
    renderHeaderPin r (compileAll ⟨r, a⟩ [b, a]) = .moved ∧
    (ekosAll (ekosReview cur s₀) [b, a]).status = .isOpen

```

### `#print axioms`, verbatim

```
'World.statements_importSource' depends on axioms: [propext, Quot.sound]
'World.importSource_wellKeyed' depends on axioms: [propext, Quot.sound]
'World.importSource_statements' depends on axioms: [propext, Quot.sound]
'World.atomPins_importSource' depends on axioms: [propext, Quot.sound]
'World.reimport_unchanged' depends on axioms: [propext, Quot.sound]
'World.reimport_rev_iff' depends on axioms: [propext, Quot.sound]
'World.current_ofCurrent' depends on axioms: [propext]
'World.mem_current' depends on axioms: [propext, Quot.sound]
'World.unlinkIfGone_spec' depends on axioms: [propext]
'World.mem_current_compile' depends on axioms: [propext, Quot.sound]
'World.not_current_after_unemit' depends on axioms: [propext, Quot.sound]
'World.history_kept' depends on axioms: [propext, Quot.sound]
'World.decode_encodeConflict' does not depend on any axioms
'World.encodeConflict_consistent' does not depend on any axioms
'World.encode_decodeConflict' depends on axioms: [propext]
'World.atomPins_encodeConflict' depends on axioms: [propext, Quot.sound]
'World.toEntry_toContainer' depends on axioms: [propext]
'World.decode_encodeReview' depends on axioms: [propext, Quot.sound]
'World.encode_decodeReview' depends on axioms: [propext, Quot.sound]
'World.append_prefix' does not depend on any axioms
'World.atomPins_encodeReview' depends on axioms: [propext, Quot.sound]
'World.not_replayed_by_compiler' does not depend on any axioms
'World.not_replayed_if_outputs_differ' does not depend on any axioms
'World.mem_atomPins_compileRun' depends on axioms: [propext, Quot.sound]
'World.compileHeader_rev_eq_iff' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.rev_le_compileAll' depends on axioms: [propext, Quot.sound]
'World.compileAll_rev_eq_iff' depends on axioms: [propext, Quot.sound]
'World.compileAll_sig' depends on axioms: [propext]
'World.pin_sameBytes_iff' depends on axioms: [propext, Quot.sound]
'World.pin_moved_iff' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.renderHeaderPin_eq_viewEvidence' depends on axioms: [propext]
'World.ekosAll_open' does not depend on any axioms
'World.ekos_holds_iff' depends on axioms: [propext, Quot.sound]
'World.pin_agrees_with_ekos' depends on axioms: [propext, Quot.sound]
'World.statusAt_single' depends on axioms: [propext]
'World.status_core_rev_agrees' depends on axioms: [propext, Quot.sound]
'World.core_sig_diverges' depends on axioms: [propext, Classical.choice, Quot.sound]
```

---

## 2026-10-19, fifth quest: transaction order (review R1, finding M9)

`World/TxOrder.lean` is additive: no existing definition or theorem changed
signature. `TxMonotone L` (strictly increasing `tx`, as `List.Pairwise`) is
decidable.
- `txMonotone_write`: `write` keeps it when the new receipt is numbered after
  the last one.
- `state_eq_replay_takeWhile`: under `TxMonotone`, `state L t` is the replay
  of the longest prefix (`takeWhile`) numbered `t` or less, so the state is
  prefix-closed.
- `diff_eq_segment`: `diff a b` is exactly the ids of the segment `(a, b]`.
- `segment_contiguous`: the log splits as prefix up to `a`, then the segment,
  then the rest.

Examples (`decide`) in `World/Examples.lean`:
- the traversal log is monotone, and an out-of-order log is not;
- the state at 3 is the replay of the first three receipts;
- `diff 2 4` is the ids of receipts 3 and 4.

The build is green (2978 jobs).

```lean
def TxMonotone (L : List (Receipt C P)) : Prop := L.Pairwise fun r s => r.tx < s.tx

theorem tx_le_last (L : List (Receipt C P)) (h : TxMonotone L) (last : Receipt C P)
    (hl : L.getLast? = some last) (r : Receipt C P) (hr : r ∈ L) : r.tx ≤ last.tx

theorem txMonotone_write [∀ s, DecidableEq (P s)] (L : List (Receipt C P)) (r : Receipt C P)
    (h : TxMonotone L) (hr : ∀ last, L.getLast? = some last → last.tx < r.tx) :
    TxMonotone (write d L r)

theorem filter_eq_takeWhile (L : List (Receipt C P)) (h : TxMonotone L) (t : Nat) :
    L.filter (fun r => decide (r.tx ≤ t)) = L.takeWhile (fun r => decide (r.tx ≤ t))

theorem state_eq_replay_takeWhile (L : List (Receipt C P)) (h : TxMonotone L) (t : Nat) :
    state d L t = replay d (L.takeWhile fun r => decide (r.tx ≤ t))

theorem takeWhile_prefix_log (L : List (Receipt C P)) (t : Nat) :
    (L.takeWhile fun r => decide (r.tx ≤ t)) <+: L

def segment (L : List (Receipt C P)) (a b : Nat) : List (Receipt C P) :=
    (L.dropWhile fun r => decide (r.tx ≤ a)).takeWhile fun r => decide (r.tx ≤ b)

theorem segment_contiguous (L : List (Receipt C P)) (a b : Nat) :
    L = (L.takeWhile fun r => decide (r.tx ≤ a)) ++ segment L a b ++
    ((L.dropWhile fun r => decide (r.tx ≤ a)).dropWhile fun r => decide (r.tx ≤ b))

theorem filter_window_eq_segment (L : List (Receipt C P)) (h : TxMonotone L) (a b : Nat) :
    L.filter (fun r => decide (a < r.tx ∧ r.tx ≤ b)) = segment L a b

theorem diff_eq_segment (L : List (Receipt C P)) (h : TxMonotone L) (a b : Nat) :
    diff d L a b = (segment L a b).map fun r => r.op.id d

```

`#print axioms`, verbatim:

```
'World.tx_le_last' depends on axioms: [propext, Quot.sound]
'World.txMonotone_write' depends on axioms: [propext, Quot.sound]
'World.filter_eq_takeWhile' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.state_eq_replay_takeWhile' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.takeWhile_prefix_log' depends on axioms: [propext]
'World.segment_contiguous' depends on axioms: [propext]
'World.filter_window_eq_segment' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.diff_eq_segment' depends on axioms: [propext, Classical.choice, Quot.sound]
```

---

## 2026-10-19, sixth quest: the clash relation and EKOS's label rule (lane B, F1)

Lane B's proposal (`notes/B-check.md` F1) adds `clash` as a field of `Schema`
and rewrites `disagreeOn`. That is sound, but it would change two existing
definitions, which check/ pins. So `World/Clash.lean` does the same thing
additively:
- a **clash table** `Clash C := SchemaId → (sources × value) → (sources ×
  value) → Bool`, where the sources are the claim's `ClaimKey.sources`, as
  the coordinator asked;
- `detectBy κ`, which is `detect` with `κ` in place of `≠`.

What is proved:
- **`detectBy_differ`**: the default table `Clash.differ` (values differ)
  gives `detect` **exactly**, so every existing theorem is its default
  instance. `World/Conflicts.lean` is untouched, including
  `detectList_congr`.
- `mem_detectBy`, `coverageBy`, `soundnessBy`, `detectListBy_congr`,
  `detectListBy_perm` and `detectBy_mono` hold for any table.
- **Symmetry is not needed**, contrary to B's note. `detectBy` tries every
  ordered pair, so a relation that holds one way round is found.
- **`labelClash`** (EKOS `label_mismatches`, `conflicts.rs:414-416`): for the
  label schema, clash iff the source sets are disjoint and the word sets are
  disjoint. The word sets come from a supplied `wordsOf`, standing in for
  `label_words`. Every other schema keeps `≠`. `mem_detectBy_label` states
  exactly what it detects.

Lane B's three probes, run by `decide` in `World.ClashExample`, now come out
as EKOS:
- `asset account` / `asset`: no conflict, though `detect` with `≠` flags it;
- a shared source: no conflict;
- two sourceless labels: a conflict.

`asset` / `liability` from two sources is a conflict.

The build is green (2979 jobs). Commit: `c5b013e`.

```lean
theorem mem_disagreeOnBy (c₁ c₂ : Claim C P) (a : C.Digest) :
    a ∈ disagreeOnBy reg κ c₁ c₂ ↔
    ∃ v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧
    κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, v₂) = true

theorem mem_detectBy (cs : Finset (Claim C P)) (k : ConflictKey C) :
    k ∈ detectBy reg κ cs ↔
    ∃ c₁ ∈ cs, ∃ c₂ ∈ cs, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
    ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧
    κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, v₂) = true ∧
    k = (c₁.key.schema, c₁.key.subject, a)

theorem coverageBy (cs : Finset (Claim C P)) (c₁ c₂ : Claim C P)
    (h₁ : c₁ ∈ cs) (h₂ : c₂ ∈ cs) (hne : c₁ ≠ c₂) (hsame : sameSubject c₁ c₂)
    (a v₁ v₂ : C.Digest) (hv₁ : (a, v₁) ∈ c₁.stated reg) (hv₂ : (a, v₂) ∈ c₂.stated reg)
    (hk : κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, v₂) = true) :
    (c₁.key.schema, c₁.key.subject, a) ∈ detectBy reg κ cs

theorem soundnessBy (cs : Finset (Claim C P)) (k : ConflictKey C) (hk : k ∈ detectBy reg κ cs) :
    ∃ c₁ ∈ cs, ∃ c₂ ∈ cs, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
    ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧
    κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, v₂) = true ∧
    k = (c₁.key.schema, c₁.key.subject, a)

theorem detectListBy_congr (l₁ l₂ : List (Claim C P)) (h : ∀ c, c ∈ l₁ ↔ c ∈ l₂) :
    detectListBy reg κ l₁ = detectListBy reg κ l₂

theorem detectListBy_perm (l₁ l₂ : List (Claim C P)) (h : l₁.Perm l₂) :
    detectListBy reg κ l₁ = detectListBy reg κ l₂

theorem detectBy_mono (cs cs' : Finset (Claim C P)) (h : cs ⊆ cs') :
    detectBy reg κ cs ⊆ detectBy reg κ cs'

theorem disagreeOnBy_differ (c₁ c₂ : Claim C P) :
    disagreeOnBy reg Clash.differ c₁ c₂ = disagreeOn reg c₁ c₂

theorem detectBy_differ (cs : Finset (Claim C P)) : detectBy reg Clash.differ cs = detect reg cs

theorem disjointB_iff {α : Type} [DecidableEq α] (l₁ l₂ : List α) :
    disjointB l₁ l₂ = true ↔ ∀ a ∈ l₁, a ∉ l₂

theorem mem_detectBy_label (label : C.SchemaId) (wordsOf : C.Digest → List C.KeyPart)
    (cs : Finset (Claim C P)) (subj : List C.KeyPart) (a : C.Digest) :
    (label, subj, a) ∈ detectBy reg (labelClash label wordsOf) cs ↔
    ∃ c₁ ∈ cs, ∃ c₂ ∈ cs, c₁ ≠ c₂ ∧ c₁.key.schema = label ∧ c₂.key.schema = label ∧
    c₁.key.subject = subj ∧ c₂.key.subject = subj ∧
    ∃ v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧
    (∀ s ∈ c₁.key.sources, s ∉ c₂.key.sources) ∧
    (∀ w ∈ wordsOf v₁, w ∉ wordsOf v₂)

```

`#print axioms`, verbatim:

```
'World.mem_disagreeOnBy' depends on axioms: [propext, Quot.sound]
'World.mem_detectBy' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.coverageBy' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.soundnessBy' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.detectListBy_congr' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.detectListBy_perm' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.detectBy_mono' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.disagreeOnBy_differ' depends on axioms: [propext, Quot.sound]
'World.detectBy_differ' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.disjointB_iff' depends on axioms: [propext, Quot.sound]
'World.mem_detectBy_label' depends on axioms: [propext, Classical.choice, Quot.sound]
```

---

## 2026-10-19, seventh quest: `WorldCore`, the Mathlib-free library (no twins)

`world/` now has two Lake libraries.
- **`WorldCore`** (root `WorldCore.lean`) imports only modules in its own set.
  `world/check-core-imports.sh` enforces this. It was tested: it fails on a
  planted `import Mathlib.Data.Finset.Basic`.
- **`World`** imports `WorldCore` and everything else.

Build times:
- a clean `nice -n 10 lake build WorldCore` is **16 jobs, 6 s**, and the log
  names no Mathlib module (`var/w1/build-clean-worldcore.log`);
- the full build after it is 2984 jobs, 15 s (`var/w1/build-clean-world-q7.log`).

No warnings, no `sorry`. Commit `3059c8f`.

**Why `detectList` and `detectListBy` cannot move to Core.** Both return a
`Finset`, which is a Mathlib type. Moving them without a signature change is
impossible. So they stay in `World` (module `World.Conflicts` / `World.Clash`),
**unchanged in name, signature and body**. Core gains the list versions:
- `World.detectL` and `World.detectLBy`, in namespace `World` (check/'s copies
  are `Check.detectL`/`Check.detectLBy`, so there is no clash);
- `World.detectL_toFinset : (detectL reg l).toFinset = detectList reg l`;
- `World.detectLBy_toFinset : (detectLBy reg κ l).toFinset = detectListBy reg κ l`.

check/ can therefore `import WorldCore`, call `World.detectL`/`detectLBy`,
and delete both its copies and its `CheckProofs` equality proofs. The
equalities now live in `World`.

**Where every name check/ pins lives now:**

| Name | Module | Library |
|---|---|---|
| `detectList` | `World.Conflicts` (unchanged) | World |
| `detectListBy` | `World.Clash` (unchanged) | World |
| `labelClash` | `World.ClashCore` (moved from `World.Clash`) | WorldCore |
| `admissible`, `AdmLog`, `rstep`, `rankMap`, `rankOf` | `World.Admission` (unchanged; it now imports `World.Ranked` instead of `World.WellFormed`) | WorldCore |
| `visible` | `World.Visible` (unchanged) | WorldCore |
| `status`, `reviewOf` | `World.Status` (unchanged) | WorldCore |
| `detectL`, `detectLBy` (new, the list versions) | `World.ConflictsCore`, `World.ClashCore` | WorldCore |

**Everything that moved module (names, signatures and proofs unchanged):**
- `World.WellFormed` → **`World.Ranked`**:
  - `Claim.PinsNonempty`, `PremiseOf`, `Ranked`, `Ranked.wellFounded`,
    `Ranked.not_self`;
  - `any_congr_mem`, `all_congr_mem`;
  - `denied_stable`, `allowed_stable`, `visible_stable`, `visibleR`,
    `visible_eq_visibleR`, `visibleR_rank_irrelevant`, `visible_iff_sourcePins`;
  - `asReview_pins`, `latest_append_put`, `reviewSurvives_put_acyclic`.

  `World.WellFormed` keeps the source-order rule (`ClaimKey.Canonical`,
  `normalize` and its theorems, `Claim.WellFormed`, `LogWellFormed`,
  `latest_wellFormed`) and imports `World.Ranked`.
- `World.Conflicts` → **`World.ConflictsCore`**: `ConflictKey`,
  `Claim.stated`, `disagreeOn`, `sameSubject` and its `Decidable` instance,
  `mem_disagreeOn`.
- `World.Clash` → **`World.ClashCore`**: `Clash`, `Clash.differ`,
  `disagreeOnBy`, `mem_disagreeOnBy`, `disagreeOnBy_differ`, `disjointB`,
  `disjointB_iff`, `labelClash`.

**Proof edits forced by leaving Mathlib** (statements untouched):
- Mathlib lemma names were replaced by core ones (`Nat.le_refl`,
  `Nat.le_antisymm`, `Nat.lt_of_le_of_lt`; `Nat.lt_wfRel.wf` for
  `wellFounded_lt`).
- Mathlib tactics `set`, `conv_rhs` and `by_contra` were replaced by plain
  terms, `conv => rhs` and `Classical.byContradiction`.
- `List.reverseRecOn` (Mathlib) was replaced by a new core lemma
  `rankInv_of_admLog_rev` (induction on the reversed log).
- Five simp-driven proofs were made explicit. Each still proves the same
  statement.

New statements:

```lean
def detectL (l : List (Claim C P)) : List (ConflictKey C)
def detectLBy (l : List (Claim C P)) : List (ConflictKey C)

theorem mem_detectL (l : List (Claim C P)) (k : ConflictKey C) :
    k ∈ detectL reg l ↔
      ∃ c₁ ∈ l, ∃ c₂ ∈ l, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
        ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧ v₁ ≠ v₂ ∧
          k = (c₁.key.schema, c₁.key.subject, a)

theorem mem_detectLBy (l : List (Claim C P)) (k : ConflictKey C) :
    k ∈ detectLBy reg κ l ↔
      ∃ c₁ ∈ l, ∃ c₂ ∈ l, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
        ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧
          κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, v₂) = true ∧
          k = (c₁.key.schema, c₁.key.subject, a)

theorem detectL_toFinset (l : List (Claim C P)) : (detectL reg l).toFinset = detectList reg l

theorem detectLBy_toFinset (l : List (Claim C P)) :
    (detectLBy reg κ l).toFinset = detectListBy reg κ l

theorem rankInv_of_admLog_rev : ∀ (R : List (Receipt C P)), AdmLog d R.reverse → RankInv d R.reverse
```

`#print axioms` (new theorems, and a sample of the moved ones), verbatim:

```
'World.mem_detectL' depends on axioms: [propext, Quot.sound]
'World.mem_detectLBy' depends on axioms: [propext, Quot.sound]
'World.detectL_toFinset' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.detectLBy_toFinset' depends on axioms: [propext, Classical.choice, Quot.sound]
'World.rankInv_of_admLog_rev' depends on axioms: [propext, Quot.sound]
'World.rankInv_of_admLog' depends on axioms: [propext, Quot.sound]
'World.ranked_of_admLog' depends on axioms: [propext, Quot.sound]
'World.visible_stable' depends on axioms: [propext, Quot.sound]
'World.reviewSurvives_put_acyclic' depends on axioms: [propext, Quot.sound]
'World.mem_disagreeOn' depends on axioms: [propext, Quot.sound]
'World.disagreeOnBy_differ' depends on axioms: [propext, Quot.sound]
```
