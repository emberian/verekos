/-
# Check.DetectBy — `World.detectListBy` and `World.labelClash` without Mathlib

`World/Clash.lean` (world `12e5543`) states conflicts under a per-schema
clash table `κ` (`detectBy`, `detectListBy`) and EKOS's label-mismatch rule
as one such table (`labelClash`: source sets disjoint and word sets
disjoint). It imports Mathlib, so this file copies `disagreeOnBy`,
`disjointB` and `labelClash` word for word and walks pairs over a `List`, as
`Check.detectL` does for `detect`. `CheckProofs.DetectBy` proves
`k ∈ detectLBy reg κ l ↔ k ∈ World.detectListBy reg κ l` and that the
copies equal the model's definitions. Built, never linked.
-/
import Check.Detect

namespace Check

set_option autoImplicit false

variable {C : World.Carriers} {P : C.SchemaId → Type} [∀ s, DecidableEq (P s)]
variable (reg : World.Registry C P)

/-- `World.Clash`, restated: per schema, when two (sources, value) pairs clash. -/
abbrev ClashL (C : World.Carriers) :=
  C.SchemaId → (List C.SourceId × C.Digest) → (List C.SourceId × C.Digest) → Bool

variable (κ : ClashL C)

/-- `World.disagreeOnBy`, copied. -/
def disagreeOnByL (c₁ c₂ : World.Claim C P) : List C.Digest :=
  (statedL reg c₁).filterMap fun av =>
    if (statedL reg c₂).any (fun bw => decide (bw.1 = av.1) &&
        κ c₁.key.schema (c₁.key.sources, av.2) (c₂.key.sources, bw.2))
    then some av.1 else none

/-- `World.detectListBy`, over lists. -/
def detectLBy (l : List (World.Claim C P)) : List (C.SchemaId × List C.KeyPart × C.Digest) :=
  l.flatMap fun c₁ => l.flatMap fun c₂ =>
    if c₁ ≠ c₂ ∧ c₁.key.schema = c₂.key.schema ∧ c₁.key.subject = c₂.key.subject then
      (disagreeOnByL reg κ c₁ c₂).map fun a => (c₁.key.schema, c₁.key.subject, a)
    else []

/-- `World.disjointB`, copied. -/
def disjointBL {α : Type} [DecidableEq α] (l₁ l₂ : List α) : Bool :=
  l₁.all fun a => !(l₂.contains a)

/-- `World.labelClash`, copied. -/
def labelClashL (label : C.SchemaId) (wordsOf : C.Digest → List C.KeyPart) : ClashL C :=
  fun s x y =>
    if s = label then disjointBL x.1 y.1 && disjointBL (wordsOf x.2) (wordsOf y.2)
    else decide (x.2 ≠ y.2)

end Check
