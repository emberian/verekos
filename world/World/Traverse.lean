/-
# World.Traverse — reachability that crosses only facts

In plain words: an **edge** is a claim that names two claims, a "from" and a
"to" (`EdgeView.ends`). A traversal starts at a seed id and follows edges, up
to a hop bound, over the edge types the caller asks for (`T`). It crosses an
edge only when:
- the edge is current (it is the claim stored under its id);
- its type is one the caller asked for;
- **the edge's own status is a fact** for its schema (`Schema.isFact`);
- **both endpoints exist and their statuses are facts** too.

Status is always defined here: it starts at the schema's initial status and
changes only by admitted reviews (`World.Status`). EKOS differs in two ways:
- `is_pending_review` reads a *missing* `status` property as confirmed
  (`/Users/ember/dev/EKOS/ekos/crates/kir/src/lib.rs:480-485`). An edge whose
  status was never written is walked as a fact there.
- `tool_dependents` checks only the edge, never the endpoints
  (`/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/mcp.rs:1933-1961`).

The theorems:
- `pending_edge_never_crossed`: an edge whose status is not a fact is never
  crossed; `reach_trivial_of_all_pending`: if every edge of the asked types is
  pending, nothing but the seed is reachable.
- `unreviewed_hypothesis_edge_not_crossed`: an edge whose schema starts in a
  non-fact status (for example `hypothesis` or `unconfirmed`) is not crossed
  until an admitted review exists — the case EKOS's missing-status default
  gets wrong.
- `reach_mono_confirm`: adding a confirming review can only add reachable
  nodes.
- `reach_mono_hops`: a larger hop bound can only add reachable nodes.

Every name here is new to VerEKOS.
-/
import World.Status

namespace World

set_option autoImplicit false

variable [C : Carriers] {P : C.SchemaId → Type}

/-- How to read an edge claim's endpoints (from, to); `none` for a claim that
is not an edge. -/
structure EdgeView [C : Carriers] (P : C.SchemaId → Type) where
  ends : Claim P → Option (C.ClaimId × C.ClaimId)

variable (R : ReviewSchema P) (reg : Registry P) [d : ClaimIdDerivation]
  (E : EdgeView P) (T : C.SchemaId → Bool)

/-- The claim's current status is a fact for its schema. -/
def IsFactNow (L : List (Receipt P)) (c : Claim P) : Prop :=
  (reg c.key.schema).isFact (status R reg L c) = true

instance (L : List (Receipt P)) (c : Claim P) : Decidable (IsFactNow R reg L c) := by
  unfold IsFactNow; infer_instance

/-- The id holds a claim whose current status is a fact. -/
def NodeFact (L : List (Receipt P)) (i : C.ClaimId) : Prop :=
  ∃ c, latest L i = some c ∧ IsFactNow R reg L c

/-- Edge `e` may be crossed from `a` to `b`. -/
structure Crosses (L : List (Receipt P)) (e : Claim P) (a b : C.ClaimId) : Prop where
  current : latest L (e.id) = some e
  typed : T e.key.schema = true
  ends : E.ends e = some (a, b)
  edgeFact : IsFactNow R reg L e
  fromFact : NodeFact R reg L a
  toFact : NodeFact R reg L b

/-- `Reach L n x z`: `z` is reachable from the seed `x` in at most `n` hops. -/
inductive Reach (L : List (Receipt P)) : Nat → C.ClaimId → C.ClaimId → Prop
  | here (n : Nat) (x : C.ClaimId) : Reach L n x x
  | hop {n : Nat} {x y z : C.ClaimId} (e : Claim P) :
      Reach L n x y → Crosses R reg E T L e y z → Reach L (n + 1) x z

/-! ## Pending edges are never crossed -/

/-- **A pending edge is never crossed.** -/
theorem pending_edge_never_crossed (L : List (Receipt P)) (e : Claim P)
    (a b : C.ClaimId) (h : (reg e.key.schema).isFact (status R reg L e) = false) :
    ¬ Crosses R reg E T L e a b := fun hc => by
  have := hc.edgeFact
  unfold IsFactNow at this
  rw [h] at this
  exact absurd this (by simp)

