/-
# World.Conflicts — disagreements as a pure function of the claim set

In plain words: two different claims about the same subject (same schema,
same subject key; their sources differ) are in conflict on an attribute when
each **states** a value for it and the values differ. `detect` returns the
set of (schema, subject, attribute) keys in conflict.

- **Coverage**: every such disagreement is detected.
- **Soundness**: everything detected is such a disagreement.
- **Order independence**: when the claims arrive as a list, the result
  depends only on which claims are in it, not on their order or on
  repetitions. EKOS's "last read wins" survivor has no counterpart: no claim is
  chosen over another.

Only what a schema's `stated` function returns is compared, so normalization
(for example `text` and `varchar` being the same type) lives in `stated`.

A concrete schema at the end — a table with typed columns — gives one
detected conflict and one non-conflict, both checked by `decide`.

This file imports Mathlib's `Finset`. Every name here is new to VerEKOS.
-/
import Mathlib.Data.Finset.Basic
import Mathlib.Data.Finset.Prod
import World.Claim

namespace World

set_option autoImplicit false

variable {C : Carriers} {P : C.SchemaId → Type} [∀ s, DecidableEq (P s)]
variable (reg : Registry C P)

/-- A conflict key: (schema, subject, attribute). There is at most one conflict
per key because the result of `detect` is a set of keys. -/
abbrev ConflictKey (C : Carriers) := C.SchemaId × List C.KeyPart × C.Digest

/-- What a claim states outright, through its schema. -/
def Claim.stated (c : Claim C P) : List (C.Digest × C.Digest) :=
  (reg c.key.schema).stated c.payload

/-- The attributes on which `c₁` states a value and `c₂` states a different
value. -/
def disagreeOn (c₁ c₂ : Claim C P) : List C.Digest :=
  (c₁.stated reg).filterMap fun av =>
    if (c₂.stated reg).any (fun bw => decide (bw.1 = av.1 ∧ bw.2 ≠ av.2)) then some av.1
    else none

/-- Same subject: same schema and same subject key (sources may differ). -/
def sameSubject (c₁ c₂ : Claim C P) : Prop :=
  c₁.key.schema = c₂.key.schema ∧ c₁.key.subject = c₂.key.subject

instance (c₁ c₂ : Claim C P) : Decidable (sameSubject c₁ c₂) := by
  unfold sameSubject; infer_instance

/-- The conflict keys of a claim set. -/
def detect (cs : Finset (Claim C P)) : Finset (ConflictKey C) :=
  ((cs ×ˢ cs).filter (fun p => p.1 ≠ p.2 ∧ sameSubject p.1 p.2)).biUnion fun p =>
    ((disagreeOn reg p.1 p.2).map fun a => (p.1.key.schema, p.1.key.subject, a)).toFinset

/-- `detect` on a list: its set of distinct claims. -/
def detectList (l : List (Claim C P)) : Finset (ConflictKey C) :=
  detect reg l.toFinset

omit [∀ s, DecidableEq (P s)] in
theorem mem_disagreeOn (c₁ c₂ : Claim C P) (a : C.Digest) :
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
    simp
    exact ⟨v₂, h₂, Ne.symm hne⟩

/-- **Exact characterization of `detect`.** A key is detected iff two
different claims in the set, about the same schema and subject, state
different values for that attribute. -/
theorem mem_detect (cs : Finset (Claim C P)) (k : ConflictKey C) :
    k ∈ detect reg cs ↔
      ∃ c₁ ∈ cs, ∃ c₂ ∈ cs, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
        ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧ v₁ ≠ v₂ ∧
          k = (c₁.key.schema, c₁.key.subject, a) := by
  unfold detect
  simp only [Finset.mem_biUnion, Finset.mem_filter, Finset.mem_product, List.mem_toFinset,
    List.mem_map, Prod.exists]
  constructor
  · rintro ⟨c₁, c₂, ⟨⟨h₁, h₂⟩, hne, hsame⟩, a, ha, rfl⟩
    obtain ⟨v₁, v₂, hv₁, hv₂, hv⟩ := (mem_disagreeOn reg c₁ c₂ a).mp ha
    exact ⟨c₁, h₁, c₂, h₂, hne, hsame, a, v₁, v₂, hv₁, hv₂, hv, rfl⟩
  · rintro ⟨c₁, h₁, c₂, h₂, hne, hsame, a, v₁, v₂, hv₁, hv₂, hv, rfl⟩
    exact ⟨c₁, c₂, ⟨⟨h₁, h₂⟩, hne, hsame⟩, a,
      (mem_disagreeOn reg c₁ c₂ a).mpr ⟨v₁, v₂, hv₁, hv₂, hv⟩, rfl⟩

