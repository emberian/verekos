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
import World.Traverse
import World.Identity
import World.Admission
import World.Document
import World.Shapes
import World.CarryForward
import Mathlib.Data.Prod.Lex

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

/-- The log holding both tables. -/
def Lσ : List (Receipt C₀ Cols) := [rcpt 1 (.put cA) .compiler, rcpt 2 (.put cB) .compiler]

/-- The state holding both tables: the replay of `Lσ`. -/
def σ₀ : C₀.ClaimId → Option (Claim C₀ Cols) := latest d₀ Lσ

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

/-- `Lσ` passes admission (checked by `decide`). -/
theorem admLσ : AdmLog d₀ Lσ := by decide

/-- So the state has no pin cycles, ranked by the **computed** rank. -/
theorem ranked₀ : Ranked σ₀ (rankN d₀ Lσ) := ranked_of_admLog d₀ Lσ admLσ

/-- The computed ranks: tables 0, the conflict (pinning two tables) 1. -/
example : rankN d₀ Lσ cA = 0 ∧ rankN d₀ Lσ conflictAB = 1 := by decide
example : rankOf d₀ Lσ cA = some 0 := by decide

/-- Refused: a claim pinning ids nothing has put yet. -/
example : ¬ AdmLog d₀ [rcpt 1 (.put conflictAB) .compiler] := by decide

/-- Refused: file A's table re-put under its id, now also pinning file B's
table. Its rank would rise from 0 to 1 (rule 2), the step that could close a
cycle with any claim pinning A. -/
example : ¬ AdmLog d₀ (Lσ ++ [rcpt 3 (.put { cA with
    pins := cA.pins ++ [⟨.claim (cB.id d₀), .core (cB.core reg₀), 1000⟩] }) .compiler]) := by
  decide

/-- Accepted: the conflict claim after both tables. -/
example : AdmLog d₀ (Lσ ++ [rcpt 3 (.put conflictAB) .compiler]) := by decide

/-- With the rank, visibility needs no chosen bound. -/
example : visibleR d₀ σ₀ allFiles (rankN d₀ Lσ) conflictAB = true := by decide
example : visibleR d₀ σ₀ notB (rankN d₀ Lσ) conflictAB = false := by decide

end World.Example

/-! ### Traversal and identity -/

namespace World.Example

def orders : Nat := 2

/-- File A's `orders` table. -/
def cO : Claim C₀ Cols where
  key := ⟨Sch.table, [orders], [fileA]⟩
  payload := [(colId, tInt)]
  pins := [⟨.source fileA none, .atoms [], 1000⟩]
  valid := ⟨none, none⟩

/-- A claim of schema `s` pinning two claims at their cores. -/
def pair (s : Sch) (subj : List Nat) (srcs : List Nat) (a b : Claim C₀ Cols) : Claim C₀ Cols where
  key := ⟨s, subj, srcs⟩
  payload := []
  pins := [⟨.claim (a.id d₀), .core (a.core reg₀), 1000⟩,
           ⟨.claim (b.id d₀), .core (b.core reg₀), 1000⟩]
  valid := ⟨none, none⟩

/-- `orders` references `customers`. -/
def fkOC : Claim C₀ Cols := pair .fk [orders, customers] [fileA] cO cA
/-- A fuzzy candidate: A's and B's `customers` may be one table. -/
def saAB : Claim C₀ Cols := pair .sameAs [customers] [fileA, fileB] cA cB
/-- An exact merge: A's and C's `customers` are one table. -/
def mxAC : Claim C₀ Cols := pair .sameAsExact [customers] [fileA, fileC] cA cC

/-- Every two-claim-pin claim is an edge. -/
def E₀ : EdgeView C₀ Cols := ⟨fun c =>
  match c.pins with
  | [⟨.claim a, _, _⟩, ⟨.claim b, _, _⟩] => some (a, b)
  | _ => none⟩

def T₀ : C₀.SchemaId → Bool := fun _ => true

def Lt : List (Receipt C₀ Cols) :=
  [rcpt 1 (.put cA) .compiler, rcpt 2 (.put cB) .compiler, rcpt 3 (.put cO) .compiler,
   rcpt 4 (.put fkOC) .compiler, rcpt 5 (.put saAB) .compiler]

/-- `customers` is reached from `orders` over the foreign key. -/
example : Reach R₀ reg₀ d₀ E₀ T₀ Lt 1 (cO.id d₀) (cA.id d₀) :=
  .hop fkOC (.here 0 _)
    ⟨by decide, rfl, by decide, by decide, ⟨cO, by decide, by decide⟩, ⟨cA, by decide, by decide⟩⟩

