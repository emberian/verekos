/-
# Check.Detect — `World.detectList` without Mathlib

`World.detect` (`World/Conflicts.lean:63`) is stated over Mathlib's `Finset`,
so an executable that called it would compile and link Mathlib. This file
restates it over `List`, with no Mathlib import:

- `statedL`, `disagreeOnL` are `World.Claim.stated` and `World.disagreeOn`
  copied word for word (Conflicts.lean:39-48);
- `detectL` walks every ordered pair of claims in the list, as `detect` walks
  `cs ×ˢ cs`, and may repeat a key.

`CheckProofs.Detect` proves `k ∈ detectL reg l ↔ k ∈ World.detectList reg l`
(`mem_detectL`) and `(detectL reg l).toFinset = World.detectList reg l`, so the
runner's answer is the model's answer. That file imports Mathlib; it is built,
never linked into `verekos-check`.
-/
import World.Claim

namespace Check

set_option autoImplicit false

variable {C : World.Carriers} {P : C.SchemaId → Type} [∀ s, DecidableEq (P s)]
variable (reg : World.Registry C P)

/-- `World.Claim.stated`, copied. -/
def statedL (c : World.Claim C P) : List (C.Digest × C.Digest) :=
  (reg c.key.schema).stated c.payload

/-- `World.disagreeOn`, copied. -/
def disagreeOnL (c₁ c₂ : World.Claim C P) : List C.Digest :=
  (statedL reg c₁).filterMap fun av =>
    if (statedL reg c₂).any (fun bw => decide (bw.1 = av.1 ∧ bw.2 ≠ av.2)) then some av.1
    else none

/-- `World.detectList`, over lists: every ordered pair of different claims
about the same schema and subject, and each attribute they disagree on. -/
def detectL (l : List (World.Claim C P)) : List (C.SchemaId × List C.KeyPart × C.Digest) :=
  l.flatMap fun c₁ => l.flatMap fun c₂ =>
    if c₁ ≠ c₂ ∧ c₁.key.schema = c₂.key.schema ∧ c₁.key.subject = c₂.key.subject then
      (disagreeOnL reg c₁ c₂).map fun a => (c₁.key.schema, c₁.key.subject, a)
    else []

end Check
