/-
# World.TxOrder — transaction numbers that increase along the log

`World.Log` never required transaction numbers to increase along the log
(review R1, finding M9). `state L t` is a replay of the receipts numbered `t`
or less in list order, and those can sit anywhere in the list. This file adds
the well-formedness rule and what it buys, without changing any existing
definition.

- **`TxMonotone L`**: transaction numbers strictly increase along the list.
- **`write` keeps it** when the new receipt's number exceeds the last one's
  (`txMonotone_write`).
- Under `TxMonotone`, **the receipts numbered `t` or less form a prefix**:
  `state L t` is the replay of the longest prefix whose numbers are all `t`
  or less (`state_eq_replay_takeWhile`). The state at `t` is prefix-closed,
  not just filter-closed.
- Under `TxMonotone`, **`diff a b` is exactly the ids of one contiguous
  segment**: the receipts after the prefix up to `a`, up to `b`
  (`diff_eq_segment`, `segment_contiguous`).

Every name here is new to VerEKOS.
-/
import World.Log

namespace World

set_option autoImplicit false

variable [C : Carriers] {P : C.SchemaId → Type} [d : ClaimIdDerivation]

/-- Transaction numbers strictly increase along the log. -/
def TxMonotone (L : List (Receipt P)) : Prop := L.Pairwise fun r s => r.tx < s.tx

instance (L : List (Receipt P)) : Decidable (TxMonotone L) := by
  unfold TxMonotone; infer_instance

omit d in
/-- In a monotone log, every receipt is numbered at most the last one. -/
theorem tx_le_last (L : List (Receipt P)) (h : TxMonotone L) (last : Receipt P)
    (hl : L.getLast? = some last) (r : Receipt P) (hr : r ∈ L) : r.tx ≤ last.tx := by
  obtain ⟨ys, rfl⟩ := List.getLast?_eq_some_iff.mp hl
  rcases List.mem_append.mp hr with hy | hy
  · unfold TxMonotone at h
    rw [List.pairwise_append] at h
    exact Nat.le_of_lt (h.2.2 r hy last (List.mem_singleton_self _))
  · rw [List.mem_singleton.mp hy]; exact Nat.le_refl _

/-- **`write` keeps the log monotone** when the new receipt is numbered after
the last one (or the log is empty). -/
theorem txMonotone_write [∀ s, DecidableEq (P s)] (L : List (Receipt P)) (r : Receipt P)
    (h : TxMonotone L) (hr : ∀ last, L.getLast? = some last → last.tx < r.tx) :
    TxMonotone (write L r) := by
  unfold write
  split
  · exact h
  · unfold TxMonotone
    rw [List.pairwise_append]
    refine ⟨h, List.pairwise_singleton _ _, fun x hx y hy => ?_⟩
    rw [List.mem_singleton.mp hy]
    cases hlast : L.getLast? with
    | none => simp [List.getLast?_eq_none_iff.mp hlast] at hx
    | some last => exact Nat.lt_of_le_of_lt (tx_le_last L h last hlast x hx) (hr last hlast)

omit d in
/-- In a monotone log, the receipts numbered `t` or less are a prefix. -/
theorem filter_eq_takeWhile (L : List (Receipt P)) (h : TxMonotone L) (t : Nat) :
    L.filter (fun r => decide (r.tx ≤ t)) = L.takeWhile (fun r => decide (r.tx ≤ t)) := by
  induction L with
  | nil => rfl
  | cons r rs ih =>
    unfold TxMonotone at h
    rw [List.pairwise_cons] at h
    by_cases hr : r.tx ≤ t
    · simp [hr, ih h.2]
    · have : rs.filter (fun r => decide (r.tx ≤ t)) = [] := by
        rw [List.filter_eq_nil_iff]
        intro x hx
        have := h.1 x hx
        simp only [decide_eq_true_eq]
        omega
      simp [hr, this]

