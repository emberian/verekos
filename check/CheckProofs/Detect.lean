/-
# CheckProofs.Detect — the runner's `detectL` is the model's `detectList`

Imports Mathlib (through `World.Conflicts`). Built by `lake build CheckProofs`,
never linked into the executable.
-/
import World.Conflicts
import Check.Detect

namespace Check

set_option autoImplicit false

variable {C : World.Carriers} {P : C.SchemaId → Type} [∀ s, DecidableEq (P s)]
variable (reg : World.Registry C P)

omit [∀ s, DecidableEq (P s)] in
theorem statedL_eq (c : World.Claim C P) : statedL reg c = c.stated reg := rfl

omit [∀ s, DecidableEq (P s)] in
theorem disagreeOnL_eq (c₁ c₂ : World.Claim C P) :
    disagreeOnL reg c₁ c₂ = World.disagreeOn reg c₁ c₂ := rfl

/-- **The runner computes the model.** A key is in the runner's list exactly
when it is in `World.detectList` of the same claims. -/
theorem mem_detectL (l : List (World.Claim C P)) (k : World.ConflictKey C) :
    k ∈ detectL reg l ↔ k ∈ World.detectList reg l := by
  unfold World.detectList
  rw [World.mem_detect]
  simp only [detectL, List.mem_flatMap, List.mem_toFinset]
  constructor
  · rintro ⟨c₁, h₁, c₂, h₂, hk⟩
    split at hk
    · rename_i hc
      obtain ⟨hne, hs, hsub⟩ := hc
      rw [List.mem_map] at hk
      obtain ⟨a, ha, rfl⟩ := hk
      rw [disagreeOnL_eq, World.mem_disagreeOn] at ha
      obtain ⟨v₁, v₂, hv₁, hv₂, hv⟩ := ha
      exact ⟨c₁, h₁, c₂, h₂, hne, ⟨hs, hsub⟩, a, v₁, v₂, hv₁, hv₂, hv, rfl⟩
    · simp at hk
  · rintro ⟨c₁, h₁, c₂, h₂, hne, ⟨hs, hsub⟩, a, v₁, v₂, hv₁, hv₂, hv, rfl⟩
    refine ⟨c₁, h₁, c₂, h₂, ?_⟩
    rw [if_pos ⟨hne, hs, hsub⟩, List.mem_map]
    exact ⟨a, (by rw [disagreeOnL_eq, World.mem_disagreeOn]; exact ⟨v₁, v₂, hv₁, hv₂, hv⟩), rfl⟩

theorem detectL_toFinset (l : List (World.Claim C P)) :
    (detectL reg l).toFinset = World.detectList reg l := by
  ext k
  rw [List.mem_toFinset, mem_detectL]

/-- Order and repetition do not change the runner's set of keys
(`World.detectList_congr`, carried over). -/
theorem mem_detectL_congr (l₁ l₂ : List (World.Claim C P)) (h : ∀ c, c ∈ l₁ ↔ c ∈ l₂)
    (k : World.ConflictKey C) : k ∈ detectL reg l₁ ↔ k ∈ detectL reg l₂ := by
  rw [mem_detectL, mem_detectL, World.detectList_congr reg l₁ l₂ h]

end Check
