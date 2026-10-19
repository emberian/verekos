/-
# World.Ranked — nonempty pins and no pin cycles (Mathlib-free)

Split out of `World.WellFormed` so that `WorldCore` can use it without
Mathlib. In plain words:

1. **Pins are nonempty** (`Claim.PinsNonempty`).
2. **Pins have no cycles**: a *rank* drops from every claim to each claim it
   pins (`Ranked`). With a rank, `visible` gives the same answer at every
   bound above a claim's rank (`visible_stable`), so `visibleR` needs no
   chosen bound. A rank on the state after a put also rules out a review of
   itself (`reviewSurvives_put_acyclic`).

The third rule (sorted, duplicate-free sources) needs an order on sources
and Mathlib's sorting, and stays in `World.WellFormed`.

Every name here is new to VerEKOS.
-/
import World.Log
import World.Status
import World.Visible

namespace World

set_option autoImplicit false

variable [C : Carriers] {P : C.SchemaId → Type}

/-! ## Rule 1: pins are nonempty -/

/-- A claim has at least one pin. -/
def Claim.PinsNonempty (c : Claim P) : Prop := c.pins ≠ []

/-! ## Rule 2: no pin cycles -/

/-- `c'` is a premise of `c` in state `σ`: `c` has a claim pin naming an id
under which `σ` holds `c'`. -/
def PremiseOf (σ : C.ClaimId → Option (Claim P)) (c' c : Claim P) : Prop :=
  ∃ p ∈ c.pins, ∃ i, p.target = .claim i ∧ σ i = some c'

/-- A rank for the pin graph of `σ`: it strictly drops from every claim to
each of its premises. Its existence is the "no pin cycles" rule. -/
structure Ranked (σ : C.ClaimId → Option (Claim P)) (rank : Claim P → Nat) : Prop where
  lt : ∀ c' c, PremiseOf σ c' c → rank c' < rank c

/-- A ranked pin graph is well founded: there is no infinite chain of
premises, so in particular no cycle. -/
theorem Ranked.wellFounded {σ : C.ClaimId → Option (Claim P)} {rank : Claim P → Nat}
    (hr : Ranked σ rank) : WellFounded (PremiseOf σ) :=
  Subrelation.wf (fun {_ _} h => hr.lt _ _ h) (InvImage.wf rank Nat.lt_wfRel.wf)

/-- No claim is its own premise in a ranked state. -/
theorem Ranked.not_self {σ : C.ClaimId → Option (Claim P)} {rank : Claim P → Nat}
    (hr : Ranked σ rank) (c : Claim P) : ¬ PremiseOf σ c c :=
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
variable [d : ClaimIdDerivation] (σ : C.ClaimId → Option (Claim P)) (S : Scope)
  {rank : Claim P → Nat}

theorem denied_stable (hr : Ranked σ rank) :
    ∀ (n m : Nat) (c : Claim P), rank c < n → rank c < m →
      denied σ S n c = denied σ S m c
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
    ∀ (n m : Nat) (c : Claim P), rank c < n → rank c < m →
      allowed σ S n c = allowed σ S m c
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
theorem visible_stable (hr : Ranked σ rank) (n m : Nat) (c : Claim P)
    (hn : rank c < n) (hm : rank c < m) : visible σ S n c = visible σ S m c := by
  simp only [visible, denied_stable σ S hr n m c hn hm, allowed_stable σ S hr n m c hn hm]

/-- Visibility with no arbitrary bound: the bounded visibility at rank + 1,
which by `visible_stable` is the answer at every larger bound. -/
def visibleR (rank : Claim P → Nat) (c : Claim P) : Bool :=
  visible σ S (rank c + 1) c

/-- **`visibleR` is the limit of the bounded visibility.** -/
theorem visible_eq_visibleR (hr : Ranked σ rank) (n : Nat) (c : Claim P)
    (hn : rank c < n) : visible σ S n c = visibleR σ S rank c :=
  visible_stable σ S hr n (rank c + 1) c hn (Nat.lt_succ_self _)

/-- **`visibleR` does not depend on which rank is used.** Two ranks for the
same state give the same visibility, so "the" visibility of a claim is
well defined. -/
theorem visibleR_rank_irrelevant {rank' : Claim P → Nat} (hr : Ranked σ rank)
    (hr' : Ranked σ rank') (c : Claim P) :
    visibleR σ S rank c = visibleR σ S rank' c := by
  unfold visibleR
  rw [visible_stable σ S hr (rank c + 1) (max (rank c) (rank' c) + 1) c (by omega) (by omega),
    visible_stable σ S hr' (max (rank c) (rank' c) + 1) (rank' c + 1) c (by omega) (by omega)]

/-- **Nonempty pins make source visibility exact.** A claim whose pins are all
source pins, and which has at least one, is visible (at any bound above zero,
when its id is not explicitly allowed) exactly when every pin's origin is
allowed and not denied. Without rule 1 the "if" direction would hold
vacuously for an unpinned claim; `visible` refuses that case instead. -/
theorem visible_iff_sourcePins (n : Nat) (c : Claim P) (hne : c.PinsNonempty)
    (hsrc : ∀ p ∈ c.pins, ∃ doc r, p.target = .source doc r)
    (hid : S.allowsId (c.id) = false) (hdid : S.deniesId (c.id) = false) :
    visible σ S (n + 1) c = true ↔
      ∀ p ∈ c.pins, ∀ doc r, p.target = .source doc r →
        S.allowsOrigin doc r = true ∧ S.deniesOrigin doc r = false := by
  constructor
  · intro hv p hp doc r ht
    exact ((visible_pins σ S n c hv hid).2 p hp).1 doc r ht
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
variable (R : ReviewSchema P) (reg : Registry P) [d : ClaimIdDerivation]

/-- A review claim has exactly one pin: the claim pin at the core it read. -/
theorem asReview_pins (c : Claim P) (i : C.ClaimId) (dg : C.Digest) (s : Status)
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

theorem latest_append_put (L : List (Receipt P)) (r : Receipt P) (c : Claim P)
    (hop : r.op = .put c) : latest (L ++ [r]) (c.id) = some c := by
  simp [latest, replay, List.foldl_append, apply, hop]

/-- **ReviewSurvives for a put, with acyclicity instead of an ad hoc
hypothesis.** If the state after putting `c'` has no pin cycles, then `c'`
cannot be a review of itself, and the status of `c'` is the status `c` had
(same id, same core). -/
theorem reviewSurvives_put_acyclic [∀ s, DecidableEq (P s)]
    (hinj : Function.Injective ClaimIdDerivation.claimId)
    (L : List (Receipt P)) (c c' : Claim P) (r : Receipt P) (hop : r.op = .put c')
    {rank : Claim P → Nat} (hacyc : Ranked (latest (L ++ [r])) rank)
    (hid : c.id = c'.id) (hcore : c.core reg = c'.core reg) :
    status R reg (L ++ [r]) c' = status R reg L c := by
  apply reviewSurvives R reg hinj L [r] c c' hid hcore
  intro r' hr'
  simp only [List.mem_singleton] at hr'
  subst hr'
  cases hrev : reviewOf R reg c'.key r' with
  | none => rfl
  | some v =>
    exfalso
    obtain ⟨dg, s⟩ := v
    obtain ⟨c'', hop', has, -⟩ := (reviewOf_eq_some R reg c'.key r' dg s).mp hrev
    rw [hop] at hop'
    cases hop'
    obtain ⟨w, hpins⟩ := asReview_pins R c' _ dg s has
    apply hacyc.not_self c'
    refine ⟨⟨.claim (c'.id), .core dg, w⟩, by rw [hpins]; exact List.mem_singleton_self _,
      c'.id, rfl, ?_⟩
    exact latest_append_put L r' c' hop

end status

end World
