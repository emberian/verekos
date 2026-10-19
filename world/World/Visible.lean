/-
# World.Visible — visibility decided by pins, and deny wins

In plain words: a reader's scope says which claim ids and which source
origins (document, range) it allows and which it denies.

- A claim is **denied** when its own id is denied, or one of its source pins
  has a denied origin, or one of its claim pins points at a claim that is
  denied. Denial flows along pins.
- A claim is **allowed** when its own id is explicitly allowed, or it has at
  least one pin and every pin is allowed: a source pin's origin is allowed,
  and a claim pin points at a claim (present in the state) that is allowed.
- A claim is **visible** when it is allowed and not denied.

So **deny wins**: a denied id or a denied origin anywhere below a claim hides
it, even when its own id is explicitly allowed. A claim with no pins is hidden
unless its id is explicitly allowed ("nothing is unattributed").

Recursion is on an explicit depth bound `n` (how many claim-pin hops are
followed). When the bound runs out, the claim counts as denied and not
allowed — hidden. A bound that is too small can hide something; it can never
show something that a deeper look would hide (see `visible_mono`).

Every name here is new to VerEKOS.
-/
import World.Claim

namespace World

set_option autoImplicit false

variable {C : Carriers} {P : C.SchemaId → Type}

/-- A reader's scope. -/
structure Scope (C : Carriers) where
  allowsId : C.ClaimId → Bool
  deniesId : C.ClaimId → Bool
  allowsOrigin : C.SourceId → Option C.Range → Bool
  deniesOrigin : C.SourceId → Option C.Range → Bool

variable (d : ClaimIdDerivation C) (σ : C.ClaimId → Option (Claim C P)) (S : Scope C)

/-- Is the claim denied, looking at most `n` claim-pin hops deep? -/
def denied : Nat → Claim C P → Bool
  | 0, _ => true
  | n + 1, c => S.deniesId (c.id d) || c.pins.any fun p =>
      match p.target with
      | .source doc r => S.deniesOrigin doc r
      | .claim i =>
        match σ i with
        | some c' => denied n c'
        | none => false

/-- Is the claim allowed, looking at most `n` claim-pin hops deep? -/
def allowed : Nat → Claim C P → Bool
  | 0, _ => false
  | n + 1, c => S.allowsId (c.id d) || (!c.pins.isEmpty && c.pins.all fun p =>
      match p.target with
      | .source doc r => S.allowsOrigin doc r
      | .claim i =>
        match σ i with
        | some c' => allowed n c'
        | none => false)

/-- Visible: allowed and not denied. -/
def visible (n : Nat) (c : Claim C P) : Bool :=
  !denied d σ S n c && allowed d σ S n c

/-! ## Deny wins -/

/-- **Deny wins, by id.** A claim whose id is denied is hidden, whatever else
holds — including an explicit allow of the same id. -/
theorem deny_wins_id (n : Nat) (c : Claim C P) (h : S.deniesId (c.id d) = true) :
    visible d σ S n c = false := by
  cases n with
  | zero => simp [visible, denied]
  | succ n => simp [visible, denied, h]

/-- **Deny wins, by origin.** A claim with a source pin whose origin is
denied is hidden, even if its id is explicitly allowed and its other pins are
allowed. -/
theorem deny_wins_origin (n : Nat) (c : Claim C P) (p : Pin C) (hp : p ∈ c.pins)
    (doc : C.SourceId) (r : Option C.Range) (ht : p.target = .source doc r)
    (h : S.deniesOrigin doc r = true) : visible d σ S n c = false := by
  cases n with
  | zero => simp [visible, denied]
  | succ n =>
    have : denied d σ S (n + 1) c = true := by
      simp only [denied, Bool.or_eq_true, List.any_eq_true]
      exact Or.inr ⟨p, hp, by rw [ht]; exact h⟩
    simp [visible, this]

