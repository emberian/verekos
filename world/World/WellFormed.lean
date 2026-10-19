/-
# World.WellFormed — the three rules the first build left out

In plain words:

1. **Pins are nonempty.** Every claim says where it came from.
2. **Pins have no cycles.** Following claim pins from a claim to its premises,
   and on to theirs, always stops. We state this with a **rank**: a number per
   claim that strictly drops from a claim to each of its premises. A rank
   exists exactly when the pin graph is well founded with finite depth, and
   the rank of a claim is a bound on how deep its pins go.
3. **Sources are sorted and duplicate-free.** Then two keys are equal exactly
   when they have the same schema, the same subject, and the same *set* of
   sources. `ClaimKey.normalize` puts any key into this form.

What the rules buy:
- With a rank, `visible` no longer depends on an arbitrary depth bound: every
  bound above a claim's rank gives the same answer (`visible_stable`), so
  `visibleR` (visibility at rank + 1) is *the* visibility.
- With a rank on the state after a put, the put claim cannot be a review of
  itself, so `reviewSurvives_put`'s extra hypothesis goes away
  (`reviewSurvives_put_acyclic`).
- With nonempty pins, a claim pinned only to sources is visible exactly when
  every source origin is allowed and none is denied (`visible_iff_sourcePins`).
- A log that only ever puts well-formed claims has only well-formed claims in
  its state (`latest_wellFormed`).

Every name here is new to VerEKOS.
-/
import Mathlib.Data.Finset.Sort
import World.Log
import World.Status
import World.Visible

namespace World

set_option autoImplicit false

variable {C : Carriers} {P : C.SchemaId → Type}

/-! ## Rule 1: pins are nonempty -/

/-- A claim has at least one pin. -/
def Claim.PinsNonempty (c : Claim C P) : Prop := c.pins ≠ []

/-! ## Rule 3: sources sorted and duplicate-free -/

section keys
variable [LinearOrder C.SourceId]

/-- A key's sources are strictly increasing: sorted, with no repeats. -/
def ClaimKey.Canonical (k : ClaimKey C) : Prop := k.sources.Pairwise (· < ·)

/-- Put a key's sources into canonical form. -/
def ClaimKey.normalize (k : ClaimKey C) : ClaimKey C :=
  { k with sources := k.sources.toFinset.sort }

theorem ClaimKey.normalize_canonical (k : ClaimKey C) : k.normalize.Canonical := by
  unfold ClaimKey.Canonical ClaimKey.normalize
  exact (Finset.sortedLT_sort k.sources.toFinset).pairwise

theorem ClaimKey.mem_normalize (k : ClaimKey C) (s : C.SourceId) :
    s ∈ k.normalize.sources ↔ s ∈ k.sources := by
  simp [ClaimKey.normalize]

/-- **Canonical keys are equal iff they have the same schema, subject and set
of sources.** Order and repetition of sources cannot make two keys (and so,
under any derivation, two ids) for one source set. -/
theorem ClaimKey.eq_iff_of_canonical (k₁ k₂ : ClaimKey C) (h₁ : k₁.Canonical)
    (h₂ : k₂.Canonical) :
    k₁ = k₂ ↔ k₁.schema = k₂.schema ∧ k₁.subject = k₂.subject ∧
      ∀ s, s ∈ k₁.sources ↔ s ∈ k₂.sources := by
  constructor
  · rintro rfl; exact ⟨rfl, rfl, fun _ => Iff.rfl⟩
  · rintro ⟨hs, hsub, hsrc⟩
    have : k₁.sources = k₂.sources := List.Pairwise.eq_of_mem_iff h₁ h₂ hsrc
    cases k₁; cases k₂
    simp_all

/-- Normalization identifies exactly the keys with the same source set. -/
theorem ClaimKey.normalize_eq_iff (k₁ k₂ : ClaimKey C) :
    k₁.normalize = k₂.normalize ↔ k₁.schema = k₂.schema ∧ k₁.subject = k₂.subject ∧
      ∀ s, s ∈ k₁.sources ↔ s ∈ k₂.sources := by
  rw [ClaimKey.eq_iff_of_canonical _ _ (normalize_canonical _) (normalize_canonical _)]
  simp only [ClaimKey.mem_normalize]
  rfl

