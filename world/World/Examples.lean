/-
# World.Examples — the theorems' hypotheses can be met

Concrete runs over the table example of `World.Conflicts`, each checked by
`decide`. They show that the statements in `World.Log`, `World.Status` and
`World.Visible` are about situations that actually occur, not empty ones:

- the footprint of `diff` really is larger than the set of changed ids;
- the example's claim ids are injective in keys (the premise of
  `reviewSurvives` and `needsReviewOnCoreChange` holds here);
- a human review confirms; a compiler-written review changes nothing; a core
  change gives `needsReview`; restoring the core restores the decision;
- a conflict pinned to claims from two files is visible to a reader allowed
  both files and hidden from a reader denied one.
-/
import World.Log
import World.Status
import World.Conflicts
import World.Visible
import World.WellFormed

namespace World.Example

set_option autoImplicit false

/-- Claim ids in the example: (schema code, subject, sources). -/
def d₀ : ClaimIdDerivation C₀ where
  claimId k := ((show Sch from k.schema).code, k.subject, k.sources)

theorem Sch.code_injective : Function.Injective Sch.code := by
  intro a b h
  cases a <;> cases b <;> first | rfl | (simp [Sch.code] at h)

/-- The injectivity premise holds for the example's ids. -/
theorem d₀_injective : Function.Injective d₀.claimId := by
  rintro ⟨s₁, sub₁, src₁⟩ ⟨s₂, sub₂, src₂⟩ h
  change ((Sch.code s₁, sub₁, src₁) : Nat × List Nat × List Nat) =
    (Sch.code s₂, sub₂, src₂) at h
  have hs : Sch.code s₁ = Sch.code s₂ := congrArg Prod.fst h
  have hsub : sub₁ = sub₂ := congrArg (fun x : Nat × List Nat × List Nat => x.2.1) h
  have hsrc : src₁ = src₂ := congrArg (fun x : Nat × List Nat × List Nat => x.2.2) h
  have : s₁ = s₂ := Sch.code_injective hs
  subst this hsub hsrc
  rfl

/-- Decision codes. -/
def decConfirm : Nat := 1

/-- The review schema of the example. -/
def R₀ : ReviewSchema C₀ Cols where
  sid := Sch.review
  decision := fun cols =>
    match cols with
    | [(_, 1)] => .confirmed
    | _ => .rejected

/-- A review by principal `who` of claim `c`, pinned at its current core. -/
def reviewClaim (who : Nat) (c : Claim C₀ Cols) (code : Nat) : Claim C₀ Cols where
  key := ⟨Sch.review, [who], []⟩
  payload := [(0, code)]
  pins := [⟨.claim (c.id d₀), .core (c.core reg₀), 1000⟩]
  valid := ⟨none, none⟩

/-- A receipt. -/
def rcpt (tx : Nat) (op : Op C₀ Cols) (k : PrincipalKind) : Receipt C₀ Cols :=
  ⟨tx, op, (k, (7 : Nat)), (0 : Nat), (0 : Nat)⟩

/-- File A's table, after an edit that drops the `id` column (its core changes). -/
def cA' : Claim C₀ Cols := tableClaim fileA [(colEmail, tVarchar)]

def L₁ : List (Receipt C₀ Cols) := [rcpt 1 (.put cA) .compiler]
def L₂ : List (Receipt C₀ Cols) := L₁ ++ [rcpt 2 (.put (reviewClaim 42 cA decConfirm)) .human]

/-! ### Status -/

/-- Before any review: the table schema's initial status. -/
example : status R₀ reg₀ d₀ L₁ cA = .observed := by decide

/-- A human review at the current core confirms. -/
example : status R₀ reg₀ d₀ L₂ cA = .confirmed := by decide

/-- The same review written by the compiler changes nothing. -/
example : status R₀ reg₀ d₀
    (L₁ ++ [rcpt 2 (.put (reviewClaim 42 cA decConfirm)) .compiler]) cA = .observed := by
  decide