/-- **Coverage.** Every disagreement between two different claims about the
same subject is detected, under the key (schema, subject, attribute). -/
theorem coverage (cs : Finset (Claim C P)) (c₁ c₂ : Claim C P)
    (h₁ : c₁ ∈ cs) (h₂ : c₂ ∈ cs) (hne : c₁ ≠ c₂) (hsame : sameSubject c₁ c₂)
    (a v₁ v₂ : C.Digest) (hv₁ : (a, v₁) ∈ c₁.stated reg) (hv₂ : (a, v₂) ∈ c₂.stated reg)
    (hv : v₁ ≠ v₂) : (c₁.key.schema, c₁.key.subject, a) ∈ detect reg cs :=
  (mem_detect reg cs _).mpr ⟨c₁, h₁, c₂, h₂, hne, hsame, a, v₁, v₂, hv₁, hv₂, hv, rfl⟩

/-- **Soundness.** Nothing is detected without two claims that disagree. -/
theorem soundness (cs : Finset (Claim C P)) (k : ConflictKey C) (hk : k ∈ detect reg cs) :
    ∃ c₁ ∈ cs, ∃ c₂ ∈ cs, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
      ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧ v₁ ≠ v₂ ∧
        k = (c₁.key.schema, c₁.key.subject, a) :=
  (mem_detect reg cs k).mp hk

/-- **Order independence.** Two lists with the same members (in any order,
with any repetitions) have the same conflicts. -/
theorem detectList_congr (l₁ l₂ : List (Claim C P)) (h : ∀ c, c ∈ l₁ ↔ c ∈ l₂) :
    detectList reg l₁ = detectList reg l₂ := by
  unfold detectList
  congr 1
  ext c
  simp [h c]

/-- **Permutation invariance**, the special case of reordering. -/
theorem detectList_perm (l₁ l₂ : List (Claim C P)) (h : l₁.Perm l₂) :
    detectList reg l₁ = detectList reg l₂ :=
  detectList_congr reg l₁ l₂ fun _ => h.mem_iff

