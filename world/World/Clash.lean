/-
# World.Clash — conflicts under a per-schema clash relation

`World.Conflicts.detect` flags two claims when they state *different*
values for an attribute. EKOS's label-mismatch rule is a different relation
(`/Users/ember/dev/EKOS/ekos/crates/semantic/src/conflicts.rs:379-441`, with
`label_words` at `:355-371`). Two labels of one `EnumMeaning` conflict iff
their **source sets are disjoint** and their **word sets are disjoint**. That
is not "different after normalization": `asset account` and `asset` differ,
but share a word, so EKOS sees no conflict (lane B, `notes/B-check.md` F1).

This file follows lane B's proposal, made additive so that no existing
definition changes:
- A **clash table** gives each schema a relation on (sources, value) pairs.
  The sources are the claim's `ClaimKey.sources`.
- `detectBy κ` is `detect` with `κ` in place of `≠`.
- `Clash.differ` is the default: values differ. Under it `detectBy` is
  exactly `detect` (`detectBy_differ`), so every theorem about `detect` is
  the default instance.
- `coverage`, `soundness`, order independence and monotonicity are re-proved
  for any clash table. `detectList_congr` is untouched.
- `labelClash` implements EKOS's rule for one schema and the default for
  every other. `mem_detectBy_label` states exactly what it detects.

Symmetry of the clash relation is not needed. `detectBy` tries every ordered
pair of claims, so a relation that holds one way round is found.

Every name here is new to VerEKOS.
-/
import World.Conflicts

namespace World

set_option autoImplicit false

variable {C : Carriers} {P : C.SchemaId → Type} [∀ s, DecidableEq (P s)]
variable (reg : Registry C P)

/-- A clash table: for each schema, when two (sources, value) pairs clash. -/
abbrev Clash (C : Carriers) :=
  C.SchemaId → (List C.SourceId × C.Digest) → (List C.SourceId × C.Digest) → Bool

/-- The default: values differ. -/
def Clash.differ : Clash C := fun _ x y => decide (x.2 ≠ y.2)

variable (κ : Clash C)

/-- The attributes on which `c₁` states a value that clashes with one `c₂`
states. -/
def disagreeOnBy (c₁ c₂ : Claim C P) : List C.Digest :=
  (c₁.stated reg).filterMap fun av =>
    if (c₂.stated reg).any (fun bw => decide (bw.1 = av.1) &&
        κ c₁.key.schema (c₁.key.sources, av.2) (c₂.key.sources, bw.2))
    then some av.1 else none

/-- The conflict keys of a claim set under `κ`. -/
def detectBy (cs : Finset (Claim C P)) : Finset (ConflictKey C) :=
  ((cs ×ˢ cs).filter (fun p => p.1 ≠ p.2 ∧ sameSubject p.1 p.2)).biUnion fun p =>
    ((disagreeOnBy reg κ p.1 p.2).map fun a => (p.1.key.schema, p.1.key.subject, a)).toFinset

/-- `detectBy` on a list: its set of distinct claims. -/
def detectListBy (l : List (Claim C P)) : Finset (ConflictKey C) :=
  detectBy reg κ l.toFinset

omit [∀ s, DecidableEq (P s)] in
theorem mem_disagreeOnBy (c₁ c₂ : Claim C P) (a : C.Digest) :
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

/-- **Exact characterization of `detectBy`.** -/
theorem mem_detectBy (cs : Finset (Claim C P)) (k : ConflictKey C) :
    k ∈ detectBy reg κ cs ↔
      ∃ c₁ ∈ cs, ∃ c₂ ∈ cs, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
        ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧
          κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, v₂) = true ∧
          k = (c₁.key.schema, c₁.key.subject, a) := by
  unfold detectBy
  simp only [Finset.mem_biUnion, Finset.mem_filter, Finset.mem_product, List.mem_toFinset,
    List.mem_map, Prod.exists]
  constructor
  · rintro ⟨c₁, c₂, ⟨⟨h₁, h₂⟩, hne, hsame⟩, a, ha, rfl⟩
    obtain ⟨v₁, v₂, hv₁, hv₂, hk⟩ := (mem_disagreeOnBy reg κ c₁ c₂ a).mp ha
    exact ⟨c₁, h₁, c₂, h₂, hne, hsame, a, v₁, v₂, hv₁, hv₂, hk, rfl⟩
  · rintro ⟨c₁, h₁, c₂, h₂, hne, hsame, a, v₁, v₂, hv₁, hv₂, hk, rfl⟩
    exact ⟨c₁, c₂, ⟨⟨h₁, h₂⟩, hne, hsame⟩, a,
      (mem_disagreeOnBy reg κ c₁ c₂ a).mpr ⟨v₁, v₂, hv₁, hv₂, hk⟩, rfl⟩

