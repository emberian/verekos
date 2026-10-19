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
import World.Ranked

namespace World

set_option autoImplicit false

variable {C : Carriers} {P : C.SchemaId → Type}

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

end World
