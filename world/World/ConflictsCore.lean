/-
# World.ConflictsCore — conflict detection over lists (Mathlib-free)

The parts of `World.Conflicts` that need no Mathlib, for `WorldCore`:
`ConflictKey`, `Claim.stated`, `disagreeOn`, `sameSubject` (moved here
unchanged), and **`detectL`**, conflict detection over a list of claims,
returning a list of keys (possibly with repeats).

`World.Conflicts.detect` and `detectList` return a `Finset`, which is a
Mathlib type; they stay in `World`, unchanged. `World.Conflicts` proves
`(detectL reg l).toFinset = detectList reg l` (`detectL_toFinset`), so a
runner that imports only `WorldCore` computes the model's `detectList`.

Every name here is new to VerEKOS.
-/
import World.Claim

namespace World

set_option autoImplicit false

variable [C : Carriers] {P : C.SchemaId → Type} [∀ s, DecidableEq (P s)]
variable (reg : Registry P)

/-- A conflict key: (schema, subject, attribute). There is at most one conflict
per key because the result of `detect` is a set of keys. -/
abbrev ConflictKey [C : Carriers] := C.SchemaId × List C.KeyPart × C.Digest

/-- What a claim states outright, through its schema. -/
def Claim.stated (c : Claim P) : List (C.Digest × C.Digest) :=
  (reg c.key.schema).stated c.payload

/-- The attributes on which `c₁` states a value and `c₂` states a different
value. -/
def disagreeOn (c₁ c₂ : Claim P) : List C.Digest :=
  (c₁.stated reg).filterMap fun av =>
    if (c₂.stated reg).any (fun bw => decide (bw.1 = av.1 ∧ bw.2 ≠ av.2)) then some av.1
    else none

/-- Same subject: same schema and same subject key (sources may differ). -/
def sameSubject (c₁ c₂ : Claim P) : Prop :=
  c₁.key.schema = c₂.key.schema ∧ c₁.key.subject = c₂.key.subject

instance (c₁ c₂ : Claim P) : Decidable (sameSubject c₁ c₂) := by
  unfold sameSubject; infer_instance

omit [∀ s, DecidableEq (P s)] in
theorem mem_disagreeOn (c₁ c₂ : Claim P) (a : C.Digest) :
    a ∈ disagreeOn reg c₁ c₂ ↔
      ∃ v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧ v₁ ≠ v₂ := by
  unfold disagreeOn
  rw [List.mem_filterMap]
  constructor
  · rintro ⟨⟨a', v₁⟩, hmem, hsome⟩
    split at hsome
    · rename_i hany
      simp only [Option.some.injEq] at hsome
      subst hsome
      rw [List.any_eq_true] at hany
      obtain ⟨⟨b, w⟩, hbw, hdec⟩ := hany
      simp only [decide_eq_true_eq] at hdec
      obtain ⟨rfl, hne⟩ := hdec
      exact ⟨v₁, w, hmem, hbw, Ne.symm hne⟩
    · exact absurd hsome (by simp)
  · rintro ⟨v₁, v₂, h₁, h₂, hne⟩
    refine ⟨(a, v₁), h₁, ?_⟩
    have : (c₂.stated reg).any (fun bw => decide (bw.1 = a ∧ bw.2 ≠ v₁)) = true :=
      List.any_eq_true.mpr ⟨(a, v₂), h₂, by simp [Ne.symm hne]⟩
    rw [if_pos this]

/-- Conflict detection over a list: for every ordered pair of different
claims about the same subject, the keys of the attributes they disagree on. -/
def detectL (l : List (Claim P)) : List (ConflictKey) :=
  l.flatMap fun c₁ => l.flatMap fun c₂ =>
    if c₁ ≠ c₂ ∧ sameSubject c₁ c₂ then
      (disagreeOn reg c₁ c₂).map fun a => (c₁.key.schema, c₁.key.subject, a)
    else []

/-- **Exact characterization of `detectL`**, the same as `mem_detect`'s. -/
theorem mem_detectL (l : List (Claim P)) (k : ConflictKey) :
    k ∈ detectL reg l ↔
      ∃ c₁ ∈ l, ∃ c₂ ∈ l, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
        ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧ v₁ ≠ v₂ ∧
          k = (c₁.key.schema, c₁.key.subject, a) := by
  unfold detectL
  simp only [List.mem_flatMap]
  constructor
  · rintro ⟨c₁, h₁, c₂, h₂, hk⟩
    split at hk
    · rename_i hc
      rw [List.mem_map] at hk
      obtain ⟨a, ha, rfl⟩ := hk
      obtain ⟨v₁, v₂, hv₁, hv₂, hv⟩ := (mem_disagreeOn reg c₁ c₂ a).mp ha
      exact ⟨c₁, h₁, c₂, h₂, hc.1, hc.2, a, v₁, v₂, hv₁, hv₂, hv, rfl⟩
    · cases hk
  · rintro ⟨c₁, h₁, c₂, h₂, hne, hsame, a, v₁, v₂, hv₁, hv₂, hv, rfl⟩
    refine ⟨c₁, h₁, c₂, h₂, ?_⟩
    rw [if_pos ⟨hne, hsame⟩, List.mem_map]
    exact ⟨a, (mem_disagreeOn reg c₁ c₂ a).mpr ⟨v₁, v₂, hv₁, hv₂, hv⟩, rfl⟩

end World
