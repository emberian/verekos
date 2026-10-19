/-
# CheckProofs.DetectBy — the runner's clash path is the model's

Imports Mathlib (through `World.Clash`). Built, never linked.
-/
import World.Clash
import Check.Detect
import Check.DetectBy

namespace Check

set_option autoImplicit false

variable {C : World.Carriers} {P : C.SchemaId → Type} [∀ s, DecidableEq (P s)]
variable (reg : World.Registry C P) (κ : World.Clash C)

omit [∀ s, DecidableEq (P s)] in
theorem disagreeOnByL_eq (c₁ c₂ : World.Claim C P) :
    disagreeOnByL reg κ c₁ c₂ = World.disagreeOnBy reg κ c₁ c₂ := rfl

theorem disjointBL_eq {α : Type} [DecidableEq α] (l₁ l₂ : List α) :
    disjointBL l₁ l₂ = World.disjointB l₁ l₂ := rfl

theorem labelClashL_eq (label : C.SchemaId) (wordsOf : C.Digest → List C.KeyPart) :
    labelClashL label wordsOf = World.labelClash label wordsOf := rfl

/-- **The runner computes the model under any clash table.** -/
theorem mem_detectLBy (l : List (World.Claim C P)) (k : World.ConflictKey C) :
    k ∈ detectLBy reg κ l ↔ k ∈ World.detectListBy reg κ l := by
  unfold World.detectListBy
  rw [World.mem_detectBy]
  simp only [detectLBy, List.mem_flatMap, List.mem_toFinset]
  constructor
  · rintro ⟨c₁, h₁, c₂, h₂, hk⟩
    split at hk
    · rename_i hc
      obtain ⟨hne, hs, hsub⟩ := hc
      rw [List.mem_map] at hk
      obtain ⟨a, ha, rfl⟩ := hk
      rw [disagreeOnByL_eq, World.mem_disagreeOnBy] at ha
      obtain ⟨v₁, v₂, hv₁, hv₂, hκ⟩ := ha
      exact ⟨c₁, h₁, c₂, h₂, hne, ⟨hs, hsub⟩, a, v₁, v₂, hv₁, hv₂, hκ, rfl⟩
    · simp at hk
  · rintro ⟨c₁, h₁, c₂, h₂, hne, ⟨hs, hsub⟩, a, v₁, v₂, hv₁, hv₂, hκ, rfl⟩
    refine ⟨c₁, h₁, c₂, h₂, ?_⟩
    rw [if_pos ⟨hne, hs, hsub⟩, List.mem_map]
    exact ⟨a, (by rw [disagreeOnByL_eq, World.mem_disagreeOnBy]; exact ⟨v₁, v₂, hv₁, hv₂, hκ⟩), rfl⟩

theorem detectLBy_toFinset (l : List (World.Claim C P)) :
    (detectLBy reg κ l).toFinset = World.detectListBy reg κ l := by
  ext k
  rw [List.mem_toFinset, mem_detectLBy]

/-- With the label table, the runner's keys are exactly the model's label
rule (`World.mem_detectBy_label`) on the same claims. -/
theorem mem_detectLBy_label (label : C.SchemaId) (wordsOf : C.Digest → List C.KeyPart)
    (l : List (World.Claim C P)) (k : World.ConflictKey C) :
    k ∈ detectLBy reg (labelClashL label wordsOf) l ↔
      k ∈ World.detectListBy reg (World.labelClash label wordsOf) l := by
  rw [labelClashL_eq, mem_detectLBy]

end Check
