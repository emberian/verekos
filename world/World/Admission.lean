/-
# World.Admission — keeping the pin graph acyclic across writes

In plain words: every put is checked before it is accepted (`admissible`).
A put of claim `c` is admissible when:

1. every claim pin of `c` names an id that is **present** in the state and is
   **not `c`'s own id**; and
2. if `c`'s id has held a claim before, `c`'s **computed rank** is **no higher**
   than the rank recorded for that id.

The rank of a claim is `1 +` the largest recorded rank among the ids it pins,
or `0` if it pins no claim (`newRank`). The recorded ranks (`rankMap`) are
computed by replaying the log, the same way the state is: a put records the
new claim's rank under its id, and a retract leaves the record alone. That way
an id that comes back after a retraction cannot climb above the claims that
still pin it.

The rank is computed by structural recursion over the log, a finite list. A
state on its own is a function with no size to count; the log is what makes
it finite. `rankOf` returns `none` exactly when a claim pins an id that the log
never put.

Theorems:
- `admLog_snoc`: a log is admissible iff its prefix is and its last receipt is
  admissible against the prefix. `AdmLog` is decidable, with an instance.
- `ranked_of_admLog`: **an admissible log yields a ranked state**, ranked by
  the computed rank, so `visibleR` is defined on it.
- `rankOf_some_of_admLog`: on an admissible log, `rankOf` returns `some` for
  every claim in the state.

Rule 2 is stricter than needed. A claim whose new version pins deeper
premises cannot be re-put under the same id at a higher rank, even when
nothing pins it. A fuller law would re-rank the dependents. See the memo.

Every name here is new to VerEKOS.
-/
import World.WellFormed

namespace World

set_option autoImplicit false

variable {C : Carriers} {P : C.SchemaId → Type} (d : ClaimIdDerivation C)

/-- Recorded ranks: the rank last recorded under each id, if any. -/
abbrev RankMap (C : Carriers) := C.ClaimId → Option Nat

/-- The rank one pin contributes: `1 +` the recorded rank of the id it pins
(`0` for an unrecorded id), or `0` for a source pin. -/
def pinRank (m : RankMap C) (p : Pin C) : Nat :=
  match p.target with
  | .claim j => (m j).getD 0 + 1
  | .source _ _ => 0

/-- The largest pin rank in a list. -/
def maxPinRank (m : RankMap C) : List (Pin C) → Nat
  | [] => 0
  | p :: ps => max (pinRank m p) (maxPinRank m ps)

/-- The computed rank of a claim against recorded ranks. -/
def newRank (m : RankMap C) (c : Claim C P) : Nat := maxPinRank m c.pins

/-- One receipt's effect on the recorded ranks. -/
def rstep (m : RankMap C) (r : Receipt C P) : RankMap C :=
  match r.op with
  | .put c => fun i => if i = c.id d then some (newRank m c) else m i
  | .retract _ => m

/-- The recorded ranks after a log. -/
def rankMap (L : List (Receipt C P)) : RankMap C := L.foldl (rstep d) (fun _ => none)

/-- The computed rank of any claim against a log (total). -/
def rankN (L : List (Receipt C P)) (c : Claim C P) : Nat := newRank (rankMap d L) c

/-- The computed rank, refusing (`none`) a claim that pins an id the log never
put. -/
def rankOf (L : List (Receipt C P)) (c : Claim C P) : Option Nat :=
  if c.pins.all (fun p => match p.target with
      | .claim j => (rankMap d L j).isSome
      | .source _ _ => true)
  then some (rankN d L c) else none

/-- Is this receipt admissible after log `L`? -/
def admissible (L : List (Receipt C P)) (r : Receipt C P) : Bool :=
  match r.op with
  | .put c =>
    c.pins.all (fun p => match p.target with
        | .claim j => decide (j ≠ c.id d) && (latest d L j).isSome
        | .source _ _ => true) &&
    (match rankMap d L (c.id d) with
     | some k => decide (newRank (rankMap d L) c ≤ k)
     | none => true)
  | .retract _ => true

/-- Every receipt is admissible against the log before it. -/
def AdmLog (L : List (Receipt C P)) : Prop :=
  ∀ k (h : k < L.length), admissible d (L.take k) L[k] = true

instance (L : List (Receipt C P)) : Decidable (AdmLog d L) := by
  unfold AdmLog; infer_instance

/-! ## Facts about ranks -/

theorem lt_maxPinRank (m : RankMap C) (ps : List (Pin C)) (p : Pin C) (hp : p ∈ ps)
    (j : C.ClaimId) (ht : p.target = .claim j) : (m j).getD 0 < maxPinRank m ps := by
  induction ps with
  | nil => cases hp
  | cons q qs ih =>
    simp only [maxPinRank]
    rcases List.mem_cons.mp hp with rfl | hq
    · have : pinRank m p = (m j).getD 0 + 1 := by simp [pinRank, ht]
      omega
    · have := ih hq; omega

