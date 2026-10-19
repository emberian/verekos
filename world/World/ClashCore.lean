/-
# World.ClashCore — the clash table and the label rule over lists (Mathlib-free)

The parts of `World.Clash` that need no Mathlib, for `WorldCore`: `Clash`,
`Clash.differ`, `disagreeOnBy`, `disjointB`, `labelClash` (moved here
unchanged), and **`detectLBy`**, detection under a clash table over a list.
`World.Clash` proves `(detectLBy reg κ l).toFinset = detectListBy reg κ l`
(`detectLBy_toFinset`).

Every name here is new to VerEKOS.
-/
import World.ConflictsCore

namespace World

set_option autoImplicit false

variable [C : Carriers] {P : C.SchemaId → Type} [∀ s, DecidableEq (P s)]
variable (reg : Registry P)

/-- A clash table: for each schema, when two (sources, value) pairs clash. -/
abbrev Clash [C : Carriers] :=
  C.SchemaId → (List C.SourceId × C.Digest) → (List C.SourceId × C.Digest) → Bool

/-- The default: values differ. -/
def Clash.differ : Clash := fun _ x y => decide (x.2 ≠ y.2)

variable (κ : Clash)

/-- The attributes on which `c₁` states a value that clashes with one `c₂`
states. -/
def disagreeOnBy (c₁ c₂ : Claim P) : List C.Digest :=
  (c₁.stated reg).filterMap fun av =>
    if (c₂.stated reg).any (fun bw => decide (bw.1 = av.1) &&
        κ c₁.key.schema (c₁.key.sources, av.2) (c₂.key.sources, bw.2))
    then some av.1 else none

omit [∀ s, DecidableEq (P s)] in
theorem mem_disagreeOnBy (c₁ c₂ : Claim P) (a : C.Digest) :
    a ∈ disagreeOnBy reg κ c₁ c₂ ↔
      ∃ v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧
        κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, v₂) = true := by
  unfold disagreeOnBy
  rw [List.mem_filterMap]
  constructor
  · rintro ⟨⟨a', v₁⟩, hmem, hsome⟩
    split at hsome
    · rename_i hany
      simp only [Option.some.injEq] at hsome
      subst hsome
      rw [List.any_eq_true] at hany
      obtain ⟨⟨b, w⟩, hbw, hdec⟩ := hany
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hdec
      obtain ⟨rfl, hk⟩ := hdec
      exact ⟨v₁, w, hmem, hbw, hk⟩
    · exact absurd hsome (by simp)
  · rintro ⟨v₁, v₂, h₁, h₂, hk⟩
    refine ⟨(a, v₁), h₁, ?_⟩
    have : (c₂.stated reg).any (fun bw => decide (bw.1 = a) &&
        κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, bw.2)) = true := by
      rw [List.any_eq_true]
      exact ⟨(a, v₂), h₂, by simp [hk]⟩
    simp only at this ⊢
    rw [if_pos this]

omit [∀ s, DecidableEq (P s)] in
/-- The default table gives the old `disagreeOn`. -/
theorem disagreeOnBy_differ (c₁ c₂ : Claim P) :
    disagreeOnBy reg Clash.differ c₁ c₂ = disagreeOn reg c₁ c₂ := by
  unfold disagreeOnBy disagreeOn Clash.differ
  have key : ∀ av bw : C.Digest × C.Digest,
      (decide (bw.1 = av.1) && decide ((c₁.key.sources, av.2).2 ≠ (c₂.key.sources, bw.2).2)) =
        decide (bw.1 = av.1 ∧ bw.2 ≠ av.2) := by
    intro av bw
    by_cases h1 : bw.1 = av.1 <;> by_cases h2 : bw.2 = av.2
    · simp [h1, h2]
    · have : ¬ av.2 = bw.2 := fun h => h2 h.symm
      simp [h1, h2, this]
    · simp [h1, h2]
    · have : ¬ av.2 = bw.2 := fun h => h2 h.symm
      simp [h1, h2, this]
  simp only [key]

/-! ## EKOS's label-mismatch rule -/

/-- Two lists share no element. -/
def disjointB {α : Type} [DecidableEq α] (l₁ l₂ : List α) : Bool :=
  l₁.all fun a => !(l₂.contains a)

omit C in
theorem disjointB_iff {α : Type} [DecidableEq α] (l₁ l₂ : List α) :
    disjointB l₁ l₂ = true ↔ ∀ a ∈ l₁, a ∉ l₂ := by
  simp [disjointB, List.all_eq_true]

/-- EKOS's rule for the schema `label` (word sets read off a value by
`wordsOf`, standing in for `label_words`): clash iff the source sets are
disjoint and the word sets are disjoint. Every other schema keeps the
default. -/
def labelClash (label : C.SchemaId) (wordsOf : C.Digest → List C.KeyPart) : Clash :=
  fun s x y =>
    if s = label then disjointB x.1 y.1 && disjointB (wordsOf x.2) (wordsOf y.2)
    else decide (x.2 ≠ y.2)

/-- Detection under a clash table, over a list. -/
def detectLBy (l : List (Claim P)) : List (ConflictKey) :=
  l.flatMap fun c₁ => l.flatMap fun c₂ =>
    if c₁ ≠ c₂ ∧ sameSubject c₁ c₂ then
      (disagreeOnBy reg κ c₁ c₂).map fun a => (c₁.key.schema, c₁.key.subject, a)
    else []

/-- **Exact characterization of `detectLBy`**, the same as `mem_detectBy`'s. -/
theorem mem_detectLBy (l : List (Claim P)) (k : ConflictKey) :
    k ∈ detectLBy reg κ l ↔
      ∃ c₁ ∈ l, ∃ c₂ ∈ l, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
        ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧
          κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, v₂) = true ∧
          k = (c₁.key.schema, c₁.key.subject, a) := by
  unfold detectLBy
  simp only [List.mem_flatMap]
  constructor
  · rintro ⟨c₁, h₁, c₂, h₂, hk⟩
    split at hk
    · rename_i hc
      rw [List.mem_map] at hk
      obtain ⟨a, ha, rfl⟩ := hk
      obtain ⟨v₁, v₂, hv₁, hv₂, hv⟩ := (mem_disagreeOnBy reg κ c₁ c₂ a).mp ha
      exact ⟨c₁, h₁, c₂, h₂, hc.1, hc.2, a, v₁, v₂, hv₁, hv₂, hv, rfl⟩
    · cases hk
  · rintro ⟨c₁, h₁, c₂, h₂, hne, hsame, a, v₁, v₂, hv₁, hv₂, hv, rfl⟩
    refine ⟨c₁, h₁, c₂, h₂, ?_⟩
    rw [if_pos ⟨hne, hsame⟩, List.mem_map]
    exact ⟨a, (mem_disagreeOnBy reg κ c₁ c₂ a).mpr ⟨v₁, v₂, hv₁, hv₂, hv⟩, rfl⟩

end World
