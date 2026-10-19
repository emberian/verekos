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