/-- Adding claims never removes a conflict: what is detected stays detected
until one of the disagreeing claims leaves the set. -/
theorem detect_mono (cs cs' : Finset (Claim C P)) (h : cs ⊆ cs') :
    detect reg cs ⊆ detect reg cs' := by
  intro k hk
  obtain ⟨c₁, h₁, c₂, h₂, rest⟩ := (mem_detect reg cs k).mp hk
  exact (mem_detect reg cs' k).mpr ⟨c₁, h h₁, c₂, h h₂, rest⟩

/-- The pins of the conflict claim for key `k`: one claim pin, at its core,
for every claim in the set that states a value for the key's attribute about
the key's subject. -/
def conflictPins (d : ClaimIdDerivation C) (cs : Finset (Claim C P)) (k : ConflictKey C) :
    Finset (Pin C) :=
  (cs.filter (fun c => c.key.schema = k.1 ∧ c.key.subject = k.2.1 ∧
      (c.stated reg).any (fun av => decide (av.1 = k.2.2)) = true)).image
    fun c => ⟨.claim (c.id d), .core (c.core reg), 1000⟩

/-! ## A concrete schema: tables with typed columns

Carriers are natural numbers; there is one schema, `table`. A table payload is
a list of (column, type) codes. `stated` normalizes the type, so `text` and
`varchar` count as one type, and states each column's normalized type. -/

namespace Example

/-- The one schema of the example. -/
inductive Sch where
  | table
  deriving DecidableEq, Repr

/-- Carriers for the example. A claim id is (subject, sources); with one
schema that pair determines the key. -/
def C₀ : Carriers where
  SchemaId := Sch
  SourceId := Nat
  Range := Nat
  Digest := Nat
  Time := Nat
  RunId := Nat
  Stage := Nat
  KeyPart := Nat
  AtomRev := Nat
  Name := Nat
  ClaimId := List Nat × List Nat
  decSchemaId := inferInstanceAs (DecidableEq Sch)
  decSourceId := inferInstanceAs (DecidableEq Nat)
  decRange := inferInstanceAs (DecidableEq Nat)
  decDigest := inferInstanceAs (DecidableEq Nat)
  decTime := inferInstanceAs (DecidableEq Nat)
  decKeyPart := inferInstanceAs (DecidableEq Nat)
  decAtomRev := inferInstanceAs (DecidableEq Nat)
  decName := inferInstanceAs (DecidableEq Nat)
  decClaimId := inferInstanceAs (DecidableEq (List Nat × List Nat))

/-- A table payload: (column, type) pairs. -/
abbrev Cols : C₀.SchemaId → Type := fun _ => List (Nat × Nat)

instance (s : C₀.SchemaId) : DecidableEq (Cols s) :=
  inferInstanceAs (DecidableEq (List (Nat × Nat)))

-- Codes. Subjects:
def customers : Nat := 1
-- Columns:
def colId : Nat := 10
def colEmail : Nat := 11
-- Types:
def tInt : Nat := 100
def tVarchar : Nat := 101
def tText : Nat := 102
-- Source files:
def fileA : Nat := 1000
def fileB : Nat := 1001
def fileC : Nat := 1002

/-- Type normalization: `text` is `varchar`. -/
def normType (t : Nat) : Nat := if t = tText then tVarchar else t

/-- The table schema. The core digest is a stand-in (the column count); no
theorem here depends on it. -/
def tableSchema : Schema C₀ Cols Sch.table where
  core := fun cols => cols.length
  structural := false
  initial := .observed
  isFact := fun _ => true
  mayDecide := fun k _ => k == .human
  stated := fun cols => cols.map fun ct => (ct.1, normType ct.2)

def reg₀ : Registry C₀ Cols := fun | .table => tableSchema

/-- A table claim about `customers` from one source file. -/
def tableClaim (file : Nat) (cols : List (Nat × Nat)) : Claim C₀ Cols where
  key := ⟨Sch.table, [customers], [file]⟩
  payload := cols
  pins := [⟨.source file none, .atoms [], 1000⟩]
  valid := ⟨none, none⟩

/-- File A: `email varchar`. -/
def cA : Claim C₀ Cols := tableClaim fileA [(colId, tInt), (colEmail, tVarchar)]
/-- File B: `email int` — a real disagreement with A. -/
def cB : Claim C₀ Cols := tableClaim fileB [(colId, tInt), (colEmail, tInt)]
/-- File C: `email text` — the same type as A after normalization. -/
def cC : Claim C₀ Cols := tableClaim fileC [(colEmail, tText)]

/-- A and B conflict on `customers.email`. -/
example : (Sch.table, [customers], colEmail) ∈ detect reg₀ {cA, cB} := by decide

/-- The conflict is on `email` only, not on `id`. -/
example : detect reg₀ {cA, cB} = {(Sch.table, [customers], colEmail)} := by decide

/-- A and C do not conflict: `text` and `varchar` normalize to one type. -/
example : detect reg₀ {cA, cC} = ∅ := by decide

/-- With all three, the conflict is still the one key. -/
example : detectList reg₀ [cC, cB, cA, cB] = {(Sch.table, [customers], colEmail)} := by decide

end Example

end World
