/-
# World.CarryForward — "the transclusion is the carry-forward rule"

Design §3 says a review of a conflict needs no carry-forward code. The review
pins the conflict's header atom by a snapshot transclusion. The compiler
rewrites that atom only when the conflict's signature changes. So the pin
shows the same bytes exactly while the signature is unchanged, and says
`moved` once it changes. That is what EKOS's `carry_forward`
(`/Users/ember/dev/EKOS/ekos/crates/semantic/src/conflicts.rs:506-535`)
does by hand.

This file models the three things and proves where they agree.

1. **The header atom** (`compileHeader`). A compile with signature `s` leaves
   the atom alone if `s` is what it holds, and otherwise rewrites it at a
   fresh revision. So the revision moves exactly when the signature changes
   (`compileHeader_rev_eq_iff`).
2. **The review's snapshot pin** (`renderHeaderPin`). It reads `sameBytes`
   iff no compile since the review changed the signature, and `moved`
   otherwise (`pin_sameBytes_iff`, `pin_moved_iff`). It agrees with
   `World.Document.viewEvidence` (`renderHeaderPin_eq_viewEvidence`).
3. **EKOS's `carry_forward`** (`ekosCompile`), modelled line by line:
   - an `open` conflict stays open;
   - a reviewed one keeps its review iff `reviewed_signature` equals the
     fresh signature;
   - otherwise it reopens as `open`, keeping the old decision as
     `previous_review`.

   After a review, the review holds iff every later compile had the reviewed
   signature (`ekos_holds_iff`).

**Agreement.** The pin reads `sameBytes` iff EKOS's review holds
(`pin_agrees_with_ekos`).

**World.Status agrees too, but only with the right core digest.** Make the
conflict schema's `core` the **header atom's revision**, and give the review
a single admitted decision pinned at the revision it read. Then:
- `status` is the decision while the pin reads `sameBytes`;
- it is `needsReview` once the pin reads `moved`;
- in both cases this is exactly when EKOS holds or reopens
  (`status_core_rev_agrees`).

EKOS's reopened state is spelled `open`, with the old decision kept;
World.Status's is `needsReview`, with the old review kept. They mean the same
thing.

**Making `core` the signature itself is not enough** (`core_sig_diverges`).
If the signature goes A → B → A, the pin reads `moved` and EKOS stays
reopened (its early return on `open`). But a status keyed by signature finds
the old review at the current core A and reports the old decision. The
revision is the right core because it never comes back.

Every name here is new to VerEKOS.
-/
import World.Status
import World.Document

namespace World

set_option autoImplicit false

variable [C : Carriers]

/-! ## The header atom and the review's pin -/

/-- The conflict header atom: its revision and the signature it holds. -/
structure HeaderAtom [C : Carriers] where
  rev : Nat
  sig : C.Digest
  deriving DecidableEq

/-- One compile with signature `s`: rewrite the header only if `s` changed,
at a revision newer than any before. -/
def compileHeader (h : HeaderAtom) (s : C.Digest) : HeaderAtom :=
  if s = h.sig then h else ⟨h.rev + 1, s⟩

/-- A sequence of compiles. -/
def compileAll (h : HeaderAtom) (hist : List C.Digest) : HeaderAtom :=
  hist.foldl compileHeader h

/-- **The revision moves exactly when the signature changes.** -/
theorem compileHeader_rev_eq_iff (h : HeaderAtom) (s : C.Digest) :
    (compileHeader h s).rev = h.rev ↔ s = h.sig := by
  unfold compileHeader
  split
  · simp_all
  · rename_i hs; simp [hs]

theorem rev_le_compileAll (h : HeaderAtom) (hist : List C.Digest) :
    h.rev ≤ (compileAll h hist).rev := by
  induction hist generalizing h with
  | nil => exact Nat.le_refl _
  | cons s t ih =>
    show h.rev ≤ (compileAll (compileHeader h s) t).rev
    have h1 := ih (compileHeader h s)
    have h2 : h.rev ≤ (compileHeader h s).rev := by unfold compileHeader; split <;> simp
    omega

