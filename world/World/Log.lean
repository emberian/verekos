/-
# World.Log — the receipt log, its state, writes and diffs

In plain words:
- The log is a list of receipts. Nothing is ever removed from it.
- The **state** at transaction `t` is what you get by replaying, in log
  order, every receipt numbered `t` or less: a put installs the claim under its
  id, a retract removes whatever is under that id.
- **`write`** appends one receipt, except when the receipt would change
  nothing (a put of exactly the value already current, or a retract of an id
  that is already absent). Then it leaves the log as it was.
- **`diff L a b`** lists the ids touched by receipts numbered after `a` and up
  to `b`. It is a footprint: every id whose value differs between the two
  states is in it, but an id can be in it without its value having changed
  (a put of the same value, or a put then a retract).

Every name here is new to VerEKOS.
-/
import World.Claim

namespace World

set_option autoImplicit false

variable [C : Carriers] {P : C.SchemaId → Type} [d : ClaimIdDerivation]

/-- A state: the current claim under each id, if any. -/
abbrev View [C : Carriers] (P : C.SchemaId → Type) := C.ClaimId → Option (Claim P)

/-- The empty state. -/
def View.empty : View P := fun _ => none

/-- Apply one receipt to a state. -/
def apply (s : View P) (r : Receipt P) : View P :=
  match r.op with
  | .put c => fun i => if i = c.id then some c else s i
  | .retract j => fun i => if i = j then none else s i

/-- Replay a list of receipts, in list order, from the empty state. -/
def replay (L : List (Receipt P)) : View P :=
  L.foldl (apply) View.empty

/-- The state at transaction `t`: replay the receipts numbered `t` or less. -/
def state (L : List (Receipt P)) (t : Nat) : View P :=
  replay (L.filter (fun r => decide (r.tx ≤ t)))

/-- The state after the whole log. -/
def latest (L : List (Receipt P)) : View P := replay L

section write
variable [∀ s, DecidableEq (P s)]

/-- Would this receipt change nothing about the latest state? -/
def redundant (L : List (Receipt P)) (r : Receipt P) : Bool :=
  match r.op with
  | .put c => decide (latest L (c.id) = some c)
  | .retract i => (latest L i).isNone

/-- Append a receipt unless it would change nothing. -/
def write (L : List (Receipt P)) (r : Receipt P) : List (Receipt P) :=
  if redundant L r then L else L ++ [r]

end write

/-- A step on logs is append-only when the old log is always a prefix of the
new one. -/
def AppendOnly (step : List (Receipt P) → List (Receipt P)) : Prop :=
  ∀ L, L <+: step L

/-- The ids touched by receipts numbered after `a` and up to `b`, in log order
(an id may repeat). -/
def diff (L : List (Receipt P)) (a b : Nat) : List C.ClaimId :=
  (L.filter (fun r => decide (a < r.tx ∧ r.tx ≤ b))).map (fun r => r.op.id)

/-! ## Facts about `apply` and `replay` -/

/-- A receipt that touches another id leaves this id alone. -/
theorem apply_of_ne (s : View P) (r : Receipt P) (i : C.ClaimId)
    (h : r.op.id ≠ i) : apply s r i = s i := by
  unfold apply
  cases hop : r.op with
  | put c =>
    simp only [hop, Op.id] at h ⊢
    simp [Ne.symm h]
  | retract j =>
    simp only [hop, Op.id] at h ⊢
    simp [Ne.symm h]