/-- The unreviewed fuzzy candidate is not crossed. -/
example : ¬ Crosses R₀ reg₀ d₀ E₀ T₀ Lt saAB (cA.id d₀) (cB.id d₀) :=
  unreviewed_hypothesis_edge_not_crossed R₀ reg₀ d₀ E₀ T₀ Lt saAB _ _ (by decide) (by decide)

/-- A human confirms the candidate; now it is crossed. -/
def Lt' : List (Receipt C₀ Cols) := Lt ++ [rcpt 6 (.put (reviewClaim 42 saAB decConfirm)) .human]

example : Crosses R₀ reg₀ d₀ E₀ T₀ Lt' saAB (cA.id d₀) (cB.id d₀) :=
  ⟨by decide, rfl, by decide, by decide, ⟨cA, by decide, by decide⟩, ⟨cB, by decide, by decide⟩⟩

/-- An agent's confirmation would count too; the compiler's does not. -/
example : ¬ Crosses R₀ reg₀ d₀ E₀ T₀
    (Lt ++ [rcpt 6 (.put (reviewClaim 42 saAB decConfirm)) .compiler]) saAB
    (cA.id d₀) (cB.id d₀) :=
  unreviewed_hypothesis_edge_not_crossed R₀ reg₀ d₀ E₀ T₀ _ saAB _ _ (by decide) (by decide)

/-- `SameAs` schemas. -/
def V₀ : SameAsView C₀ := ⟨fun s => s == Sch.sameAs || s == Sch.sameAsExact⟩

def cands₀ : Finset (Claim C₀ Cols) := {saAB, mxAC}

def L₀ : List (Receipt C₀ Cols) :=
  [rcpt 1 (.put cA) .compiler, rcpt 2 (.put cB) .compiler, rcpt 3 (.put cC) .compiler,
   rcpt 4 (.put saAB) .compiler]

/-- The compiler's confirming review of the exact merge. -/
def rvMx : Claim C₀ Cols := reviewClaim 7 mxAC decConfirm

def r₁ : Receipt C₀ Cols := rcpt 5 (.put mxAC) .compiler
def r₂ : Receipt C₀ Cols := rcpt 6 (.put rvMx) .compiler
def r₃ : Receipt C₀ Cols := rcpt 7 (.retract (mxAC.id d₀)) .compiler

/-- Before the merge: no links (the fuzzy candidate is unconfirmed). -/
example : links R₀ reg₀ d₀ V₀ L₀ cands₀ = ∅ := by decide

/-- After the compiler's exact merge: A's and C's `customers` are linked. -/
example : links R₀ reg₀ d₀ V₀ (L₀ ++ [r₁, r₂]) cands₀ = {(cA.key, cC.key)} := by decide

/-- The merge theorem's hypotheses hold here. -/
example : Same (links R₀ reg₀ d₀ V₀ (L₀ ++ [r₁, r₂]) cands₀) cA.key cC.key :=
  (merge_takes_effect R₀ reg₀ d₀ V₀ L₀ cands₀ mxAC rvMx cA cC (cA.id d₀) (cC.id d₀) r₁ r₂
    (by decide) rfl rfl (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide)).2

/-- The reversibility theorem's hypotheses hold here: retracting the merge
gives back exactly the links before it. -/
example : links R₀ reg₀ d₀ V₀ (L₀ ++ [r₁, r₂, r₃]) cands₀ = links R₀ reg₀ d₀ V₀ L₀ cands₀ :=
  merge_reversible R₀ reg₀ d₀ V₀ L₀ cands₀ mxAC rvMx r₁ r₂ r₃ rfl rfl rfl
    (by decide) (by decide) (by decide) (by decide) ⟨(0 : Nat), .confirmed, by decide⟩ (by decide)
    (by
      intro c hc a b h
      simp only [cands₀, Finset.mem_insert, Finset.mem_singleton] at hc
      rcases hc with rfl | rfl
      · have : asSameAs V₀ saAB = some (cA.id d₀, cB.id d₀) := by decide
        rw [this] at h; injection h with h; injection h with ha hb; subst ha hb
        exact ⟨by decide, by decide⟩
      · have : asSameAs V₀ mxAC = some (cA.id d₀, cC.id d₀) := by decide
        rw [this] at h; injection h with h; injection h with ha hb; subst ha hb
        exact ⟨by decide, by decide⟩)

/-- With no links, `Same` is equality. -/
theorem same_empty {α : Type} [DecidableEq α] (x y : α) (h : Same (∅ : Finset (α × α)) x y) :
    x = y := by
  rcases same_eq_or_support ∅ h with h | h
  · exact h
  · simp [support] at h