/-- The revision after a run of compiles is the one read iff every compile
had the signature read. -/
theorem compileAll_rev_eq_iff (h : HeaderAtom) (hist : List C.Digest) :
    (compileAll h hist).rev = h.rev ↔ ∀ s ∈ hist, s = h.sig := by
  induction hist generalizing h with
  | nil => simp [compileAll]
  | cons s t ih =>
    simp only [compileAll, List.foldl_cons, List.mem_cons, forall_eq_or_imp]
    by_cases hs : s = h.sig
    · have : compileHeader h s = h := by simp [compileHeader, hs]
      rw [this]
      exact ⟨fun h' => ⟨hs, (ih h).mp h'⟩, fun ⟨_, h'⟩ => (ih h).mpr h'⟩
    · have hc : compileHeader h s = ⟨h.rev + 1, s⟩ := by simp [compileHeader, hs]
      rw [hc]
      have := rev_le_compileAll (⟨h.rev + 1, s⟩ : HeaderAtom) t
      unfold compileAll at this
      simp only at this
      constructor
      · intro h'; omega
      · rintro ⟨h', -⟩; exact absurd h' hs

/-- The signature the header holds is the last one compiled. -/
theorem compileAll_sig (h : HeaderAtom) (hist : List C.Digest) :
    (compileAll h hist).sig = hist.getLastD h.sig := by
  induction hist generalizing h with
  | nil => rfl
  | cons s t ih =>
    simp only [compileAll, List.foldl_cons] at ih ⊢
    rw [ih]
    have : (compileHeader h s).sig = s := by unfold compileHeader; split <;> simp_all
    rw [List.getLastD_cons, this]

/-- A reviewer's view of the header pin (the reviewer holds a grant): the same
bytes iff the header is still at the revision read. -/
def renderHeaderPin (read : Nat) (h : HeaderAtom) : PinView :=
  if h.rev = read then .sameBytes else .moved

/-- **The pin shows the same bytes iff the signature never changed since the
review.** -/
theorem pin_sameBytes_iff (h : HeaderAtom) (hist : List C.Digest) :
    renderHeaderPin h.rev (compileAll h hist) = .sameBytes ↔ ∀ s ∈ hist, s = h.sig := by
  rw [← compileAll_rev_eq_iff]
  unfold renderHeaderPin
  split <;> simp_all

/-- **The pin says `moved` iff some compile since the review changed the
signature.** -/
theorem pin_moved_iff (h : HeaderAtom) (hist : List C.Digest) :
    renderHeaderPin h.rev (compileAll h hist) = .moved ↔ ∃ s ∈ hist, s ≠ h.sig := by
  have hs := pin_sameBytes_iff h hist
  have hcases : renderHeaderPin h.rev (compileAll h hist) = .sameBytes ∨
      renderHeaderPin h.rev (compileAll h hist) = .moved := by
    unfold renderHeaderPin; split <;> simp
  constructor
  · intro hm
    refine Classical.byContradiction fun hn => ?_
    have hall : ∀ s ∈ hist, s = h.sig := fun s hs' =>
      Classical.byContradiction fun hne => hn ⟨s, hs', hne⟩
    rw [hs.mpr hall] at hm
    cases hm
  · rintro ⟨x, hx, hne⟩
    rcases hcases with h1 | h1
    · exact absurd (hs.mp h1 x hx) hne
    · exact h1