/-- **If every edge of the asked types is pending, only the seed is
reachable.** -/
theorem reach_trivial_of_all_pending (L : List (Receipt P))
    (hall : ∀ e, T e.key.schema = true → E.ends e ≠ none →
      (reg e.key.schema).isFact (status R reg L e) = false)
    {n : Nat} {x z : C.ClaimId} (h : Reach R reg E T L n x z) : x = z := by
  induction h with
  | here => rfl
  | hop e _ hc ih =>
    exact absurd hc (pending_edge_never_crossed R reg E T L e _ _
      (hall e hc.typed (by rw [hc.ends]; simp)))

/-- With no admitted review, the status is the schema's initial status. -/
theorem status_of_no_reviews (L : List (Receipt P)) (c : Claim P)
    (h : admittedReviews R reg L c.key = []) :
    status R reg L c = (reg c.key.schema).initial := by
  simp [status, statusAt, h]

/-- **An unreviewed hypothesis edge is not crossed.** If an edge's schema
starts in a status that is not a fact (`hypothesis`, `unconfirmed`, …) and no
admitted review of the edge exists, the edge is not crossed. In EKOS the same
edge with no `status` property would be walked as confirmed. -/
theorem unreviewed_hypothesis_edge_not_crossed (L : List (Receipt P)) (e : Claim P)
    (a b : C.ClaimId)
    (hinit : (reg e.key.schema).isFact (reg e.key.schema).initial = false)
    (hnone : admittedReviews R reg L e.key = []) :
    ¬ Crosses R reg E T L e a b := by
  apply pending_edge_never_crossed
  rw [status_of_no_reviews R reg L e hnone]
  exact hinit

/-- **An unreviewed hypothesis node blocks traversal too.** An edge into (or
out of) a node whose schema starts in a non-fact status and that has no
admitted review is not crossed, even if the edge itself is a fact. EKOS
checks only the edge. -/
theorem unreviewed_hypothesis_node_blocks (L : List (Receipt P)) (e c : Claim P)
    (a b : C.ClaimId) (hb : latest L b = some c)
    (hinit : (reg c.key.schema).isFact (reg c.key.schema).initial = false)
    (hnone : admittedReviews R reg L c.key = []) :
    ¬ Crosses R reg E T L e a b := fun hc => by
  obtain ⟨c', hc', hf⟩ := hc.toFact
  rw [hb] at hc'
  cases hc'
  unfold IsFactNow at hf
  rw [status_of_no_reviews R reg L c hnone, hinit] at hf
  exact absurd hf (by simp)

/-! ## Monotonicity -/

/-- **A larger hop bound only adds.** -/
theorem reach_mono_hops (L : List (Receipt P)) {n : Nat} {x z : C.ClaimId}
    (h : Reach R reg E T L n x z) : Reach R reg E T L (n + 1) x z := by
  induction h with
  | here n x => exact .here _ _
  | hop e _ hc ih => exact .hop e ih hc

theorem reach_mono_hops_le (L : List (Receipt P)) {n m : Nat} (hnm : n ≤ m)
    {x z : C.ClaimId} (h : Reach R reg E T L n x z) : Reach R reg E T L m x z := by
  induction hnm with
  | refl => exact h
  | step _ ih => exact reach_mono_hops R reg E T L ih

section confirm

/-- The state stores every claim under its own id. -/
theorem foldl_apply_id : ∀ (L : List (Receipt P)) (s : View P),
    (∀ i c, s i = some c → c.id = i) →
    ∀ i c, (L.foldl (apply) s) i = some c → c.id = i
  | [], _, hs, i, c, h => hs i c h
  | r :: L, s, hs, i, c, h => by
    refine foldl_apply_id L (apply s r) ?_ i c h
    intro j c' hj
    unfold apply at hj
    cases hop : r.op with
    | put c₀ =>
      simp only [hop] at hj
      split at hj
      · rename_i hjc
        injection hj with hj
        subst hj
        exact hjc.symm
      · exact hs j c' hj
    | retract k =>
      simp only [hop] at hj
      split at hj
      · cases hj
      · exact hs j c' hj

theorem latest_id (L : List (Receipt P)) (i : C.ClaimId) (c : Claim P)
    (h : latest L i = some c) : c.id = i :=
  foldl_apply_id L View.empty (by intro _ _ h; cases h) i c h

