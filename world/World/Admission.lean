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
import World.Ranked

namespace World

set_option autoImplicit false

variable [C : Carriers] {P : C.SchemaId → Type} [d : ClaimIdDerivation]

/-- Recorded ranks: the rank last recorded under each id, if any. -/
abbrev RankMap [C : Carriers] := C.ClaimId → Option Nat

/-- The rank one pin contributes: `1 +` the recorded rank of the id it pins
(`0` for an unrecorded id), or `0` for a source pin. -/
def pinRank (m : RankMap) (p : Pin) : Nat :=
  match p.target with
  | .claim j => (m j).getD 0 + 1
  | .source _ _ => 0

/-- The largest pin rank in a list. -/
def maxPinRank (m : RankMap) : List (Pin) → Nat
  | [] => 0
  | p :: ps => max (pinRank m p) (maxPinRank m ps)

/-- The computed rank of a claim against recorded ranks. -/
def newRank (m : RankMap) (c : Claim P) : Nat := maxPinRank m c.pins

/-- One receipt's effect on the recorded ranks. -/
def rstep (m : RankMap) (r : Receipt P) : RankMap :=
  match r.op with
  | .put c => fun i => if i = c.id then some (newRank m c) else m i
  | .retract _ => m

/-- The recorded ranks after a log. -/
def rankMap (L : List (Receipt P)) : RankMap := L.foldl (rstep) (fun _ => none)

/-- The computed rank of any claim against a log (total). -/
def rankN (L : List (Receipt P)) (c : Claim P) : Nat := newRank (rankMap L) c

/-- The computed rank, refusing (`none`) a claim that pins an id the log never
put. -/
def rankOf (L : List (Receipt P)) (c : Claim P) : Option Nat :=
  if c.pins.all (fun p => match p.target with
      | .claim j => (rankMap L j).isSome
      | .source _ _ => true)
  then some (rankN L c) else none

/-- Is this receipt admissible after log `L`? -/
def admissible (L : List (Receipt P)) (r : Receipt P) : Bool :=
  match r.op with
  | .put c =>
    c.pins.all (fun p => match p.target with
        | .claim j => decide (j ≠ c.id) && (latest L j).isSome
        | .source _ _ => true) &&
    (match rankMap L (c.id) with
     | some k => decide (newRank (rankMap L) c ≤ k)
     | none => true)
  | .retract _ => true

/-- Every receipt is admissible against the log before it. -/
def AdmLog (L : List (Receipt P)) : Prop :=
  ∀ k (h : k < L.length), admissible (L.take k) L[k] = true

instance (L : List (Receipt P)) : Decidable (AdmLog L) := by
  unfold AdmLog; infer_instance

/-! ## Facts about ranks -/

theorem lt_maxPinRank (m : RankMap) (ps : List (Pin)) (p : Pin) (hp : p ∈ ps)
    (j : C.ClaimId) (ht : p.target = .claim j) : (m j).getD 0 < maxPinRank m ps := by
  induction ps with
  | nil => cases hp
  | cons q qs ih =>
    simp only [maxPinRank]
    rcases List.mem_cons.mp hp with rfl | hq
    · have : pinRank m p = (m j).getD 0 + 1 := by simp [pinRank, ht]
      omega
    · have := ih hq; omega

