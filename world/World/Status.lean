/-
# World.Status — status as a function of the reviews in the log

A claim has no status field. Its status is read off the log:

1. Collect the **admitted reviews** of the claim: put receipts of review
   claims that target this claim's id, whose decision the claim's schema lets
   the receipt's author kind make (`Schema.mayDecide`).
2. If any admitted review is pinned at the claim's **current** core digest,
   the status is the decision of the last such review in the log.
3. Otherwise, if some admitted review exists (pinned at another core), the
   status is `needsReview`.
4. Otherwise, it is the schema's initial status.

A review is never withdrawn by retracting it: retract receipts are ignored
here, and a change of mind is a new review. This is a choice of this model;
EKOS has no review retraction either.

The status of a claim depends only on its key (which fixes its id and its
schema) and its core digest. That is the formal content of "a review lasts
while the core does": EKOS's hand-written `carry_forward` functions become this
definition.

Every name here is new to VerEKOS.
-/
import World.Log

namespace World

set_option autoImplicit false

variable [C : Carriers] {P : C.SchemaId → Type}

/-- The review schema: which schema id review claims have, and how to read
the decision out of a review payload. A review claim's single pin targets the
reviewed claim at the core digest the reviewer saw. -/
structure ReviewSchema [C : Carriers] (P : C.SchemaId → Type) where
  sid : C.SchemaId
  decision : P sid → Status

variable (R : ReviewSchema P) (reg : Registry P) [d : ClaimIdDerivation]

/-- If `c` is a review claim, return (the reviewed id, the core digest the
review is pinned at, the decision). A claim of the review schema whose pins
are not exactly one claim pin at a core digest is not a review. -/
def asReview (c : Claim P) : Option (C.ClaimId × C.Digest × Status) :=
  if h : c.key.schema = R.sid then
    match c.pins with
    | [⟨.claim i, .core dg, _⟩] => some (i, dg, R.decision (h ▸ c.payload))
    | _ => none
  else none

/-- If receipt `r` is an admitted review of the claim with key `k`, return
(the core digest it is pinned at, its decision). -/
def reviewOf (k : ClaimKey) (r : Receipt P) : Option (C.Digest × Status) :=
  match r.op with
  | .put c' =>
    match asReview R c' with
    | some (i, dg, s) =>
      if i = ClaimIdDerivation.claimId k ∧ (reg k.schema).mayDecide r.author.1 s = true
      then some (dg, s) else none
    | none => none
  | .retract _ => none

/-- All admitted reviews of the claim with key `k`, in log order. -/
def admittedReviews (L : List (Receipt P)) (k : ClaimKey) : List (C.Digest × Status) :=
  L.filterMap (reviewOf R reg k)

/-- Status of the claim with key `k` and core digest `dg`, as described in the
module docstring. -/
def statusAt (L : List (Receipt P)) (k : ClaimKey) (dg : C.Digest) : Status :=
  match ((admittedReviews R reg L k).filter (fun x => decide (x.1 = dg))).getLast? with
  | some (_, s) => s
  | none => if (admittedReviews R reg L k).isEmpty then (reg k.schema).initial
            else .needsReview

/-- The status of claim `c` in log `L`. -/
def status (L : List (Receipt P)) (c : Claim P) : Status :=
  statusAt R reg L c.key (c.core reg)

/-! ## Lemmas -/

/-- Appending receipts none of which is an admitted review of `k` leaves the
status of `k` (at any core) unchanged. -/
theorem statusAt_append_of_no_review (L L₂ : List (Receipt P)) (k : ClaimKey)
    (dg : C.Digest) (h : ∀ r ∈ L₂, reviewOf R reg k r = none) :
    statusAt R reg (L ++ L₂) k dg = statusAt R reg L k dg := by
  have : L₂.filterMap (reviewOf R reg k) = [] := by
    rw [List.filterMap_eq_nil_iff]; exact h
  simp [statusAt, admittedReviews, List.filterMap_append, this]