/-- Normalizing a canonical key changes nothing. -/
theorem ClaimKey.normalize_of_canonical (k : ClaimKey C) (h : k.Canonical) :
    k.normalize = k :=
  (ClaimKey.eq_iff_of_canonical _ _ (normalize_canonical _) h).mpr
    ⟨rfl, rfl, fun s => mem_normalize k s⟩

/-- A well-formed claim: nonempty pins and a canonical key. (Acyclicity is a
property of a state, not of one claim: see `Ranked`.) -/
def Claim.WellFormed (c : Claim C P) : Prop := c.PinsNonempty ∧ c.key.Canonical

/-- A log puts only well-formed claims. -/
def LogWellFormed (L : List (Receipt C P)) : Prop :=
  ∀ r ∈ L, ∀ c, r.op = .put c → c.WellFormed

theorem foldl_apply_wellFormed (d : ClaimIdDerivation C) :
    ∀ (L : List (Receipt C P)) (s : View C P),
      (∀ i c, s i = some c → c.WellFormed) → LogWellFormed L →
      ∀ i c, (L.foldl (apply d) s) i = some c → c.WellFormed
  | [], s, hs, _, i, c, h => hs i c h
  | r :: L, s, hs, hL, i, c, h => by
    refine foldl_apply_wellFormed d L (apply d s r) ?_
      (fun r' hr' => hL r' (List.mem_cons_of_mem _ hr')) i c h
    intro j c' hj
    unfold apply at hj
    cases hop : r.op with
    | put c₀ =>
      simp only [hop] at hj
      split at hj
      · injection hj with hj
        subst hj
        exact hL r List.mem_cons_self _ hop
      · exact hs j c' hj
    | retract k =>
      simp only [hop] at hj
      split at hj
      · cases hj
      · exact hs j c' hj

/-- **A well-formed log has a well-formed state.** -/
theorem latest_wellFormed (d : ClaimIdDerivation C) (L : List (Receipt C P))
    (h : LogWellFormed L) (i : C.ClaimId) (c : Claim C P)
    (hc : latest d L i = some c) : c.WellFormed :=
  foldl_apply_wellFormed d L View.empty (by intro _ _ h; cases h) h i c hc

end keys

/-! ## Rule 2: no pin cycles -/