/-- **Coverage** under any clash table. -/
theorem coverageBy (cs : Finset (Claim C P)) (c₁ c₂ : Claim C P)
    (h₁ : c₁ ∈ cs) (h₂ : c₂ ∈ cs) (hne : c₁ ≠ c₂) (hsame : sameSubject c₁ c₂)
    (a v₁ v₂ : C.Digest) (hv₁ : (a, v₁) ∈ c₁.stated reg) (hv₂ : (a, v₂) ∈ c₂.stated reg)
    (hk : κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, v₂) = true) :
    (c₁.key.schema, c₁.key.subject, a) ∈ detectBy reg κ cs :=
  (mem_detectBy reg κ cs _).mpr ⟨c₁, h₁, c₂, h₂, hne, hsame, a, v₁, v₂, hv₁, hv₂, hk, rfl⟩

/-- **Soundness** under any clash table. -/
theorem soundnessBy (cs : Finset (Claim C P)) (k : ConflictKey C) (hk : k ∈ detectBy reg κ cs) :
    ∃ c₁ ∈ cs, ∃ c₂ ∈ cs, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
      ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧
        κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, v₂) = true ∧
        k = (c₁.key.schema, c₁.key.subject, a) :=
  (mem_detectBy reg κ cs k).mp hk

/-- **Order independence** under any clash table. -/
theorem detectListBy_congr (l₁ l₂ : List (Claim C P)) (h : ∀ c, c ∈ l₁ ↔ c ∈ l₂) :
    detectListBy reg κ l₁ = detectListBy reg κ l₂ := by
  unfold detectListBy
  congr 1
  ext c
  simp [h c]

theorem detectListBy_perm (l₁ l₂ : List (Claim C P)) (h : l₁.Perm l₂) :
    detectListBy reg κ l₁ = detectListBy reg κ l₂ :=
  detectListBy_congr reg κ l₁ l₂ fun _ => h.mem_iff

/-- **Monotonicity** under any clash table. -/
theorem detectBy_mono (cs cs' : Finset (Claim C P)) (h : cs ⊆ cs') :
    detectBy reg κ cs ⊆ detectBy reg κ cs' := by
  intro k hk
  obtain ⟨c₁, h₁, c₂, h₂, rest⟩ := (mem_detectBy reg κ cs k).mp hk
  exact (mem_detectBy reg κ cs' k).mpr ⟨c₁, h₁ |> h, c₂, h h₂, rest⟩

omit [∀ s, DecidableEq (P s)] in
/-- The default table gives the old `disagreeOn`. -/
theorem disagreeOnBy_differ (c₁ c₂ : Claim C P) :
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

/-- **The default clash table is exactly `detect`.** Every theorem about
`detect` is the default instance of the theorems here. -/
theorem detectBy_differ (cs : Finset (Claim C P)) : detectBy reg Clash.differ cs = detect reg cs := by
  unfold detectBy detect
  simp only [disagreeOnBy_differ]

/-! ## EKOS's label-mismatch rule -/

/-- Two lists share no element. -/
def disjointB {α : Type} [DecidableEq α] (l₁ l₂ : List α) : Bool :=
  l₁.all fun a => !(l₂.contains a)

theorem disjointB_iff {α : Type} [DecidableEq α] (l₁ l₂ : List α) :
    disjointB l₁ l₂ = true ↔ ∀ a ∈ l₁, a ∉ l₂ := by
  simp [disjointB, List.all_eq_true]

/-- EKOS's rule for the schema `label` (word sets read off a value by
`wordsOf`, standing in for `label_words`): clash iff the source sets are
disjoint and the word sets are disjoint. Every other schema keeps the
default. -/
def labelClash (label : C.SchemaId) (wordsOf : C.Digest → List C.KeyPart) : Clash C :=
  fun s x y =>
    if s = label then disjointB x.1 y.1 && disjointB (wordsOf x.2) (wordsOf y.2)
    else decide (x.2 ≠ y.2)

/-- **What the label rule detects.** A key of the label schema is detected
iff two different claims about the same subject state labels for that
attribute whose source sets share no source and whose word sets share no
word. -/
theorem mem_detectBy_label (label : C.SchemaId) (wordsOf : C.Digest → List C.KeyPart)
    (cs : Finset (Claim C P)) (subj : List C.KeyPart) (a : C.Digest) :
    (label, subj, a) ∈ detectBy reg (labelClash label wordsOf) cs ↔
      ∃ c₁ ∈ cs, ∃ c₂ ∈ cs, c₁ ≠ c₂ ∧ c₁.key.schema = label ∧ c₂.key.schema = label ∧
        c₁.key.subject = subj ∧ c₂.key.subject = subj ∧
        ∃ v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧
          (∀ s ∈ c₁.key.sources, s ∉ c₂.key.sources) ∧
          (∀ w ∈ wordsOf v₁, w ∉ wordsOf v₂) := by
  rw [mem_detectBy]
  constructor
  · rintro ⟨c₁, h₁, c₂, h₂, hne, ⟨hs, hsub⟩, a', v₁, v₂, hv₁, hv₂, hk, hkey⟩
    simp only [Prod.mk.injEq] at hkey
    obtain ⟨hl, hsubj, rfl⟩ := hkey
    subst hl
    unfold labelClash at hk
    simp only [if_true, Bool.and_eq_true, disjointB_iff] at hk
    exact ⟨c₁, h₁, c₂, h₂, hne, rfl, hs.symm, hsubj.symm, hsub ▸ hsubj.symm, v₁, v₂, hv₁, hv₂,
      hk.1, hk.2⟩
  · rintro ⟨c₁, h₁, c₂, h₂, hne, hl₁, hl₂, hsub₁, hsub₂, v₁, v₂, hv₁, hv₂, hsrc, hw⟩
    refine ⟨c₁, h₁, c₂, h₂, hne, ⟨hl₁.trans hl₂.symm, hsub₁.trans hsub₂.symm⟩, a, v₁, v₂, hv₁,
      hv₂, ?_, by rw [hl₁, hsub₁]⟩
    unfold labelClash
    rw [if_pos hl₁]
    simp only [Bool.and_eq_true, disjointB_iff]
    exact ⟨hsrc, hw⟩