/-- `renderHeaderPin` is `viewEvidence` on the review's evidence container,
for a reader with a grant, when atom revisions are read through an injective
`pinOf`. -/
theorem renderHeaderPin_eq_viewEvidence (pinOf : Nat → C.AtomRev)
    (hinj : Function.Injective pinOf) (doc : C.SourceId) (m : EvidenceMeta)
    (read : Nat) (h : HeaderAtom) :
    viewEvidence (fun _ => true) (fun _ a => decide (a = pinOf h.rev))
      ⟨m, ⟨doc, [pinOf read]⟩⟩ = renderHeaderPin read h := by
  unfold viewEvidence renderHeaderPin
  simp only [Bool.not_true, Bool.false_eq_true, if_false, List.all_cons, List.all_nil,
    Bool.and_true, decide_eq_true_eq]
  by_cases hr : h.rev = read
  · simp [hr]
  · have : pinOf read ≠ pinOf h.rev := fun e => hr (hinj e).symm
    simp [hr, this]

/-! ## EKOS's `carry_forward` -/

/-- EKOS conflict status: `open`, or a decision. -/
inductive EStatus where
  /-- EKOS `open`. -/
  | isOpen
  | decided (s : Status)
  deriving DecidableEq

/-- The parts of an EKOS conflict object `carry_forward` reads and writes. -/
structure EConflict [C : Carriers] where
  status : EStatus
  reviewedSig : Option C.Digest
  sig : C.Digest
  deriving DecidableEq

/-- A human review: the decision, and `reviewed_signature` := the current
signature. -/
def ekosReview (cur : EConflict) (s : Status) : EConflict :=
  ⟨.decided s, some cur.sig, cur.sig⟩

/-- One compile: the fresh conflict (status `open`, signature `fresh`), then
`carry_forward(fresh, current)`. -/
def ekosCompile (cur : EConflict) (fresh : C.Digest) : EConflict :=
  match cur.status with
  | .isOpen => ⟨.isOpen, none, fresh⟩
  | .decided s =>
    if cur.reviewedSig = some fresh then ⟨.decided s, cur.reviewedSig, fresh⟩
    else ⟨.isOpen, none, fresh⟩

def ekosAll (cur : EConflict) (hist : List C.Digest) : EConflict :=
  hist.foldl ekosCompile cur

theorem ekosAll_open (r : Option C.Digest) (g : C.Digest) (hist : List C.Digest) :
    (ekosAll ⟨.isOpen, r, g⟩ hist).status = .isOpen := by
  induction hist generalizing r g with
  | nil => rfl
  | cons x t ih => exact ih none x

/-- **EKOS: a review holds iff every later compile had the reviewed
signature.** Once a compile changes it, the conflict is `open` for good (until
a new review), even if the signature later comes back. -/
theorem ekos_holds_iff (cur : EConflict) (s : Status) (hist : List C.Digest) :
    (ekosAll (ekosReview cur s) hist).status = .decided s ↔ ∀ x ∈ hist, x = cur.sig := by
  unfold ekosReview
  generalize cur.sig = g
  induction hist with
  | nil => simp [ekosAll]
  | cons x t ih =>
    simp only [ekosAll, List.foldl_cons, List.mem_cons, forall_eq_or_imp] at ih ⊢
    by_cases hx : x = g
    · subst hx
      have : ekosCompile (⟨.decided s, some x, x⟩ : EConflict) x = ⟨.decided s, some x, x⟩ := by
        simp [ekosCompile]
      rw [this]
      exact ⟨fun h => ⟨rfl, ih.mp h⟩, fun ⟨_, h⟩ => ih.mpr h⟩
    · have : ekosCompile (⟨.decided s, some g, g⟩ : EConflict) x = ⟨.isOpen, none, x⟩ := by
        simp [ekosCompile, Ne.symm hx]
      rw [this]
      have := ekosAll_open none x t
      unfold ekosAll at this
      rw [this]
      simp [hx]

/-! ## Agreement -/

