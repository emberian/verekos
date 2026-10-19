/-
# Check.Adm — the pin law (`World.admissible`, `World.AdmLog`) without Mathlib

`World/Admission.lean` imports `World.WellFormed`, which imports Mathlib, so
calling `World.admissible` from the executable would link Mathlib. This file
copies `pinRank`, `maxPinRank`, `newRank`, `rstep`, `rankMap` and
`admissible` (Admission.lean:44-100) word for word, and decides `AdmLog` as a
`Bool`. `CheckProofs.Adm` proves `admissibleL = World.admissible` and
`admLogB d L = true ↔ World.AdmLog d L`, and the same for the pins-nonempty
rule (`World.Claim.PinsNonempty`). Built, never linked.
-/
import World.Log

namespace Check

set_option autoImplicit false

variable {C : World.Carriers} {P : C.SchemaId → Type} (d : World.ClaimIdDerivation C)

def pinRankL (m : C.ClaimId → Option Nat) (p : World.Pin C) : Nat :=
  match p.target with
  | .claim j => (m j).getD 0 + 1
  | .source _ _ => 0

def maxPinRankL (m : C.ClaimId → Option Nat) : List (World.Pin C) → Nat
  | [] => 0
  | p :: ps => max (pinRankL m p) (maxPinRankL m ps)

def newRankL (m : C.ClaimId → Option Nat) (c : World.Claim C P) : Nat := maxPinRankL m c.pins

def rstepL (m : C.ClaimId → Option Nat) (r : World.Receipt C P) : C.ClaimId → Option Nat :=
  match r.op with
  | .put c => fun i => if i = c.id d then some (newRankL m c) else m i
  | .retract _ => m

def rankMapL (L : List (World.Receipt C P)) : C.ClaimId → Option Nat :=
  L.foldl (rstepL d) (fun _ => none)

def admissibleL (L : List (World.Receipt C P)) (r : World.Receipt C P) : Bool :=
  match r.op with
  | .put c =>
    c.pins.all (fun p => match p.target with
        | .claim j => decide (j ≠ c.id d) && (World.latest d L j).isSome
        | .source _ _ => true) &&
    (match rankMapL d L (c.id d) with
     | some k => decide (newRankL (rankMapL d L) c ≤ k)
     | none => true)
  | .retract _ => true

/-- `AdmLog`, decided: every receipt is admissible against the log before it. -/
def admLogB (L : List (World.Receipt C P)) : Bool :=
  (List.range L.length).all fun k =>
    match L[k]? with
    | some r => admissibleL d (L.take k) r
    | none => true

/-- `Claim.PinsNonempty`, decided. -/
def pinsNonemptyB (c : World.Claim C P) : Bool := !c.pins.isEmpty

end Check