theorem maxPinRank_mono (m m' : RankMap) (ps : List (Pin))
    (h : ∀ p ∈ ps, ∀ j, p.target = .claim j → (m' j).getD 0 ≤ (m j).getD 0) :
    maxPinRank m' ps ≤ maxPinRank m ps := by
  induction ps with
  | nil => exact Nat.le_refl _
  | cons q qs ih =>
    simp only [maxPinRank]
    have hq : pinRank m' q ≤ pinRank m q := by
      unfold pinRank
      cases ht : q.target with
      | source _ _ => exact Nat.le_refl _
      | claim j => have := h q List.mem_cons_self j ht; dsimp only; omega
    have := ih (fun p hp => h p (List.mem_cons_of_mem _ hp))
    omega

theorem maxPinRank_congr (m m' : RankMap) (ps : List (Pin))
    (h : ∀ p ∈ ps, ∀ j, p.target = .claim j → m' j = m j) :
    maxPinRank m' ps = maxPinRank m ps :=
  Nat.le_antisymm (maxPinRank_mono m m' ps fun p hp j ht => by simp [h p hp j ht])
    (maxPinRank_mono m' m ps fun p hp j ht => by simp [h p hp j ht])

/-! ## Admissible logs -/

theorem admLog_snoc (L : List (Receipt P)) (r : Receipt P) :
    AdmLog (L ++ [r]) ↔ AdmLog L ∧ admissible L r = true := by
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
def RankInv (L : List (Receipt P)) : Prop :=
  (∀ j c, latest L j = some c → ∃ k, rankMap L j = some k ∧ newRank (rankMap L) c ≤ k) ∧
  (∀ j c, latest L j = some c → ∀ p ∈ c.pins, ∀ i, p.target = .claim i →
    (rankMap L i).isSome = true)

theorem rankMap_snoc (L : List (Receipt P)) (r : Receipt P) :
    rankMap (L ++ [r]) = rstep (rankMap L) r := by
  simp [rankMap, List.foldl_append]

theorem latest_snoc' (L : List (Receipt P)) (r : Receipt P) :
    latest (L ++ [r]) = apply (latest L) r := by
  simp [latest, replay, List.foldl_append]

theorem rankInv_snoc (L : List (Receipt P)) (r : Receipt P) (hinv : RankInv L)
    (hadm : admissible L r = true) : RankInv (L ++ [r]) := by
  obtain ⟨hA, hB⟩ := hinv
  rw [RankInv, rankMap_snoc, latest_snoc']
  unfold admissible at hadm
  unfold apply rstep
  cases hop : r.op with
  | retract x =>
    simp only
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
    -- c₀'s pins avoid (c₀.id) and name present ids.
    have hpin : ∀ p ∈ c₀.pins, ∀ i, p.target = .claim i → i ≠ (c₀.id) ∧ (latest L i).isSome := by
      intro p hp i ht
      have := hpins p hp
      simp only [ht, Bool.and_eq_true, decide_eq_true_eq] at this
      exact this
    -- The new map agrees with the old one except at (c₀.id).
    have hm'ne : ∀ i, i ≠ (c₀.id) → (if i = (c₀.id) then some (newRank (rankMap L) c₀) else (rankMap L) i) = (rankMap L) i := by
      intro i hi; simp [hi]
    -- c₀'s computed rank is the same against the new map.
    have hsame : newRank (fun i => if i = (c₀.id) then some (newRank (rankMap L) c₀) else (rankMap L) i) c₀ = (newRank (rankMap L) c₀) := by
      unfold newRank
      exact maxPinRank_congr _ _ _ fun p hp i ht => hm'ne i (hpin p hp i ht).1
    -- The new map is no higher than the old one at every recorded id.
    have hle : ∀ i, ((rankMap L) i).isSome = true →
        ((if i = (c₀.id) then some (newRank (rankMap L) c₀) else (rankMap L) i).getD 0) ≤ ((rankMap L) i).getD 0 := by
      intro i hi
      by_cases hix : i = (c₀.id)
      · subst hix
        obtain ⟨k, hk⟩ := Option.isSome_iff_exists.mp hi
        simp only [if_true, Option.getD_some, hk]
        rw [hk] at hcap
        simpa using hcap
      · simp [hix]
    refine ⟨fun j c hj => ?_, fun j c hj => ?_⟩
    · by_cases hjx : j = (c₀.id)
      · simp only [hjx, if_true, Option.some.injEq] at hj ⊢
        subst hj
        exact ⟨(newRank (rankMap L) c₀), rfl, Nat.le_of_eq hsame⟩
      · simp only [hjx, if_false] at hj ⊢
        obtain ⟨k, hk, hck⟩ := hA j c hj
        refine ⟨k, hk, Nat.le_trans ?_ hck⟩
        unfold newRank
        exact maxPinRank_mono _ _ _ fun p hp i ht => hle i (hB j c hj p hp i ht)
    · intro p hp i ht
      by_cases hix : i = (c₀.id)
      · simp [hix]
      · simp only [hix, if_false]
        by_cases hjx : j = (c₀.id)
        · simp only [hjx, if_true, Option.some.injEq] at hj
          subst hj
          obtain ⟨-, hpres⟩ := hpin p hp i ht
          obtain ⟨c', hc'⟩ := Option.isSome_iff_exists.mp hpres
          obtain ⟨k, hk, -⟩ := hA i c' hc'
          simp [hk]
        · simp only [hjx, if_false] at hj
          exact hB j c hj p hp i ht

theorem rankInv_of_admLog_rev : ∀ (R : List (Receipt P)), AdmLog R.reverse → RankInv R.reverse
  | [], _ => by
    refine ⟨fun j c h => ?_, fun j c h => ?_⟩ <;> cases h
  | r :: R, h => by
    rw [List.reverse_cons] at h ⊢
    obtain ⟨hL, hr⟩ := (admLog_snoc R.reverse r).mp h
    exact rankInv_snoc R.reverse r (rankInv_of_admLog_rev R hL) hr

theorem rankInv_of_admLog (L : List (Receipt P)) (h : AdmLog L) : RankInv L := by
  have := rankInv_of_admLog_rev L.reverse (by rw [List.reverse_reverse]; exact h)
  rwa [List.reverse_reverse] at this

/-- **An admissible log yields a ranked state**, ranked by the computed rank.
So `visibleR` with `rankN L` is defined on every admissible log, and by
`visibleR_rank_irrelevant` it agrees with any other rank. -/
theorem ranked_of_admLog (L : List (Receipt P)) (h : AdmLog L) :
    Ranked (latest L) (rankN L) := by
  obtain ⟨hA, -⟩ := rankInv_of_admLog L h
  refine ⟨fun c' c ⟨p, hp, i, ht, hσ⟩ => ?_⟩
  obtain ⟨k, hk, hc'⟩ := hA i c' hσ
  have := lt_maxPinRank (rankMap L) c.pins p hp i ht
  rw [hk] at this
  unfold rankN newRank
  simp only [Option.getD_some] at this
  exact Nat.lt_of_le_of_lt hc' this

/-- **On an admissible log, `rankOf` returns a rank for every claim in the
state**, and it is the rank that `ranked_of_admLog` uses. -/
theorem rankOf_some_of_admLog (L : List (Receipt P)) (h : AdmLog L)
    (i : C.ClaimId) (c : Claim P) (hc : latest L i = some c) :
    rankOf L c = some (rankN L c) := by
  obtain ⟨-, hB⟩ := rankInv_of_admLog L h
  unfold rankOf
  rw [if_pos]
  rw [List.all_eq_true]
  intro p hp
  cases ht : p.target with
  | source _ _ => rfl
  | claim j => exact hB i c hc p hp j ht

/-- A put that pins its own id is never admissible. -/
theorem not_admissible_self_pin (L : List (Receipt P)) (r : Receipt P) (c : Claim P)
    (hop : r.op = .put c) (p : Pin) (hp : p ∈ c.pins) (ht : p.target = .claim (c.id)) :
    admissible L r = false := by
  unfold admissible
  simp only [hop, Bool.and_eq_false_iff]
  left
  rw [List.all_eq_false]
  exact ⟨p, hp, by simp [ht]⟩

/-- A put that pins an absent id is never admissible. -/
theorem not_admissible_absent_pin (L : List (Receipt P)) (r : Receipt P) (c : Claim P)
    (hop : r.op = .put c) (p : Pin) (hp : p ∈ c.pins) (j : C.ClaimId)
    (ht : p.target = .claim j) (habs : latest L j = none) :
    admissible L r = false := by
  unfold admissible
  simp only [hop, Bool.and_eq_false_iff]
  left
  rw [List.all_eq_false]
  exact ⟨p, hp, by simp [ht, habs]⟩

end World