/-! ## Example: the label rule firing and not firing -/

namespace ClashExample

/-- Carriers: one schema; everything else numbers. -/
def C₁ : Carriers where
  SchemaId := Unit
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
  decSchemaId := inferInstanceAs (DecidableEq Unit)
  decSourceId := inferInstanceAs (DecidableEq Nat)
  decRange := inferInstanceAs (DecidableEq Nat)
  decDigest := inferInstanceAs (DecidableEq Nat)
  decTime := inferInstanceAs (DecidableEq Nat)
  decKeyPart := inferInstanceAs (DecidableEq Nat)
  decAtomRev := inferInstanceAs (DecidableEq Nat)
  decName := inferInstanceAs (DecidableEq Nat)
  decClaimId := inferInstanceAs (DecidableEq (List Nat × List Nat))

/-- A payload: (attribute, label) pairs. -/
abbrev Pay : C₁.SchemaId → Type := fun _ => List (Nat × Nat)

instance (s : C₁.SchemaId) : DecidableEq (Pay s) :=
  inferInstanceAs (DecidableEq (List (Nat × Nat)))

/-- The `EnumMeaning` schema: it states its labels. -/
def enumMeaning : Schema C₁ Pay () where
  core := fun _ => (0 : Nat)
  structural := false
  initial := .hypothesis
  isFact := fun _ => true
  mayDecide := fun k _ => k == .human
  stated := fun xs => xs

def reg₁ : Registry C₁ Pay := fun _ => enumMeaning

-- Codes. The attribute "label":
def attrLabel : Nat := 1
-- Labels: 10 = "asset account", 11 = "asset", 12 = "liability".
def lAssetAccount : Nat := 10
def lAsset : Nat := 11
def lLiability : Nat := 12
-- Words: 100 = asset, 101 = account, 102 = liability.
def wordsOf₁ (v : C₁.Digest) : List C₁.KeyPart :=
  if v = (10 : Nat) then [(100 : Nat), (101 : Nat)]
  else if v = (11 : Nat) then [(100 : Nat)]
  else if v = (12 : Nat) then [(102 : Nat)] else []
-- Sources.
def srcComment : Nat := 1
def srcCase : Nat := 2

def κ₁ : Clash C₁ := labelClash () wordsOf₁

/-- One label of the `EnumMeaning` for subject 7, asserted by `srcs`. -/
def lbl (srcs : List Nat) (v : Nat) : Claim C₁ Pay where
  key := ⟨(), [(7 : Nat)], srcs⟩
  payload := [(attrLabel, v)]
  pins := [⟨.source (srcs.headD 0) none, .atoms [], 1000⟩]
  valid := ⟨none, none⟩

def k₁ : ConflictKey C₁ := ((), [(7 : Nat)], (1 : Nat))

/-- `asset account` vs `asset`, from two sources: they share a word, so no
conflict — though plain `≠` would say there is one. -/
example : detectBy reg₁ κ₁ {lbl [srcComment] lAssetAccount, lbl [srcCase] lAsset} = ∅ := by decide
example : k₁ ∈ detect reg₁ {lbl [srcComment] lAssetAccount, lbl [srcCase] lAsset} := by decide

/-- `asset` vs `liability`, from two sources: a conflict. -/
example : detectBy reg₁ κ₁ {lbl [srcComment] lAsset, lbl [srcCase] lLiability} = {k₁} := by decide

/-- A label shared by both sources, and a second label from one of them: the
source sets meet, so no conflict. -/
example : detectBy reg₁ κ₁ {lbl [srcComment, srcCase] lAsset, lbl [srcComment] lLiability} = ∅ := by
  decide

/-- Two labels with no source at all: empty source sets are disjoint, so a
conflict, as in EKOS. -/
example : detectBy reg₁ κ₁ {lbl [] lAsset, lbl [] lLiability} = {k₁} := by decide

end ClashExample

end World