/-- **The transclusion is the carry-forward rule.** For a review taken when
the header held signature `h.sig` (and EKOS's conflict had the same signature),
the review's snapshot pin shows the same bytes iff EKOS's review still holds. -/
theorem pin_agrees_with_ekos (h : HeaderAtom) (cur : EConflict) (hsig : cur.sig = h.sig)
    (s : Status) (hist : List C.Digest) :
    renderHeaderPin h.rev (compileAll h hist) = .sameBytes ↔
      (ekosAll (ekosReview cur s) hist).status = .decided s := by
  rw [pin_sameBytes_iff, ekos_holds_iff, hsig]

section status
variable {P : C.SchemaId → Type} (R : ReviewSchema P) (reg : Registry P)
  [d : ClaimIdDerivation]

/-- With one admitted review, the status is its decision at its core and
`needsReview` at any other core. -/
theorem statusAt_single (L : List (Receipt P)) (k : ClaimKey) (dg₀ : C.Digest)
    (s₀ : Status) (h : admittedReviews R reg L k = [(dg₀, s₀)]) (dg : C.Digest) :
    statusAt R reg L k dg = if dg = dg₀ then s₀ else .needsReview := by
  unfold statusAt
  rw [h]
  by_cases hd : dg₀ = dg
  · subst hd; simp
  · simp [hd, Ne.symm hd]

/-- **World.Status agrees with EKOS when the conflict's core is the header
revision.** Let `revDigest` (injective) turn a header revision into a core
digest, and let the log hold one admitted review of the conflict, pinned at
the revision read, with decision `s₀`. After any run of compiles, the status at
the current core is `s₀` exactly when EKOS's review holds, and `needsReview`
exactly when EKOS has reopened. -/
theorem status_core_rev_agrees (revDigest : Nat → C.Digest) (hinj : Function.Injective revDigest)
    (L : List (Receipt P)) (k : ClaimKey) (h : HeaderAtom) (cur : EConflict)
    (hsig : cur.sig = h.sig) (s₀ : Status)
    (hrev : admittedReviews R reg L k = [(revDigest h.rev, s₀)]) (hist : List C.Digest) :
    statusAt R reg L k (revDigest (compileAll h hist).rev) =
      if (ekosAll (ekosReview cur s₀) hist).status = .decided s₀ then s₀ else .needsReview := by
  rw [statusAt_single R reg L k _ s₀ hrev]
  have hp := pin_agrees_with_ekos h cur hsig s₀ hist
  unfold renderHeaderPin at hp
  by_cases hr : (compileAll h hist).rev = h.rev
  · have he := hp.mp (by simp [hr])
    simp [hr, he]
  · have hne : revDigest (compileAll h hist).rev ≠ revDigest h.rev := fun e => hr (hinj e)
    have he : ¬ (ekosAll (ekosReview cur s₀) hist).status = .decided s₀ := fun e => by
      have := hp.mpr e
      simp [hr] at this
    simp [hne, he]

/-- **With the signature as the core, World.Status and EKOS disagree.** If
the signature goes from `a` to `b` and back to `a`, the pin says `moved` and
EKOS has reopened, but a status keyed by signature finds the review at the
current core `a` and reports the old decision. -/
theorem core_sig_diverges (L : List (Receipt P)) (k : ClaimKey) (a b : C.Digest)
    (hab : a ≠ b) (r : Nat) (s₀ : Status)
    (hrev : admittedReviews R reg L k = [(a, s₀)]) (cur : EConflict) (hsig : cur.sig = a) :
    statusAt R reg L k (compileAll ⟨r, a⟩ [b, a]).sig = s₀ ∧
      renderHeaderPin r (compileAll ⟨r, a⟩ [b, a]) = .moved ∧
      (ekosAll (ekosReview cur s₀) [b, a]).status = .isOpen := by
  refine ⟨?_, ?_, ?_⟩
  · rw [statusAt_single R reg L k a s₀ hrev, compileAll_sig]
    simp
  · have := (pin_moved_iff (⟨r, a⟩ : HeaderAtom) [b, a]).mpr ⟨b, by simp, Ne.symm hab⟩
    exact this
  · simp [ekosAll, ekosReview, hsig, ekosCompile, hab]

end status

end World