/-- After the retraction, A's and C's `customers` are separate again. -/
example : ¬ Same (links R₀ reg₀ d₀ V₀ (L₀ ++ [r₁, r₂, r₃]) cands₀) cA.key cC.key := by
  have : links R₀ reg₀ d₀ V₀ (L₀ ++ [r₁, r₂, r₃]) cands₀ = ∅ := by decide
  rw [this]
  intro h
  exact absurd (same_empty _ _ h) (by decide)

end World.Example

/-! ### A total order on the example's keys, and canonical keys -/

namespace World.Example

/-- Keys as (schema code, subject, sources), compared lexicographically. -/
def keyCode (k : ClaimKey C₀) : Lex (Nat × Lex (List Nat × List Nat)) :=
  toLex ((show Sch from k.schema).code, toLex (k.subject, k.sources))

theorem keyCode_injective : Function.Injective keyCode := by
  rintro ⟨s₁, sub₁, src₁⟩ ⟨s₂, sub₂, src₂⟩ h
  change ((Sch.code s₁, (sub₁, src₁)) : Nat × (List Nat × List Nat)) =
    (Sch.code s₂, (sub₂, src₂)) at h
  have hs : Sch.code s₁ = Sch.code s₂ := congrArg Prod.fst h
  have hsub : sub₁ = sub₂ := congrArg (fun x : Nat × (List Nat × List Nat) => x.2.1) h
  have hsrc : src₁ = src₂ := congrArg (fun x : Nat × (List Nat × List Nat) => x.2.2) h
  have : s₁ = s₂ := Sch.code_injective hs
  subst this hsub hsrc
  rfl

instance : LinearOrder (ClaimKey C₀) := LinearOrder.lift' keyCode keyCode_injective