/-- The compiler re-putting the same claim keeps the confirmation. -/
example : status R₀ reg₀ d₀ (L₂ ++ [rcpt 3 (.put cA) .compiler]) cA = .confirmed := by decide

/-- After the core changes, the old review no longer decides: `needsReview`. -/
example : status R₀ reg₀ d₀ (L₂ ++ [rcpt 3 (.put cA') .compiler]) cA' = .needsReview := by
  decide

/-- Changing the core back restores the decision made at that core. -/
example : status R₀ reg₀ d₀
    (L₂ ++ [rcpt 3 (.put cA') .compiler, rcpt 4 (.put cA) .compiler]) cA = .confirmed := by
  decide

/-! ### The footprint is an over-approximation -/

/-- A second put of the same claim lands in the footprint of `diff` ... -/
example : diff d₀ [rcpt 1 (.put cA) .compiler, rcpt 2 (.put cA) .agent] 1 2 = [cA.id d₀] := by
  decide

/-- ... although the value under that id did not change. -/
example : state d₀ [rcpt 1 (.put cA) .compiler, rcpt 2 (.put cA) .agent] 1 (cA.id d₀) =
    state d₀ [rcpt 1 (.put cA) .compiler, rcpt 2 (.put cA) .agent] 2 (cA.id d₀) := by
  decide

/-! ### Visibility -/

/-- A conflict claim pinning file A's and file B's tables. Its payload is
unused here. -/
def conflictAB : Claim C₀ Cols where
  key := ⟨Sch.table, [customers, colEmail], [fileA, fileB]⟩
  payload := []
  pins := [⟨.claim (cA.id d₀), .core (cA.core reg₀), 1000⟩,
           ⟨.claim (cB.id d₀), .core (cB.core reg₀), 1000⟩]
  valid := ⟨none, none⟩

/-- The state holding both tables. -/
def σ₀ : C₀.ClaimId → Option (Claim C₀ Cols) := fun i =>
  if i = cA.id d₀ then some cA else if i = cB.id d₀ then some cB else none

/-- A reader allowed every file. -/
def allFiles : Scope C₀ := ⟨fun _ => false, fun _ => false, fun _ _ => true, fun _ _ => false⟩

/-- A reader allowed every file but denied file B. -/
def notB : Scope C₀ :=
  ⟨fun _ => false, fun _ => false, fun _ _ => true, fun doc _ => doc == fileB⟩

example : visible d₀ σ₀ allFiles 2 conflictAB = true := by decide
example : visible d₀ σ₀ notB 2 conflictAB = false := by decide
/-- Too small a bound hides, never shows. -/
example : visible d₀ σ₀ allFiles 1 conflictAB = false := by decide
/-- File A's table alone stays visible to the reader denied file B. -/
example : visible d₀ σ₀ notB 1 cA = true := by decide

/-! ### No pin cycles in the example state -/

/-- Is this a claim pin? -/
def isClaimPin (p : Pin C₀) : Bool :=
  match p.target with
  | .claim _ => true
  | .source _ _ => false

/-- A rank for `σ₀`: claims with a claim pin sit one level above the tables. -/
def rank₀ (c : Claim C₀ Cols) : Nat := if c.pins.any isClaimPin then 1 else 0

/-- The example state has no pin cycles. -/
theorem ranked₀ : Ranked σ₀ rank₀ := ⟨by
  rintro c' c ⟨p, hp, i, ht, hσ⟩
  have h1 : rank₀ c' = 0 := by
    unfold σ₀ at hσ
    split at hσ
    · cases hσ; decide
    · split at hσ
      · cases hσ; decide
      · cases hσ
  have h2 : rank₀ c = 1 := by
    unfold rank₀
    rw [if_pos]
    exact List.any_eq_true.mpr ⟨p, hp, by simp [isClaimPin, ht]⟩
  omega⟩

/-- With the rank, visibility needs no chosen bound. -/
example : visibleR d₀ σ₀ allFiles rank₀ conflictAB = true := by decide
example : visibleR d₀ σ₀ notB rank₀ conflictAB = false := by decide

end World.Example