/-- Unfolding `reviewOf`: what it means for a receipt to be an admitted review. -/
theorem reviewOf_eq_some (k : ClaimKey) (r : Receipt P) (dg : C.Digest) (s : Status) :
    reviewOf R reg k r = some (dg, s) ↔
      ∃ c', r.op = .put c' ∧ asReview R c' = some (ClaimIdDerivation.claimId k, dg, s) ∧
        (reg k.schema).mayDecide r.author.1 s = true := by
  unfold reviewOf
  cases hop : r.op with
  | retract j => simp
  | put c' =>
    simp only [Op.put.injEq, exists_eq_left']
    cases ha : asReview R c' with
    | none => simp
    | some v =>
      obtain ⟨i, dg', s'⟩ := v
      dsimp only
      by_cases hc : i = ClaimIdDerivation.claimId k ∧ (reg k.schema).mayDecide r.author.1 s' = true
      · rw [if_pos hc]
        constructor
        · intro h
          simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact ⟨by rw [hc.1], hc.2⟩
        · rintro ⟨h1, _⟩
          simp only [Option.some.injEq, Prod.mk.injEq] at h1 ⊢
          exact ⟨h1.2.1, h1.2.2⟩
      · rw [if_neg hc]
        simp only [reduceCtorEq, false_iff]
        rintro ⟨h1, h4⟩
        simp only [Option.some.injEq, Prod.mk.injEq] at h1
        obtain ⟨h1, _, rfl⟩ := h1
        exact hc ⟨h1, h4⟩

/-! ## The status theorems -/

/-- **CompilerCannotDecide.** In plain words: if a claim's schema never lets
the compiler make any decision, then nothing the compiler writes — puts,
retracts, even review claims — changes that claim's status.

Formally: for a claim `c` whose schema has `mayDecide .compiler s = false` for
every `s`, appending any list of compiler-authored receipts leaves
`status L c` unchanged.

(The exploration's sketch quantified over every claim. That is false in EKOS's
own model: an exact identity merge is a `SameAs` confirmed by the compiler, so
the compiler is admitted for that schema. The hypothesis on the schema is the
honest form.) -/
theorem compilerCannotDecide (L L₂ : List (Receipt P)) (c : Claim P)
    (hschema : ∀ s, (reg c.key.schema).mayDecide .compiler s = false)
    (hcomp : ∀ r ∈ L₂, r.author.1 = .compiler) :
    status R reg (L ++ L₂) c = status R reg L c := by
  apply statusAt_append_of_no_review
  intro r hr
  cases h : reviewOf R reg c.key r with
  | none => rfl
  | some v =>
    obtain ⟨dg, s⟩ := v
    obtain ⟨_, _, _, hmay⟩ := (reviewOf_eq_some R reg c.key r dg s).mp h
    rw [hcomp r hr, hschema s] at hmay
    exact absurd hmay (by simp)

/-- **Every decision has an author.** In plain words: if a claim's status is
neither its schema's initial status nor `needsReview`, then the log contains a
put of a review of this claim, pinned at its current core, with exactly that
decision, by a principal whose kind the schema admits for that decision. -/
theorem decision_has_author (L : List (Receipt P)) (c : Claim P) (s : Status)
    (hs : status R reg L c = s) (hinit : s ≠ (reg c.key.schema).initial)
    (hnr : s ≠ .needsReview) :
    ∃ r ∈ L, ∃ c', r.op = .put c' ∧ asReview R c' = some (c.id, c.core reg, s) ∧
      (reg c.key.schema).mayDecide r.author.1 s = true := by
  unfold status statusAt at hs
  cases hlast : ((admittedReviews R reg L c.key).filter
      (fun x => decide (x.1 = c.core reg))).getLast? with
  | some x =>
    rw [hlast] at hs
    obtain ⟨dg, s'⟩ := x
    dsimp only at hs
    subst hs
    have hmem := List.mem_of_getLast? hlast
    rw [List.mem_filter, admittedReviews, List.mem_filterMap] at hmem
    obtain ⟨⟨r, hr, hrev⟩, hdg⟩ := hmem
    simp only [decide_eq_true_eq] at hdg
    subst hdg
    obtain ⟨c', hop, has, hmay⟩ := (reviewOf_eq_some R reg c.key r _ _).mp hrev
    exact ⟨r, hr, c', hop, has, hmay⟩
  | none =>
    rw [hlast] at hs
    dsimp only at hs
    split at hs
    · exact absurd hs.symm hinit
    · exact absurd hs.symm hnr

/-- **ReviewSurvives.** In plain words: a review lasts while the core does.
If `c'` is a later version of `c` (same id) with the same core digest, then
after any further receipts that are not admitted reviews of it — for example
the compiler putting `c'` again — the status of `c'` is the status `c` had.

The premise that ids are injective in keys is used to conclude that `c` and
`c'` have the same key, hence the same schema and the same review rules. -/
theorem reviewSurvives (hinj : Function.Injective ClaimIdDerivation.claimId)
    (L L₂ : List (Receipt P)) (c c' : Claim P)
    (hid : c.id = c'.id) (hcore : c.core reg = c'.core reg)
    (hrest : ∀ r ∈ L₂, reviewOf R reg c'.key r = none) :
    status R reg (L ++ L₂) c' = status R reg L c := by
  have hk : c.key = c'.key := hinj hid
  unfold status
  rw [statusAt_append_of_no_review R reg L L₂ c'.key _ hrest, ← hk, ← hcore]

/-- The exploration's form of `reviewSurvives`: putting a new version `c'`
with the same id and core, by anyone, keeps the status — provided `c'` is not
itself a review of itself (a claim pinned to its own id, which the pin
acyclicity law, not yet stated, would rule out). -/
theorem reviewSurvives_put (hinj : Function.Injective ClaimIdDerivation.claimId)
    (L : List (Receipt P)) (c c' : Claim P) (r : Receipt P)
    (hop : r.op = .put c') (hnotrev : asReview R c' = none)
    (hid : c.id = c'.id) (hcore : c.core reg = c'.core reg) :
    status R reg (L ++ [r]) c' = status R reg L c := by
  apply reviewSurvives R reg hinj L [r] c c' hid hcore
  intro r' hr'
  simp only [List.mem_singleton] at hr'
  subst hr'
  simp [reviewOf, hop, hnotrev]

/-- **NeedsReviewOnCoreChange.** In plain words: if a claim was reviewed (an
admitted review exists, at the core it had then) and the claim now has a
core at which no admitted review exists, its status is `needsReview`. The old
review is kept in the log; it just no longer decides. -/
theorem needsReviewOnCoreChange (hinj : Function.Injective ClaimIdDerivation.claimId)
    (L : List (Receipt P)) (c c' : Claim P) (hid : c.id = c'.id)
    (hold : ∃ r ∈ L, ∃ s, reviewOf R reg c.key r = some (c.core reg, s))
    (hnone : ∀ r ∈ L, ∀ s, reviewOf R reg c'.key r ≠ some (c'.core reg, s)) :
    status R reg L c' = .needsReview := by
  have hk : c.key = c'.key := hinj hid
  rw [hk] at hold
  obtain ⟨r₀, hr₀, s₀, hrev₀⟩ := hold
  unfold status statusAt
  have hfil : (admittedReviews R reg L c'.key).filter
      (fun x => decide (x.1 = c'.core reg)) = [] := by
    rw [List.filter_eq_nil_iff]
    intro x hx
    rw [admittedReviews, List.mem_filterMap] at hx
    obtain ⟨r, hr, hrev⟩ := hx
    obtain ⟨dg, s⟩ := x
    simp only [decide_eq_true_eq]
    rintro rfl
    exact hnone r hr s hrev
  have hne : (admittedReviews R reg L c'.key).isEmpty = false := by
    rw [List.isEmpty_eq_false_iff_exists_mem]
    exact ⟨_, List.mem_filterMap.mpr ⟨r₀, hr₀, hrev₀⟩⟩
  rw [hfil]
  simp [hne]

/-- **An admitted review takes effect.** Appending an admitted review of `c`
pinned at its current core sets the status to that review's decision. This
shows the hypotheses of the theorems above can be met and are not vacuous. -/
theorem reviewTakesEffect (L : List (Receipt P)) (c : Claim P) (r : Receipt P)
    (s : Status) (hrev : reviewOf R reg c.key r = some (c.core reg, s)) :
    status R reg (L ++ [r]) c = s := by
  unfold status statusAt admittedReviews
  rw [List.filterMap_append]
  simp [hrev, List.filter_append]

/-- Decided stays decided, per core digest: once an admitted review pinned at
digest `dg` exists, no later receipts make the status at `dg` the initial
status or `needsReview` by default — it is always the decision of the last
admitted review at `dg`. -/
theorem decided_stays_decided (L L₂ : List (Receipt P)) (k : ClaimKey)
    (dg : C.Digest) (s : Status) (r : Receipt P) (hr : r ∈ L)
    (hrev : reviewOf R reg k r = some (dg, s)) :
    ∃ s', statusAt R reg (L ++ L₂) k dg = s' ∧
      ∃ r' ∈ L ++ L₂, reviewOf R reg k r' = some (dg, s') := by
  unfold statusAt
  have hmem : (dg, s) ∈ (admittedReviews R reg (L ++ L₂) k).filter
      (fun x => decide (x.1 = dg)) := by
    rw [List.mem_filter, admittedReviews, List.mem_filterMap]
    exact ⟨⟨r, List.mem_append_left _ hr, hrev⟩, by simp⟩
  cases hlast : ((admittedReviews R reg (L ++ L₂) k).filter
      (fun x => decide (x.1 = dg))).getLast? with
  | none =>
    rw [List.getLast?_eq_none_iff] at hlast
    rw [hlast] at hmem
    simp at hmem
  | some x =>
    obtain ⟨dg', s'⟩ := x
    refine ⟨s', rfl, ?_⟩
    have hm := List.mem_of_getLast? hlast
    rw [List.mem_filter, admittedReviews, List.mem_filterMap] at hm
    obtain ⟨⟨r', hr', hrev'⟩, hdg⟩ := hm
    simp only [decide_eq_true_eq] at hdg
    subst hdg
    exact ⟨r', hr', hrev'⟩

end World