theorem maxPinRank_mono (m m' : RankMap C) (ps : List (Pin C))
    (h : ∀ p ∈ ps, ∀ j, p.target = .claim j → (m' j).getD 0 ≤ (m j).getD 0) :
    maxPinRank m' ps ≤ maxPinRank m ps := by
  induction ps with
  | nil => exact le_refl _
  | cons q qs ih =>
    simp only [maxPinRank]
    have hq : pinRank m' q ≤ pinRank m q := by
      unfold pinRank
      cases ht : q.target with
      | source _ _ => exact le_refl _
      | claim j => have := h q List.mem_cons_self j ht; omega
    have := ih (fun p hp => h p (List.mem_cons_of_mem _ hp))
    omega

theorem maxPinRank_congr (m m' : RankMap C) (ps : List (Pin C))
    (h : ∀ p ∈ ps, ∀ j, p.target = .claim j → m' j = m j) :
    maxPinRank m' ps = maxPinRank m ps :=
  le_antisymm (maxPinRank_mono m m' ps fun p hp j ht => by rw [h p hp j ht])
    (maxPinRank_mono m' m ps fun p hp j ht => by rw [h p hp j ht])

/-! ## Admissible logs -/

theorem admLog_snoc (L : List (Receipt C P)) (r : Receipt C P) :
    AdmLog d (L ++ [r]) ↔ AdmLog d L ∧ admissible d L r = true := by
  constructor
  · intro h
    refine ⟨fun k hk => ?_, ?_⟩
    · have := h k (by simp; omega)
      rwa [List.take_append_of_le_length (by omega), List.getElem_append_left hk] at this
    · have := h L.length (by simp)
      simpa using this
  · rintro ⟨hL, hr⟩ k hk
    simp only [List.length_append, List.length_singleton] at hk
    by_cases hkl : k < L.length
    · rw [List.take_append_of_le_length (by omega), List.getElem_append_left hkl]
      exact hL k hkl
    · have : k = L.length := by omega
      subst this
      simpa using hr

/-- The invariant an admissible log keeps. (A) every claim in the state has a
recorded rank at least its computed rank; (B) every claim pin of a claim in
the state names an id with a recorded rank. -/
def RankInv (L : List (Receipt C P)) : Prop :=
  (∀ j c, latest d L j = some c → ∃ k, rankMap d L j = some k ∧ newRank (rankMap d L) c ≤ k) ∧
  (∀ j c, latest d L j = some c → ∀ p ∈ c.pins, ∀ i, p.target = .claim i →
    (rankMap d L i).isSome = true)

theorem rankMap_snoc (L : List (Receipt C P)) (r : Receipt C P) :
    rankMap d (L ++ [r]) = rstep d (rankMap d L) r := by
  simp [rankMap, List.foldl_append]

theorem latest_snoc' (L : List (Receipt C P)) (r : Receipt C P) :
    latest d (L ++ [r]) = apply d (latest d L) r := by
  simp [latest, replay, List.foldl_append]

theorem rankInv_snoc (L : List (Receipt C P)) (r : Receipt C P) (hinv : RankInv d L)
    (hadm : admissible d L r = true) : RankInv d (L ++ [r]) := by
  obtain ⟨hA, hB⟩ := hinv
  rw [RankInv, rankMap_snoc, latest_snoc']
  unfold admissible at hadm
  unfold apply rstep
  cases hop : r.op with
  | retract x =>
    simp only [hop]
    refine ⟨fun j c hj => ?_, fun j c hj => ?_⟩
    · split at hj
      · cases hj
      · exact hA j c hj
    · split at hj
      · cases hj
      · exact hB j c hj
  | put c₀ =>
    simp only [hop, Bool.and_eq_true, List.all_eq_true] at hadm ⊢
    obtain ⟨hpins, hcap⟩ := hadm
    set x := c₀.id d with hx
    set m := rankMap d L with hm
    set nr := newRank m c₀ with hnr
    -- c₀'s pins avoid x and name present ids.
    have hpin : ∀ p ∈ c₀.pins, ∀ i, p.target = .claim i → i ≠ x ∧ (latest d L i).isSome := by
      intro p hp i ht
      have := hpins p hp
      simp only [ht, Bool.and_eq_true, decide_eq_true_eq] at this
      exact this
    -- The new map agrees with the old one except at x.
    have hm'ne : ∀ i, i ≠ x → (if i = x then some nr else m i) = m i := by
      intro i hi; simp [hi]
    -- c₀'s computed rank is the same against the new map.
    have hsame : newRank (fun i => if i = x then some nr else m i) c₀ = nr := by
      unfold newRank
      rw [hnr]
      exact maxPinRank_congr _ _ _ fun p hp i ht => hm'ne i (hpin p hp i ht).1
    -- The new map is no higher than the old one at every recorded id.
    have hle : ∀ i, (m i).isSome = true →
        ((if i = x then some nr else m i).getD 0) ≤ (m i).getD 0 := by
      intro i hi
      by_cases hix : i = x
      · subst hix
        obtain ⟨k, hk⟩ := Option.isSome_iff_exists.mp hi
        simp only [if_true, Option.getD_some, hk]
        rw [hk] at hcap
        simpa using hcap
      · simp [hix]
    refine ⟨fun j c hj => ?_, fun j c hj => ?_⟩
    · by_cases hjx : j = x
      · simp only [hjx, if_true, Option.some.injEq] at hj ⊢
        subst hj
        exact ⟨nr, rfl, by rw [hsame]⟩
      · simp only [hjx, if_false] at hj ⊢
        obtain ⟨k, hk, hck⟩ := hA j c hj
        refine ⟨k, hk, le_trans ?_ hck⟩
        unfold newRank
        exact maxPinRank_mono _ _ _ fun p hp i ht => hle i (hB j c hj p hp i ht)
    · intro p hp i ht
      by_cases hix : i = x
      · simp [hix]
      · simp only [hix, if_false]
        by_cases hjx : j = x
        · simp only [hjx, if_true, Option.some.injEq] at hj
          subst hj
          obtain ⟨-, hpres⟩ := hpin p hp i ht
          obtain ⟨c', hc'⟩ := Option.isSome_iff_exists.mp hpres
          obtain ⟨k, hk, -⟩ := hA i c' hc'
          simp [hk]
        · simp only [hjx, if_false] at hj
          exact hB j c hj p hp i ht

theorem rankInv_of_admLog : ∀ (L : List (Receipt C P)), AdmLog d L → RankInv d L := by
  intro L
  induction L using List.reverseRecOn with
  | nil =>
    intro _
    refine ⟨fun j c h => ?_, fun j c h => ?_⟩ <;> cases h
  | append_singleton L r ih =>
    intro h
    obtain ⟨hL, hr⟩ := (admLog_snoc d L r).mp h
    exact rankInv_snoc d L r (ih hL) hr

/-- **An admissible log yields a ranked state**, ranked by the computed rank.
So `visibleR` with `rankN d L` is defined on every admissible log, and by
`visibleR_rank_irrelevant` it agrees with any other rank. -/
theorem ranked_of_admLog (L : List (Receipt C P)) (h : AdmLog d L) :
    Ranked (latest d L) (rankN d L) := by
  obtain ⟨hA, -⟩ := rankInv_of_admLog d L h
  refine ⟨fun c' c ⟨p, hp, i, ht, hσ⟩ => ?_⟩
  obtain ⟨k, hk, hc'⟩ := hA i c' hσ
  have := lt_maxPinRank (rankMap d L) c.pins p hp i ht
  rw [hk] at this
  unfold rankN newRank
  simp only [Option.getD_some] at this
  exact lt_of_le_of_lt hc' this

/-- **On an admissible log, `rankOf` returns a rank for every claim in the
state**, and it is the rank that `ranked_of_admLog` uses. -/
theorem rankOf_some_of_admLog (L : List (Receipt C P)) (h : AdmLog d L)
    (i : C.ClaimId) (c : Claim C P) (hc : latest d L i = some c) :
    rankOf d L c = some (rankN d L c) := by
  obtain ⟨-, hB⟩ := rankInv_of_admLog d L h
  unfold rankOf
  rw [if_pos]
  rw [List.all_eq_true]
  intro p hp
  cases ht : p.target with
  | source _ _ => rfl
  | claim j => exact hB i c hc p hp j ht

/-- A put that pins its own id is never admissible. -/
theorem not_admissible_self_pin (L : List (Receipt C P)) (r : Receipt C P) (c : Claim C P)
    (hop : r.op = .put c) (p : Pin C) (hp : p ∈ c.pins) (ht : p.target = .claim (c.id d)) :
    admissible d L r = false := by
  unfold admissible
  simp only [hop, Bool.and_eq_false_iff]
  left
  rw [List.all_eq_false]
  exact ⟨p, hp, by simp [ht]⟩

/-- A put that pins an absent id is never admissible. -/
theorem not_admissible_absent_pin (L : List (Receipt C P)) (r : Receipt C P) (c : Claim C P)
    (hop : r.op = .put c) (p : Pin C) (hp : p ∈ c.pins) (j : C.ClaimId)
    (ht : p.target = .claim j) (habs : latest d L j = none) :
    admissible d L r = false := by
  unfold admissible
  simp only [hop, Bool.and_eq_false_iff]
  left
  rw [List.all_eq_false]
  exact ⟨p, hp, by simp [ht, habs]⟩

end World