/-- **The state at `t` is the replay of the longest prefix numbered `t` or
less.** -/
theorem state_eq_replay_takeWhile (L : List (Receipt P)) (h : TxMonotone L) (t : Nat) :
    state L t = replay (L.takeWhile fun r => decide (r.tx ≤ t)) := by
  unfold state
  rw [filter_eq_takeWhile L h t]

omit d in
/-- That prefix is a prefix. -/
theorem takeWhile_prefix_log (L : List (Receipt P)) (t : Nat) :
    (L.takeWhile fun r => decide (r.tx ≤ t)) <+: L :=
  List.takeWhile_prefix _

/-- The segment `(a, b]`: after the prefix numbered `a` or less, the receipts
up to `b`. -/
def segment (L : List (Receipt P)) (a b : Nat) : List (Receipt P) :=
  (L.dropWhile fun r => decide (r.tx ≤ a)).takeWhile fun r => decide (r.tx ≤ b)

omit d in
/-- **The segment is contiguous:** the log is the prefix up to `a`, then the
segment, then the rest. -/
theorem segment_contiguous (L : List (Receipt P)) (a b : Nat) :
    L = (L.takeWhile fun r => decide (r.tx ≤ a)) ++ segment L a b ++
      ((L.dropWhile fun r => decide (r.tx ≤ a)).dropWhile fun r => decide (r.tx ≤ b)) := by
  unfold segment
  rw [List.append_assoc, List.takeWhile_append_dropWhile, List.takeWhile_append_dropWhile]

omit d in
theorem filter_window_eq_segment (L : List (Receipt P)) (h : TxMonotone L) (a b : Nat) :
    L.filter (fun r => decide (a < r.tx ∧ r.tx ≤ b)) = segment L a b := by
  induction L with
  | nil => rfl
  | cons r rs ih =>
    have hm := h
    unfold TxMonotone at h
    rw [List.pairwise_cons] at h
    unfold segment at ih ⊢
    by_cases ha : r.tx ≤ a
    · have : ¬ (a < r.tx ∧ r.tx ≤ b) := fun hw => by omega
      simp only [List.filter_cons, this, decide_false, Bool.false_eq_true, if_false,
        List.dropWhile_cons, ha, decide_true, if_true]
      exact ih h.2
    · simp only [List.dropWhile_cons, ha, decide_false, Bool.false_eq_true, if_false]
      -- every later receipt is numbered above `a`
      have hrest : rs.filter (fun r => decide (a < r.tx ∧ r.tx ≤ b)) =
          rs.filter (fun r => decide (r.tx ≤ b)) := by
        apply List.filter_congr
        intro x hx
        have := h.1 x hx
        simp only [decide_eq_decide]
        constructor
        · exact fun hw => hw.2
        · exact fun hb => ⟨by omega, hb⟩
      by_cases hb : r.tx ≤ b
      · have hw : a < r.tx ∧ r.tx ≤ b := ⟨by omega, hb⟩
        simp only [List.filter_cons, hw, and_self, decide_true, if_true, List.takeWhile_cons]
        rw [hrest, filter_eq_takeWhile rs h.2 b]
      · have hw : ¬ (a < r.tx ∧ r.tx ≤ b) := fun hw => hb hw.2
        have hnil : rs.filter (fun r => decide (r.tx ≤ b)) = [] := by
          rw [List.filter_eq_nil_iff]
          intro x hx
          have := h.1 x hx
          simp only [decide_eq_true_eq]
          omega
        rw [List.filter_cons, if_neg (by simp only [decide_eq_true_eq]; exact hw), hrest, hnil]
        simp [hb]

/-- **Under monotone numbers, `diff a b` is exactly the ids of the contiguous
segment `(a, b]`, in log order.** -/
theorem diff_eq_segment (L : List (Receipt P)) (h : TxMonotone L) (a b : Nat) :
    diff L a b = (segment L a b).map fun r => r.op.id := by
  unfold diff
  rw [filter_window_eq_segment L h a b]

end World