/-- `c'` is a premise of `c` in state `σ`: `c` has a claim pin naming an id
under which `σ` holds `c'`. -/
def PremiseOf (σ : C.ClaimId → Option (Claim C P)) (c' c : Claim C P) : Prop :=
  ∃ p ∈ c.pins, ∃ i, p.target = .claim i ∧ σ i = some c'

/-- A rank for the pin graph of `σ`: it strictly drops from every claim to
each of its premises. Its existence is the "no pin cycles" rule. -/
structure Ranked (σ : C.ClaimId → Option (Claim C P)) (rank : Claim C P → Nat) : Prop where
  lt : ∀ c' c, PremiseOf σ c' c → rank c' < rank c

/-- A ranked pin graph is well founded: there is no infinite chain of
premises, so in particular no cycle. -/
theorem Ranked.wellFounded {σ : C.ClaimId → Option (Claim C P)} {rank : Claim C P → Nat}
    (hr : Ranked σ rank) : WellFounded (PremiseOf σ) :=
  Subrelation.wf (fun {_ _} h => hr.lt _ _ h) (InvImage.wf rank wellFounded_lt)

/-- No claim is its own premise in a ranked state. -/
theorem Ranked.not_self {σ : C.ClaimId → Option (Claim C P)} {rank : Claim C P → Nat}
    (hr : Ranked σ rank) (c : Claim C P) : ¬ PremiseOf σ c c :=
  fun h => Nat.lt_irrefl _ (hr.lt c c h)

theorem any_congr_mem {α : Type} (l : List α) (f g : α → Bool)
    (h : ∀ a ∈ l, f a = g a) : l.any f = l.any g := by
  induction l with
  | nil => rfl
  | cons a l ih =>
    simp only [List.any_cons]
    rw [h a List.mem_cons_self, ih (fun b hb => h b (List.mem_cons_of_mem _ hb))]

theorem all_congr_mem {α : Type} (l : List α) (f g : α → Bool)
    (h : ∀ a ∈ l, f a = g a) : l.all f = l.all g := by
  induction l with
  | nil => rfl
  | cons a l ih =>
    simp only [List.all_cons]
    rw [h a List.mem_cons_self, ih (fun b hb => h b (List.mem_cons_of_mem _ hb))]

section visible
variable (d : ClaimIdDerivation C) (σ : C.ClaimId → Option (Claim C P)) (S : Scope C)
  {rank : Claim C P → Nat}

theorem denied_stable (hr : Ranked σ rank) :
    ∀ (n m : Nat) (c : Claim C P), rank c < n → rank c < m →
      denied d σ S n c = denied d σ S m c
  | 0, _, _, hn, _ => absurd hn (Nat.not_lt_zero _)
  | _ + 1, 0, _, _, hm => absurd hm (Nat.not_lt_zero _)
  | n + 1, m + 1, c, hn, hm => by
    simp only [denied]
    congr 1
    apply any_congr_mem
    intro p hp
    dsimp only
    cases ht : p.target with
    | source doc r => rfl
    | claim i =>
      dsimp only
      cases hσ : σ i with
      | none => rfl
      | some c' =>
        dsimp only
        have := hr.lt c' c ⟨p, hp, i, ht, hσ⟩
        exact denied_stable hr n m c' (by omega) (by omega)

theorem allowed_stable (hr : Ranked σ rank) :
    ∀ (n m : Nat) (c : Claim C P), rank c < n → rank c < m →
      allowed d σ S n c = allowed d σ S m c
  | 0, _, _, hn, _ => absurd hn (Nat.not_lt_zero _)
  | _ + 1, 0, _, _, hm => absurd hm (Nat.not_lt_zero _)
  | n + 1, m + 1, c, hn, hm => by
    simp only [allowed]
    congr 2
    apply all_congr_mem
    intro p hp
    dsimp only
    cases ht : p.target with
    | source doc r => rfl
    | claim i =>
      dsimp only
      cases hσ : σ i with
      | none => rfl
      | some c' =>
        dsimp only
        have := hr.lt c' c ⟨p, hp, i, ht, hσ⟩
        exact allowed_stable hr n m c' (by omega) (by omega)

/-- **The depth bound stops mattering above the rank.** In a state with no pin
cycles, every bound larger than a claim's rank gives the same visibility. -/
theorem visible_stable (hr : Ranked σ rank) (n m : Nat) (c : Claim C P)
    (hn : rank c < n) (hm : rank c < m) : visible d σ S n c = visible d σ S m c := by
  simp only [visible, denied_stable d σ S hr n m c hn hm, allowed_stable d σ S hr n m c hn hm]

/-- Visibility with no arbitrary bound: the bounded visibility at rank + 1,
which by `visible_stable` is the answer at every larger bound. -/
def visibleR (rank : Claim C P → Nat) (c : Claim C P) : Bool :=
  visible d σ S (rank c + 1) c

/-- **`visibleR` is the limit of the bounded visibility.** -/
theorem visible_eq_visibleR (hr : Ranked σ rank) (n : Nat) (c : Claim C P)
    (hn : rank c < n) : visible d σ S n c = visibleR d σ S rank c :=
  visible_stable d σ S hr n (rank c + 1) c hn (Nat.lt_succ_self _)

/-- **`visibleR` does not depend on which rank is used.** Two ranks for the
same state give the same visibility, so "the" visibility of a claim is
well defined. -/
theorem visibleR_rank_irrelevant {rank' : Claim C P → Nat} (hr : Ranked σ rank)
    (hr' : Ranked σ rank') (c : Claim C P) :
    visibleR d σ S rank c = visibleR d σ S rank' c := by
  unfold visibleR
  rw [visible_stable d σ S hr (rank c + 1) (max (rank c) (rank' c) + 1) c (by omega) (by omega),
    visible_stable d σ S hr' (max (rank c) (rank' c) + 1) (rank' c + 1) c (by omega) (by omega)]

/-- **Nonempty pins make source visibility exact.** A claim whose pins are all
source pins, and which has at least one, is visible (at any bound above zero,
when its id is not explicitly allowed) exactly when every pin's origin is
allowed and not denied. Without rule 1 the "if" direction would hold
vacuously for an unpinned claim; `visible` refuses that case instead. -/
theorem visible_iff_sourcePins (n : Nat) (c : Claim C P) (hne : c.PinsNonempty)
    (hsrc : ∀ p ∈ c.pins, ∃ doc r, p.target = .source doc r)
    (hid : S.allowsId (c.id d) = false) (hdid : S.deniesId (c.id d) = false) :
    visible d σ S (n + 1) c = true ↔
      ∀ p ∈ c.pins, ∀ doc r, p.target = .source doc r →
        S.allowsOrigin doc r = true ∧ S.deniesOrigin doc r = false := by
  constructor
  · intro hv p hp doc r ht
    exact ((visible_pins d σ S n c hv hid).2 p hp).1 doc r ht
  · intro hall
    simp only [visible, denied, allowed, hid, hdid, Bool.false_or,
      Bool.and_eq_true, Bool.not_eq_true', List.any_eq_false, List.all_eq_true,
      List.isEmpty_eq_false_iff]
    refine ⟨fun p hp => ?_, hne, fun p hp => ?_⟩
    · obtain ⟨doc, r, ht⟩ := hsrc p hp
      have := (hall p hp doc r ht).2
      simp [ht, this]
    · obtain ⟨doc, r, ht⟩ := hsrc p hp
      have := (hall p hp doc r ht).1
      simp [ht, this]

end visible

/-! ## Acyclicity removes the self-review hypothesis -/

section status
variable (R : ReviewSchema C P) (reg : Registry C P) (d : ClaimIdDerivation C)

/-- A review claim has exactly one pin: the claim pin at the core it read. -/
theorem asReview_pins (c : Claim C P) (i : C.ClaimId) (dg : C.Digest) (s : Status)
    (h : asReview R c = some (i, dg, s)) : ∃ w, c.pins = [⟨.claim i, .core dg, w⟩] := by
  unfold asReview at h
  split at h
  · split at h
    · rename_i i' dg' w hpins
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, -⟩ := h
      exact ⟨w, hpins⟩
    · exact absurd h (by simp)
  · exact absurd h (by simp)

theorem latest_append_put (L : List (Receipt C P)) (r : Receipt C P) (c : Claim C P)
    (hop : r.op = .put c) : latest d (L ++ [r]) (c.id d) = some c := by
  simp [latest, replay, List.foldl_append, apply, hop]

/-- **ReviewSurvives for a put, with acyclicity instead of an ad hoc
hypothesis.** If the state after putting `c'` has no pin cycles, then `c'`
cannot be a review of itself, and the status of `c'` is the status `c` had
(same id, same core). -/
theorem reviewSurvives_put_acyclic [∀ s, DecidableEq (P s)]
    (hinj : Function.Injective d.claimId)
    (L : List (Receipt C P)) (c c' : Claim C P) (r : Receipt C P) (hop : r.op = .put c')
    {rank : Claim C P → Nat} (hacyc : Ranked (latest d (L ++ [r])) rank)
    (hid : c.id d = c'.id d) (hcore : c.core reg = c'.core reg) :
    status R reg d (L ++ [r]) c' = status R reg d L c := by
  apply reviewSurvives R reg d hinj L [r] c c' hid hcore
  intro r' hr'
  simp only [List.mem_singleton] at hr'
  subst hr'
  cases hrev : reviewOf R reg d c'.key r' with
  | none => rfl
  | some v =>
    exfalso
    obtain ⟨dg, s⟩ := v
    obtain ⟨c'', hop', has, -⟩ := (reviewOf_eq_some R reg d c'.key r' dg s).mp hrev
    rw [hop] at hop'
    cases hop'
    obtain ⟨w, hpins⟩ := asReview_pins R c' _ dg s has
    apply hacyc.not_self c'
    refine ⟨⟨.claim (c'.id d), .core dg, w⟩, by rw [hpins]; exact List.mem_singleton_self _,
      c'.id d, rfl, ?_⟩
    exact latest_append_put d L r' c' hop

end status

end World