/-- A receipt that touches this id sets it without looking at the old value. -/
theorem apply_of_eq (s s' : View P) (r : Receipt P) (i : C.ClaimId)
    (h : r.op.id = i) : apply s r i = apply s' r i := by
  unfold apply
  cases hop : r.op with
  | put c =>
    simp only [hop, Op.id] at h ⊢
    simp [h]
  | retract j =>
    simp only [hop, Op.id] at h ⊢
    simp [h]

/-- The value at `i` after a replay depends only on the receipts that touch
`i`, and on the starting value at `i`. -/
theorem foldl_apply_at (i : C.ClaimId) :
    ∀ (L : List (Receipt P)) (s s' : View P), s i = s' i →
      (L.foldl (apply) s) i =
        ((L.filter (fun r => decide (r.op.id = i))).foldl (apply) s') i
  | [], s, s', h => by simpa using h
  | r :: L, s, s', h => by
    by_cases hr : r.op.id = i
    · have : apply s r i = apply s' r i := apply_of_eq s s' r i hr
      simp only [List.foldl_cons, List.filter_cons, hr, decide_true, if_true]
      exact foldl_apply_at i L _ _ this
    · have : apply s r i = s' i := by rw [apply_of_ne s r i hr, h]
      simp only [List.foldl_cons, List.filter_cons, hr, decide_false]
      exact foldl_apply_at i L _ _ this

/-! ## The four log theorems -/

/-- **AppendOnly.** `write` never removes or reorders anything: the old log is
a prefix of the new one. -/
theorem write_appendOnly [∀ s, DecidableEq (P s)] (r : Receipt P) :
    AppendOnly (fun L => write L r) := by
  intro L
  show L <+: write L r
  unfold write
  split
  · exact List.prefix_refl L
  · exact List.prefix_append L [r]

/-- **IdempotentPut.** A put whose claim equals (by the claims' decidable
equality: same key, payload, pins and window) the claim currently stored
under its id leaves the log unchanged. -/
theorem idempotentPut [∀ s, DecidableEq (P s)] (L : List (Receipt P))
    (r : Receipt P) (c : Claim P) (hop : r.op = .put c)
    (hcur : latest L (c.id) = some c) : write L r = L := by
  unfold write redundant
  simp [hop, hcur]

/-- Skipping a redundant receipt is sound: the latest state after `write` is
exactly the latest state after applying the receipt. So `IdempotentPut` never
loses information. -/
theorem latest_write [∀ s, DecidableEq (P s)] (L : List (Receipt P))
    (r : Receipt P) : latest (write L r) = apply (latest L) r := by
  unfold write
  by_cases hred : redundant L r = true
  · simp only [hred, if_true]
    funext i
    unfold redundant at hred
    unfold apply
    cases hop : r.op with
    | put c =>
      simp only [hop, decide_eq_true_eq] at hred
      by_cases hi : i = c.id
      · subst hi; simp [hred]
      · simp [hi]
    | retract j =>
      simp only [hop, Option.isNone_iff_eq_none] at hred
      by_cases hi : i = j
      · subst hi; simp [hred]
      · simp [hi]
  · simp only [hred, Bool.false_eq_true, if_false]
    simp [latest, replay, List.foldl_append]

/-- **Prefix lemma.** Receipts numbered after `t` do not change the state at
`t`, wherever they sit in the log. -/
theorem state_append_of_future (L₁ L₂ : List (Receipt P)) (t : Nat)
    (h : ∀ r ∈ L₂, t < r.tx) : state (L₁ ++ L₂) t = state L₁ t := by
  unfold state
  have : L₂.filter (fun r => decide (r.tx ≤ t)) = [] := by
    rw [List.filter_eq_nil_iff]
    intro r hr
    have := h r hr
    simp only [decide_eq_true_eq]
    omega
  rw [List.filter_append, this, List.append_nil]

/-- When every receipt is numbered `t` or less, the state at `t` is the latest
state. -/
theorem state_eq_latest (L : List (Receipt P)) (t : Nat)
    (h : ∀ r ∈ L, r.tx ≤ t) : state L t = latest L := by
  unfold state latest
  rw [List.filter_eq_self.mpr (by intro r hr; simpa using h r hr)]

/-- What `diff` contains: exactly the ids of receipts numbered after `a` and up
to `b`. -/
theorem mem_diff (L : List (Receipt P)) (a b : Nat) (i : C.ClaimId) :
    i ∈ diff L a b ↔ ∃ r ∈ L, a < r.tx ∧ r.tx ≤ b ∧ r.op.id = i := by
  simp [diff, and_assoc]

/-- **DiffIsFootprint.** For `a ≤ b`, an id that `diff` does not list has the
same value in the state at `a` and the state at `b`. Equivalently, every id
whose value changed is listed. (The converse is false: see the module
docstring.) -/
theorem diffIsFootprint (L : List (Receipt P)) (a b : Nat) (hab : a ≤ b)
    (i : C.ClaimId) (hi : i ∉ diff L a b) : state L a i = state L b i := by
  rw [mem_diff] at hi
  unfold state replay
  rw [foldl_apply_at i _ View.empty View.empty rfl,
      foldl_apply_at i (L.filter fun r => decide (r.tx ≤ b)) View.empty View.empty rfl,
      List.filter_filter, List.filter_filter]
  have hf : (L.filter fun r => decide (r.op.id = i) && decide (r.tx ≤ a)) =
      (L.filter fun r => decide (r.op.id = i) && decide (r.tx ≤ b)) := by
    apply List.filter_congr
    intro r hr
    by_cases ht : r.op.id = i
    · have hnot : ¬ (a < r.tx ∧ r.tx ≤ b) := fun hw => hi ⟨r, hr, hw.1, hw.2, ht⟩
      simp only [ht, decide_true, Bool.true_and]
      exact decide_eq_decide.mpr (by constructor <;> intro <;> omega)
    · simp [ht]
  rw [hf]

end World
