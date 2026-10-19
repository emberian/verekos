/-
# CheckProofs.Adm — the runner's pin-law check is the model's

Imports Mathlib (through `World.Admission`). Built, never linked.
-/
import World.Admission
import Check.Adm

namespace Check

set_option autoImplicit false

variable {C : World.Carriers} {P : C.SchemaId → Type} (d : World.ClaimIdDerivation C)

theorem pinRankL_eq (m : C.ClaimId → Option Nat) (p : World.Pin C) :
    pinRankL m p = World.pinRank m p := by
  unfold pinRankL World.pinRank; rfl

theorem maxPinRankL_eq (m : C.ClaimId → Option Nat) (ps : List (World.Pin C)) :
    maxPinRankL m ps = World.maxPinRank m ps := by
  induction ps with
  | nil => rfl
  | cons p ps ih => simp only [maxPinRankL, World.maxPinRank, pinRankL_eq, ih]

theorem newRankL_eq (m : C.ClaimId → Option Nat) (c : World.Claim C P) :
    newRankL m c = World.newRank m c := maxPinRankL_eq m c.pins

theorem rstepL_eq : rstepL (P := P) d = World.rstep d := by
  funext m r
  unfold rstepL World.rstep
  cases r.op <;> simp [newRankL_eq]

theorem rankMapL_eq (L : List (World.Receipt C P)) : rankMapL d L = World.rankMap d L := by
  unfold rankMapL World.rankMap; rw [rstepL_eq]

theorem admissibleL_eq (L : List (World.Receipt C P)) (r : World.Receipt C P) :
    admissibleL d L r = World.admissible d L r := by
  unfold admissibleL World.admissible
  rw [rankMapL_eq]
  cases r.op with
  | retract _ => rfl
  | put c =>
    simp only [newRankL_eq]
    congr 1

/-- **The runner decides the model's pin law.** -/
theorem admLogB_iff (L : List (World.Receipt C P)) : admLogB d L = true ↔ World.AdmLog d L := by
  unfold admLogB World.AdmLog
  simp only [List.all_eq_true, List.mem_range]
  constructor
  · intro h k hk
    have := h k hk
    rw [List.getElem?_eq_getElem hk] at this
    simpa [admissibleL_eq] using this
  · intro h k hk
    rw [List.getElem?_eq_getElem hk]
    simpa [admissibleL_eq] using h k hk

theorem pinsNonemptyB_iff (c : World.Claim C P) : pinsNonemptyB c = true ↔ c.PinsNonempty := by
  unfold pinsNonemptyB World.Claim.PinsNonempty
  cases c.pins <;> simp

end Check