/-- **Denial flows along pins.** A claim pinned to a denied claim is hidden. -/
theorem deny_through_premise (n : Nat) (c : Claim C P) (p : Pin C) (hp : p ∈ c.pins)
    (i : C.ClaimId) (ht : p.target = .claim i) (c' : Claim C P) (hσ : σ i = some c')
    (h : denied d σ S n c' = true) : visible d σ S (n + 1) c = false := by
  have : denied d σ S (n + 1) c = true := by
    simp only [denied, Bool.or_eq_true, List.any_eq_true]
    exact Or.inr ⟨p, hp, by rw [ht]; simp only [hσ]; exact h⟩
  simp [visible, this]

/-- **A conflict is hidden when any alternative's origin is denied.** A
conflict claim pins each alternative claim; if one alternative has a source pin
whose origin the reader is denied, the conflict is hidden from that reader.
(Stated for any claim `k` that pins claims, which is what a conflict is.) -/
theorem conflict_hidden_of_alternative_denied (n : Nat) (k : Claim C P)
    (p : Pin C) (hp : p ∈ k.pins) (i : C.ClaimId) (ht : p.target = .claim i)
    (alt : Claim C P) (hσ : σ i = some alt)
    (q : Pin C) (hq : q ∈ alt.pins) (doc : C.SourceId) (r : Option C.Range)
    (hqt : q.target = .source doc r) (hden : S.deniesOrigin doc r = true) :
    visible d σ S (n + 2) k = false := by
  apply deny_through_premise d σ S (n + 1) k p hp i ht alt hσ
  simp only [denied, Bool.or_eq_true, List.any_eq_true]
  exact Or.inr ⟨q, hq, by rw [hqt]; exact hden⟩

/-- **Nothing is unattributed.** A claim with no pins is hidden unless its id
is explicitly allowed. -/
theorem unpinned_hidden (n : Nat) (c : Claim C P) (hpins : c.pins = [])
    (hid : S.allowsId (c.id d) = false) : visible d σ S n c = false := by
  cases n with
  | zero => simp [visible, denied]
  | succ n => simp [visible, allowed, hpins, hid]

/-- **Visibility is decided by pins.** If a claim is visible and its id is not
explicitly allowed, then it has a pin, and every pin is visible in its own
way: a source pin's origin is allowed and not denied; a claim pin points at a
claim present in the state that is itself visible one hop shallower. -/
theorem visible_pins (n : Nat) (c : Claim C P) (hv : visible d σ S (n + 1) c = true)
    (hid : S.allowsId (c.id d) = false) :
    c.pins ≠ [] ∧ ∀ p ∈ c.pins,
      (∀ doc r, p.target = .source doc r →
        S.allowsOrigin doc r = true ∧ S.deniesOrigin doc r = false) ∧
      (∀ i, p.target = .claim i → ∃ c', σ i = some c' ∧ visible d σ S n c' = true) := by
  simp only [visible, Bool.and_eq_true, Bool.not_eq_true'] at hv
  obtain ⟨hnd, hal⟩ := hv
  simp only [allowed, hid, Bool.false_or, Bool.and_eq_true, Bool.not_eq_true',
    List.isEmpty_eq_false_iff, List.all_eq_true] at hal
  simp only [denied, Bool.or_eq_false_iff, List.any_eq_false] at hnd
  obtain ⟨hne, hall⟩ := hal
  refine ⟨hne, fun p hp => ⟨fun doc r ht => ?_, fun i ht => ?_⟩⟩
  · have h1 := hall p hp
    have h2 := hnd.2 p hp
    rw [ht] at h1 h2
    exact ⟨h1, by simpa using h2⟩
  · have h1 := hall p hp
    have h2 := hnd.2 p hp
    rw [ht] at h1 h2
    cases hσ : σ i with
    | none => simp [hσ] at h1
    | some c' =>
      simp only [hσ] at h1 h2
      exact ⟨c', rfl, by simp [visible, h1, h2]⟩

/-! ## The depth bound only ever errs toward hiding -/

theorem denied_anti : ∀ (n : Nat) (c : Claim C P),
    denied d σ S (n + 1) c = true → denied d σ S n c = true
  | 0, _, _ => rfl
  | n + 1, c, h => by
    simp only [denied, Bool.or_eq_true, List.any_eq_true] at h ⊢
    rcases h with h | ⟨p, hp, hpt⟩
    · exact Or.inl h
    · refine Or.inr ⟨p, hp, ?_⟩
      split at hpt
      · exact hpt
      · rename_i i _
        split at hpt
        · rename_i c' _
          exact denied_anti n c' hpt
        · exact absurd hpt (by simp)

theorem allowed_mono : ∀ (n : Nat) (c : Claim C P),
    allowed d σ S n c = true → allowed d σ S (n + 1) c = true
  | 0, _, h => by simp [allowed] at h
  | n + 1, c, h => by
    simp only [allowed, Bool.or_eq_true, Bool.and_eq_true, List.all_eq_true] at h ⊢
    rcases h with h | ⟨hne, hall⟩
    · exact Or.inl h
    · refine Or.inr ⟨hne, fun p hp => ?_⟩
      have hpt := hall p hp
      split at hpt
      · exact hpt
      · split at hpt
        · rename_i c' _
          exact allowed_mono n c' hpt
        · exact absurd hpt (by simp)

/-- **A small bound never shows what a deeper look hides.** If a claim is
visible at depth `n`, it is visible at depth `n + 1`. Read the other way: if
the deeper look hides a claim, the shallower look hides it too. Raising the
bound can only turn hidden into visible (when the shallower look ran out),
never visible into hidden. -/
theorem visible_mono (n : Nat) (c : Claim C P) (h : visible d σ S n c = true) :
    visible d σ S (n + 1) c = true := by
  simp only [visible, Bool.and_eq_true, Bool.not_eq_true'] at h ⊢
  obtain ⟨hnd, hal⟩ := h
  refine ⟨?_, allowed_mono d σ S n c hal⟩
  cases hd : denied d σ S (n + 1) c
  · rfl
  · rw [denied_anti d σ S n c hd] at hnd
    exact absurd hnd (by simp)

end World