/-- After the exact merge, C's `customers` has A's key as its canonical key
(file A's key is the smaller), and after the retraction it is its own again. -/
example : canonical (links R₀ reg₀ d₀ V₀ (L₀ ++ [r₁, r₂]) cands₀) cC.key = cA.key := by
  have hle : cA.key ≤ cC.key := by show keyCode _ ≤ keyCode _; decide
  apply le_antisymm
  · exact canonical_le _ _ _
      ((same_equivalence _).symm (merge_takes_effect R₀ reg₀ d₀ V₀ L₀ cands₀ mxAC rvMx cA cC
        (cA.id d₀) (cC.id d₀) r₁ r₂ (by decide) rfl rfl (by decide) (by decide) (by decide)
        (by decide) (by decide) (by decide) (by decide)).2)
  · have hs := same_canonical (links R₀ reg₀ d₀ V₀ (L₀ ++ [r₁, r₂]) cands₀) cC.key
    have hl : links R₀ reg₀ d₀ V₀ (L₀ ++ [r₁, r₂]) cands₀ = {(cA.key, cC.key)} := by decide
    rw [hl] at hs ⊢
    generalize canonical ({(cA.key, cC.key)} : Finset _) cC.key = k at hs ⊢
    rcases same_eq_or_support _ hs with h | ⟨-, h⟩
    · rw [← h]; exact hle
    · simp only [support, Finset.image_singleton, Finset.mem_union,
        Finset.mem_singleton] at h
      rcases h with h | h <;> rw [h]
      · exact hle

example : canonical (links R₀ reg₀ d₀ V₀ (L₀ ++ [r₁, r₂, r₃]) cands₀) cC.key = cC.key := by
  have hl : links R₀ reg₀ d₀ V₀ (L₀ ++ [r₁, r₂, r₃]) cands₀ = ∅ := by decide
  have hs := same_canonical (links R₀ reg₀ d₀ V₀ (L₀ ++ [r₁, r₂, r₃]) cands₀) cC.key
  rw [hl] at hs ⊢
  exact (same_empty _ _ hs).symm

end World.Example

/-! ### The document shape, refusals, and rooms -/

namespace World.Example

/-- Atom revisions in the example are numbers. -/
instance (n : Nat) : OfNat C₀.AtomRev n := inferInstanceAs (OfNat Nat n)

/-- File A's `customers`, pinned to two atoms of file A at revisions 7 and 8. -/
def cW : Claim C₀ Cols where
  key := ⟨Sch.table, [customers], [fileA]⟩
  payload := [(colEmail, tVarchar)]
  pins := [⟨.source fileA none, .atoms [7, 8], 1000⟩]
  valid := ⟨none, none⟩

/-- A pin of the wrong shape: a source read as a core digest. -/
def cBad : Claim C₀ Cols := { cW with pins := [⟨.source fileA none, .core (0 : Nat), 1000⟩] }

example : (encode cW).map cellAtomPins = some [(fileA, 7), (fileA, 8)] := by decide
example : (encode cBad).isNone = true := by decide
example : (encode conflictAB).map (·.premises.length) = some 2 := by decide

/-- `orders` with its outgoing foreign key lays out as one document with one
edge container linking to `customers`. -/
example : (toDocument d₀ E₀ cO [fkOC]).map (·.edges.map (·.link)) = some [cA.id d₀] := by
  decide
/-- An edge that does not start at the object is refused. -/
example : (toDocument d₀ E₀ cA [fkOC]).isNone = true := by decide

/-- The kernel's refusals, by name. -/
example : admitEvidence (C := C₀) (fun _ => false) (fun _ _ => true)
    ⟨⟨1000, none⟩, ⟨fileA, [7]⟩⟩ = some .sourceNotCovered := by decide
example : admitEvidence (C := C₀) (fun _ => true) (fun _ a => a == 7)
    ⟨⟨1000, none⟩, ⟨fileA, [7, 9]⟩⟩ = some .staleOpening := by decide

/-- What readers see: the placeholder without a grant, `moved` after an edit,
the same bytes otherwise. -/
example : viewEvidence (C := C₀) (fun _ => false) (fun _ _ => true)
    ⟨⟨1000, none⟩, ⟨fileA, [7, 8]⟩⟩ = .noGrant 2 := by decide
example : viewEvidence (C := C₀) (fun _ => true) (fun _ a => a == 7)
    ⟨⟨1000, none⟩, ⟨fileA, [7, 8]⟩⟩ = .moved := by decide
example : viewEvidence (C := C₀) (fun _ => true) (fun _ _ => true)
    ⟨⟨1000, none⟩, ⟨fileA, [7, 8]⟩⟩ = .sameBytes := by decide

/-- Rooms: file C alone in room 2, the rest in room 1. -/
def roomOf (doc : Nat) : Nat := if doc = fileC then 2 else 1

/-- The audience theorem applies to file A's table: visible exactly to readers
holding room 1's grant. -/
example (g : Nat → Bool) :
    visibleR d₀ σ₀ (readerScope fun doc => g (roomOf doc)) (rankN d₀ Lσ) cW = true ↔
      g 1 = true :=
  visibleR_iff_room d₀ σ₀ (rankN d₀ Lσ) roomOf g 1 cW _ rfl (by simp [Claim.PinsNonempty, cW]) (by
    intro p hp
    simp only [cW, List.mem_singleton] at hp
    subst hp
    exact ⟨fileA, none, rfl, by decide⟩)

end World.Example

/-! ### Shapes, the manifest, and carry-forward -/

namespace World.Example

/-- Atom ids in the example: the structural key itself. -/
def atomOf₀ : List C₀.KeyPart → List Nat := id

def hdr₀ : SourceHeader C₀ := ⟨[fileA], (0 : Nat), (0 : Nat), (0 : Nat), (0 : Nat)⟩
def stA : Statement C₀ := ⟨[customers], (11 : Nat)⟩
def stO : Statement C₀ := ⟨[orders], (12 : Nat)⟩
def srcA : SourceDoc C₀ (List Nat) := importSource atomOf₀ hdr₀ [stA, stO] 1

/-- Re-importing the unchanged file changes nothing. -/
example : reimport atomOf₀ srcA [stA, stO] 2 = srcA := by decide
/-- Editing `orders` moves only its atom to the new revision. -/
example : (reimport atomOf₀ srcA [stA, ⟨[orders], (13 : Nat)⟩] 2).atomPins =
    [([customers], 1), ([orders], 2)] := by decide

/-- A compile that stops emitting `orders` unlinks it; history stays. -/
def man₀ : Manifest C₀ :=
  Manifest.ofCurrent [([customers], cA.id d₀), ([orders], cO.id d₀)]
example : (man₀.compile [([customers], cA.id d₀)]).current = [([customers], cA.id d₀)] := by
  decide
example : (man₀.compile [([customers], cA.id d₀)]).links.length = 2 := by decide

/-- Signatures as numbers: A = 1, B = 2. A review at A, then compiles. -/
def h₀ : HeaderAtom C₀ := ⟨5, (1 : Nat)⟩
def e₀ : EConflict C₀ := ⟨.isOpen, none, (1 : Nat)⟩

-- unchanged: the pin shows the same bytes and EKOS keeps the review
example : renderHeaderPin 5 (compileAll h₀ [(1 : Nat), (1 : Nat)]) = .sameBytes := by decide
example : (ekosAll (ekosReview e₀ .resolved) [(1 : Nat), (1 : Nat)]).status =
    .decided .resolved := by decide
-- A → B → A: moved, and EKOS stays open
example : renderHeaderPin 5 (compileAll h₀ [(2 : Nat), (1 : Nat)]) = .moved := by decide
example : (ekosAll (ekosReview e₀ .resolved) [(2 : Nat), (1 : Nat)]).status = .isOpen := by
  decide

end World.Example