/-- Putting a claim under a fresh id changes the state only at that id. -/
theorem latest_append_fresh (L : List (Receipt P)) (r : Receipt P) (rv : Claim P)
    (hop : r.op = .put rv) (j : C.ClaimId) (hj : j ≠ rv.id) :
    latest (L ++ [r]) j = latest L j := by
  simp [latest, replay, List.foldl_append, apply, hop, hj]

/-- **Adding a confirming review can only add reachable nodes.**

The review `rv` is put by receipt `r` under a fresh id. It is an admitted
review of a claim `t` (current in the state), pinned at `t`'s current core,
and its decision `s` is a fact for `t`'s schema. Then everything reachable
before is reachable after.

Why each hypothesis is needed (each is false without it):
- *fresh id*: putting the review over an existing claim replaces that claim in
  the state, which can remove a node or an edge;
- *at the current core*: a review at an old core turns `t`'s status into
  `needsReview`, which may not be a fact;
- *decision is a fact*: a rejecting review removes `t` from traversal. -/
theorem reach_mono_confirm (L : List (Receipt P)) (r : Receipt P) (rv t : Claim P)
    (s : Status) (hop : r.op = .put rv) (hfresh : latest L (rv.id) = none)
    (ht : latest L (t.id) = some t)
    (hrev : reviewOf R reg t.key r = some (t.core reg, s))
    (hfact : (reg t.key.schema).isFact s = true)
    {n : Nat} {x z : C.ClaimId} (h : Reach R reg E T L n x z) :
    Reach R reg E T (L ++ [r]) n x z := by
  -- The review is admitted only for `t`'s id.
  have honly : ∀ (k : ClaimKey) dg s', reviewOf R reg k r = some (dg, s') →
      ClaimIdDerivation.claimId k = t.id := by
    intro k dg s' hk
    obtain ⟨c₁, hop₁, has₁, -⟩ := (reviewOf_eq_some R reg k r dg s').mp hk
    obtain ⟨c₂, hop₂, has₂, -⟩ := (reviewOf_eq_some R reg t.key r _ s).mp hrev
    rw [hop₁] at hop₂
    cases hop₂
    rw [has₁] at has₂
    simp only [Option.some.injEq, Prod.mk.injEq] at has₂
    exact has₂.1
  -- Claims present before keep their place.
  have hkeep : ∀ j c, latest L j = some c → latest (L ++ [r]) j = some c := by
    intro j c hj
    have hne : j ≠ rv.id := by rintro rfl; rw [hfresh] at hj; cases hj
    rw [latest_append_fresh L r rv hop j hne, hj]
  -- Facts present before stay facts.
  have hfactKeep : ∀ c, latest L (c.id) = some c → IsFactNow R reg L c →
      IsFactNow R reg (L ++ [r]) c := by
    intro c hc hf
    by_cases hct : c.id = t.id
    · rw [hct, ht] at hc
      injection hc with hc
      subst hc
      unfold IsFactNow
      rw [reviewTakesEffect R reg L t r s hrev]
      exact hfact
    · unfold IsFactNow at hf ⊢
      have hnone : ∀ r' ∈ [r], reviewOf R reg c.key r' = none := by
        intro r' hr'
        simp only [List.mem_singleton] at hr'
        subst hr'
        cases hk : reviewOf R reg c.key r' with
        | none => rfl
        | some v => exact absurd (honly c.key v.1 v.2 hk) hct
      unfold status
      rw [statusAt_append_of_no_review R reg L [r] c.key _ hnone]
      exact hf
  have hnode : ∀ i, NodeFact R reg L i → NodeFact R reg (L ++ [r]) i := by
    rintro i ⟨c, hc, hf⟩
    have hid : c.id = i := latest_id L i c hc
    subst hid
    exact ⟨c, hkeep _ c hc, hfactKeep c hc hf⟩
  induction h with
  | here n x => exact .here _ _
  | hop e _ hc ih =>
    exact .hop e ih
      { current := hkeep _ _ hc.current
        typed := hc.typed
        ends := hc.ends
        edgeFact := hfactKeep e hc.current hc.edgeFact
        fromFact := hnode _ hc.fromFact
        toFact := hnode _ hc.toFact }

end confirm

end World
