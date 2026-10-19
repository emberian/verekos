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
import World.ClashCore

namespace World

set_option autoImplicit false

section generic

variable [C : Carriers] {P : C.SchemaId → Type} [∀ s, DecidableEq (P s)]
variable (reg : Registry P)

variable (κ : Clash)

/-- The conflict keys of a claim set under `κ`. -/
def detectBy (cs : Finset (Claim P)) : Finset (ConflictKey) :=
  ((cs ×ˢ cs).filter (fun p => p.1 ≠ p.2 ∧ sameSubject p.1 p.2)).biUnion fun p =>
    ((disagreeOnBy reg κ p.1 p.2).map fun a => (p.1.key.schema, p.1.key.subject, a)).toFinset

/-- `detectBy` on a list: its set of distinct claims. -/
def detectListBy (l : List (Claim P)) : Finset (ConflictKey) :=
  detectBy reg κ l.toFinset

/-- **Exact characterization of `detectBy`.** -/
theorem mem_detectBy (cs : Finset (Claim P)) (k : ConflictKey) :
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

/-- **The list detector of `WorldCore` computes `detectListBy`.** -/
theorem detectLBy_toFinset (l : List (Claim P)) :
    (detectLBy reg κ l).toFinset = detectListBy reg κ l := by
  ext k
  rw [List.mem_toFinset, mem_detectLBy, detectListBy, mem_detectBy]
  simp only [List.mem_toFinset]

/-- **Coverage** under any clash table. -/
theorem coverageBy (cs : Finset (Claim P)) (c₁ c₂ : Claim P)
    (h₁ : c₁ ∈ cs) (h₂ : c₂ ∈ cs) (hne : c₁ ≠ c₂) (hsame : sameSubject c₁ c₂)
    (a v₁ v₂ : C.Digest) (hv₁ : (a, v₁) ∈ c₁.stated reg) (hv₂ : (a, v₂) ∈ c₂.stated reg)
    (hk : κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, v₂) = true) :
    (c₁.key.schema, c₁.key.subject, a) ∈ detectBy reg κ cs :=
  (mem_detectBy reg κ cs _).mpr ⟨c₁, h₁, c₂, h₂, hne, hsame, a, v₁, v₂, hv₁, hv₂, hk, rfl⟩

/-- **Soundness** under any clash table. -/
theorem soundnessBy (cs : Finset (Claim P)) (k : ConflictKey) (hk : k ∈ detectBy reg κ cs) :
    ∃ c₁ ∈ cs, ∃ c₂ ∈ cs, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
      ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧
        κ c₁.key.schema (c₁.key.sources, v₁) (c₂.key.sources, v₂) = true ∧
        k = (c₁.key.schema, c₁.key.subject, a) :=
  (mem_detectBy reg κ cs k).mp hk

/-- **Order independence** under any clash table. -/
theorem detectListBy_congr (l₁ l₂ : List (Claim P)) (h : ∀ c, c ∈ l₁ ↔ c ∈ l₂) :
    detectListBy reg κ l₁ = detectListBy reg κ l₂ := by
  unfold detectListBy
  congr 1
  ext c
  simp [h c]

theorem detectListBy_perm (l₁ l₂ : List (Claim P)) (h : l₁.Perm l₂) :
    detectListBy reg κ l₁ = detectListBy reg κ l₂ :=
  detectListBy_congr reg κ l₁ l₂ fun _ => h.mem_iff

/-- **Monotonicity** under any clash table. -/
theorem detectBy_mono (cs cs' : Finset (Claim P)) (h : cs ⊆ cs') :
    detectBy reg κ cs ⊆ detectBy reg κ cs' := by
  intro k hk
  obtain ⟨c₁, h₁, c₂, h₂, rest⟩ := (mem_detectBy reg κ cs k).mp hk
  exact (mem_detectBy reg κ cs' k).mpr ⟨c₁, h₁ |> h, c₂, h h₂, rest⟩

/-- **The default clash table is exactly `detect`.** Every theorem about
`detect` is the default instance of the theorems here. -/
theorem detectBy_differ (cs : Finset (Claim P)) : detectBy reg Clash.differ cs = detect reg cs := by
  unfold detectBy detect
  simp only [disagreeOnBy_differ]

/-! ## EKOS's label-mismatch rule -/

/-- **What the label rule detects.** A key of the label schema is detected
iff two different claims about the same subject state labels for that
attribute whose source sets share no source and whose word sets share no
word. -/
theorem mem_detectBy_label (label : C.SchemaId) (wordsOf : C.Digest → List C.KeyPart)
    (cs : Finset (Claim P)) (subj : List C.KeyPart) (a : C.Digest) :
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

end generic

/-! ## Example: the label rule firing and not firing -/

namespace ClashExample

/-- Carriers: one schema; everything else numbers. -/
scoped instance C₁ : Carriers where
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
def enumMeaning : Schema Pay () where
  core := fun _ => (0 : Nat)
  structural := false
  initial := .hypothesis
  isFact := fun _ => true
  mayDecide := fun k _ => k == .human
  stated := fun xs => xs

def reg₁ : Registry Pay := fun _ => enumMeaning

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

def κ₁ : Clash := labelClash () wordsOf₁

/-- One label of the `EnumMeaning` for subject 7, asserted by `srcs`. -/
def lbl (srcs : List Nat) (v : Nat) : Claim Pay where
  key := ⟨(), [(7 : Nat)], srcs⟩
  payload := [(attrLabel, v)]
  pins := [⟨.source (srcs.headD 0) none, .atoms [], 1000⟩]
  valid := ⟨none, none⟩

def k₁ : ConflictKey := ((), [(7 : Nat)], (1 : Nat))

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
