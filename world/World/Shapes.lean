/-
# World.Shapes — the other document shapes of exploration 01 §2.1

`World.Document` gave `ekos/object/v1`. This file gives the rest, as Lean
data beside it:

| Shape | Holds | Derived on the way in, checked on the way back |
|---|---|---|
| `ekos/source/v1` | a header atom; one text atom per statement | each atom id is derived from the statement's structural key |
| `ekos/manifest/v1` | external links keyed by logical key, each live or unlinked | the current set; a compile unlinks what it no longer emits |
| `ekos/conflict/v1` | a header (subject, attribute, type, **signature**); one container per claim: a meta atom with the normalized value and a snapshot pin of that claim's statement; a `Disputes` link to the subject; **no `chosen`** | the signature, from the attribute and the members' (value, source) |
| `ekos/review/v1` | appended decision containers, each a decision atom plus a snapshot pin of the reviewed header atom (one atom) | each pin names exactly one atom |
| `ekos/compile-run/v1` | input pins with read heights; compiler identity; output list; command-bytes digest | nothing; the record is stored as given |
| `ekos/replay-attestation/v1` | the run, the verifier, the outputs and command digest the verifier got | the `replayedDeterministic` label |

For each shape there is a content record (what the shape means), an
`encode` into the document, and a `decode` back. Three kinds of theorem:
- `decode (encode x) = x`;
- `encode (decode D) = D` for every document whose derived fields are
  consistent — so the derived fields are the only thing a document can get
  wrong;
- for shapes that pin atoms, the (source document, atom revision) pins are
  kept both ways.

The source shape also gets "a pin moves exactly when its statement changed":
on re-import an atom keeps its revision iff its bytes are unchanged. The
manifest gets "a later compile that no longer emits an object makes it not
current" (`not_current_after_unemit`), the thing EKOS cannot do.

Revisions in this file are `Nat` counters. A write takes a revision larger
than any before it, which is what makes "same revision" mean "not written
since". minidregg's revisions are `OperationId`s, and its freshness is the
same property.

Lane W17 has not yet recorded what the deployed client can express
(`notes/W17-slice1.md` did not exist when this was written). These shapes
follow exploration 01 as written.

Every name here is new to VerEKOS.
-/
import World.Document

namespace World

set_option autoImplicit false

variable {C : Carriers}

/-! ## `ekos/source/v1` -/

/-- The source header atom (`ekos/source-header/v1`). -/
structure SourceHeader (C : Carriers) where
  sourceKey : List C.KeyPart
  path : C.Digest
  redactionTable : C.Digest
  importer : C.Digest
  pipeline : C.Digest
  deriving DecidableEq

/-- One statement of an imported file: its structural key (for example
`create-table:customers`) and its redacted bytes (a digest here). -/
structure Statement (C : Carriers) where
  key : List C.KeyPart
  bytes : C.Digest
  deriving DecidableEq

/-- A text atom: its id, the structural key the id was derived from, its
revision, its bytes. -/
structure TextAtom (C : Carriers) (A : Type) where
  id : A
  key : List C.KeyPart
  rev : Nat
  bytes : C.Digest
  deriving DecidableEq

/-- An `ekos/source/v1` document. -/
structure SourceDoc (C : Carriers) (A : Type) where
  header : SourceHeader C
  atoms : List (TextAtom C A)
  deriving DecidableEq

section source
variable {A : Type} [DecidableEq A] (atomOf : List C.KeyPart → A)

/-- Import a file: one text atom per statement, written at revision `r`, its
id derived from its structural key. -/
def importSource (h : SourceHeader C) (stmts : List (Statement C)) (r : Nat) : SourceDoc C A :=
  ⟨h, stmts.map fun s => ⟨atomOf s.key, s.key, r, s.bytes⟩⟩

/-- The statements a source document holds. -/
def SourceDoc.statements {A : Type} (D : SourceDoc C A) : List (Statement C) :=
  D.atoms.map fun a => ⟨a.key, a.bytes⟩

/-- Every atom's id is the one derived from its key. -/
def SourceDoc.WellKeyed (D : SourceDoc C A) : Prop := ∀ a ∈ D.atoms, a.id = atomOf a.key

/-- The (atom id, revision) pairs a source document offers to pins. -/
def SourceDoc.atomPins {A : Type} (D : SourceDoc C A) : List (A × Nat) :=
  D.atoms.map fun a => (a.id, a.rev)

/-- **Decoding an import gives back the statements.** -/
theorem statements_importSource (h : SourceHeader C) (stmts : List (Statement C)) (r : Nat) :
    (importSource atomOf h stmts r).statements = stmts := by
  simp [importSource, SourceDoc.statements, Function.comp_def]

/-- An import is well keyed. -/
theorem importSource_wellKeyed (h : SourceHeader C) (stmts : List (Statement C)) (r : Nat) :
    (importSource atomOf h stmts r).WellKeyed atomOf := by
  intro a ha
  simp only [importSource, List.mem_map] at ha
  obtain ⟨s, -, rfl⟩ := ha
  rfl

/-- **Re-encoding a well-keyed document whose atoms share one revision gives
back exactly the document.** -/
theorem importSource_statements (D : SourceDoc C A) (r : Nat) (hk : D.WellKeyed atomOf)
    (hr : ∀ a ∈ D.atoms, a.rev = r) : importSource atomOf D.header D.statements r = D := by
  obtain ⟨h, atoms⟩ := D
  simp only [importSource, SourceDoc.statements, List.map_map, SourceDoc.mk.injEq, true_and]
  conv_rhs => rw [← List.map_id atoms]
  apply List.map_congr_left
  intro a ha
  obtain ⟨i, k, rv, b⟩ := a
  simp only [Function.comp_apply, id_eq, TextAtom.mk.injEq]
  exact ⟨(hk _ ha).symm, rfl, (hr _ ha).symm, rfl⟩

/-- **An import's atom pins are exactly its statements' derived ids at the
import revision.** -/
theorem atomPins_importSource (h : SourceHeader C) (stmts : List (Statement C)) (r : Nat)
    (x : A × Nat) :
    x ∈ (importSource atomOf h stmts r).atomPins ↔ ∃ s ∈ stmts, x = (atomOf s.key, r) := by
  simp [importSource, SourceDoc.atomPins, eq_comm]

/-- Re-import at revision `r`: a statement whose key already has an atom with
the same bytes keeps that atom (and its revision); any other statement gets a
fresh atom at `r`. -/
def reimport (D : SourceDoc C A) (stmts : List (Statement C)) (r : Nat) : SourceDoc C A :=
  ⟨D.header, stmts.map fun s =>
    match D.atoms.find? (fun a => a.key == s.key) with
    | some a => if a.bytes = s.bytes then a else ⟨atomOf s.key, s.key, r, s.bytes⟩
    | none => ⟨atomOf s.key, s.key, r, s.bytes⟩⟩

/-- **Re-importing an unchanged file changes nothing**, when the document is
well keyed and its keys are distinct. -/
theorem reimport_unchanged (D : SourceDoc C A) (r : Nat) (hk : D.WellKeyed atomOf)
    (hnd : (D.atoms.map (·.key)).Nodup) : reimport atomOf D D.statements r = D := by
  obtain ⟨h, atoms⟩ := D
  simp only [reimport, SourceDoc.statements, List.map_map, SourceDoc.mk.injEq, true_and]
  conv_rhs => rw [← List.map_id atoms]
  apply List.map_congr_left
  intro a ha
  simp only [Function.comp_apply, id_eq]
  have hfind : atoms.find? (fun b => b.key == a.key) = some a := by
    rw [List.find?_eq_some_iff_append]
    obtain ⟨l₁, l₂, rfl⟩ := List.append_of_mem ha
    refine ⟨by simp, l₁, l₂, rfl, fun b hb => ?_⟩
    simp only [List.map_append, List.map_cons] at hnd
    have := List.nodup_append.mp hnd
    simp only [beq_iff_eq, Bool.not_eq_true]
    rw [beq_eq_false_iff_ne]
    intro hba
    exact this.2.2 _ (List.mem_map_of_mem hb) _ List.mem_cons_self hba
  rw [hfind]
  simp

/-- **A pin moves exactly when its statement changed.** After re-import at a
fresh revision `r` (larger than every revision in the document), the atom for
statement `s`, whose key had atom `a`, keeps `a`'s revision iff `s`'s bytes
equal `a`'s. -/
theorem reimport_rev_iff (D : SourceDoc C A) (stmts : List (Statement C)) (r : Nat)
    (hfresh : ∀ a ∈ D.atoms, a.rev < r) (s : Statement C) (a : TextAtom C A)
    (ha : D.atoms.find? (fun b => b.key == s.key) = some a) :
    (match D.atoms.find? (fun b => b.key == s.key) with
      | some a => if a.bytes = s.bytes then a else ⟨atomOf s.key, s.key, r, s.bytes⟩
      | none => ⟨atomOf s.key, s.key, r, s.bytes⟩ : TextAtom C A).rev = a.rev ↔
      a.bytes = s.bytes := by
  rw [ha]
  have hlt := hfresh a (List.mem_of_find?_eq_some ha)
  by_cases hb : a.bytes = s.bytes
  · simp [hb]
  · simp only [hb, if_false, iff_false]
    omega

end source

/-! ## `ekos/manifest/v1` -/

/-- One manifest entry: an external link whose authority is the logical key
and whose path is the compiled cell; `live = false` once unlinked (the
tombstone is kept). -/
structure ManifestLink (C : Carriers) where
  key : List C.KeyPart
  cell : C.ClaimId
  live : Bool
  deriving DecidableEq

/-- An `ekos/manifest/v1` document. -/
structure Manifest (C : Carriers) where
  links : List (ManifestLink C)
  deriving DecidableEq

/-- The current set: the live entries. -/
def Manifest.current (M : Manifest C) : List (List C.KeyPart × C.ClaimId) :=
  (M.links.filter (·.live)).map fun l => (l.key, l.cell)

/-- A compile that emits `emitted`: unlink every live entry it no longer
emits, link every emitted entry not already live. Nothing is deleted. -/
def Manifest.compile (M : Manifest C) (emitted : List (List C.KeyPart × C.ClaimId)) :
    Manifest C :=
  ⟨M.links.map (fun l => if l.live && !(emitted.contains (l.key, l.cell))
      then { l with live := false } else l) ++
    (emitted.filter fun e => !(M.current.contains e)).map fun e => ⟨e.1, e.2, true⟩⟩

/-- A manifest holding exactly a current set. -/
def Manifest.ofCurrent (es : List (List C.KeyPart × C.ClaimId)) : Manifest C :=
  ⟨es.map fun e => ⟨e.1, e.2, true⟩⟩

theorem current_ofCurrent (es : List (List C.KeyPart × C.ClaimId)) :
    (Manifest.ofCurrent es).current = es := by
  simp [Manifest.ofCurrent, Manifest.current, Function.comp_def]

/-- **After a compile, the current set is exactly what it emitted.** -/
theorem mem_current_compile (M : Manifest C) (emitted : List (List C.KeyPart × C.ClaimId))
    (e : List C.KeyPart × C.ClaimId) :
    e ∈ (M.compile emitted).current ↔ e ∈ emitted := by
  simp only [Manifest.compile, Manifest.current, List.filter_append, List.map_append,
    List.mem_append, List.mem_map, List.mem_filter, Function.comp_def]
  constructor
  · rintro (⟨l, ⟨hl, hlive⟩, rfl⟩ | ⟨l, ⟨⟨e', ⟨he', -⟩, rfl⟩, -⟩, rfl⟩)
    · obtain ⟨l₀, hl₀, rfl⟩ := hl
      by_cases h : l₀.live && !(emitted.contains (l₀.key, l₀.cell))
      · simp [h] at hlive
      · simp only [h, Bool.false_eq_true, if_false] at hlive ⊢
        simp only [hlive, Bool.true_and, Bool.not_eq_true', Bool.not_eq_false] at h
        simpa using h
    · exact he'
  · intro he
    by_cases hc : (M.links.filter (·.live)).map (fun l => (l.key, l.cell)) |>.contains e
    · left
      simp only [List.contains_iff_mem, List.mem_map, List.mem_filter] at hc
      obtain ⟨l, ⟨hl, hlive⟩, rfl⟩ := hc
      refine ⟨l, ⟨⟨l, hl, ?_⟩, ?_⟩, rfl⟩
      · simp [hlive, List.contains_iff_mem.mpr he]
      · exact hlive
    · right
      refine ⟨⟨e.1, e.2, true⟩, ⟨⟨e, ⟨he, ?_⟩, rfl⟩, rfl⟩, rfl⟩
      simpa [Manifest.current] using hc

/-- **An object a later compile no longer emits is no longer current.** -/
theorem not_current_after_unemit (M : Manifest C) (emitted : List (List C.KeyPart × C.ClaimId))
    (e : List C.KeyPart × C.ClaimId) (h : e ∉ emitted) : e ∉ (M.compile emitted).current :=
  fun he => h ((mem_current_compile M emitted e).mp he)

/-- **History is kept.** Every entry ever in the manifest is still there after
a compile (live or unlinked), with the same key and cell. -/
theorem history_kept (M : Manifest C) (emitted : List (List C.KeyPart × C.ClaimId))
    (l : ManifestLink C) (hl : l ∈ M.links) :
    ∃ l' ∈ (M.compile emitted).links, l'.key = l.key ∧ l'.cell = l.cell := by
  refine ⟨if l.live && !(emitted.contains (l.key, l.cell)) then { l with live := false } else l,
    List.mem_append_left _ (List.mem_map_of_mem hl), ?_⟩
  split <;> simp

/-! ## `ekos/conflict/v1` -/

/-- The conflict header atom. -/
structure ConflictHeader (C : Carriers) where
  subject : C.ClaimId
  attribute : C.Digest
  conflictType : C.Digest
  signature : C.Digest
  deriving DecidableEq

/-- One claim's container: a meta atom with its normalized value, and a
snapshot pin of that claim's statement. -/
structure ConflictMember (C : Carriers) where
  value : C.Digest
  pin : SnapshotPin C
  deriving DecidableEq

/-- An `ekos/conflict/v1` document. There is no `chosen` field: no claim is
preferred. -/
structure ConflictDoc (C : Carriers) where
  header : ConflictHeader C
  members : List (ConflictMember C)
  /-- The `Disputes` link, to the subject. -/
  disputes : C.ClaimId
  deriving DecidableEq

/-- What a conflict is. -/
structure Conflict (C : Carriers) where
  subject : C.ClaimId
  attribute : C.Digest
  conflictType : C.Digest
  members : List (ConflictMember C)
  deriving DecidableEq

section conflict
variable (sigOf : C.Digest → List (C.Digest × C.SourceId) → C.Digest)

/-- The signature: of the attribute and each member's (value, source). Like
EKOS's `signature` (`conflicts.rs:162-171`), lines are left out. -/
def Conflict.signature (k : Conflict C) : C.Digest :=
  sigOf k.attribute (k.members.map fun m => (m.value, m.pin.source))

def encodeConflict (k : Conflict C) : ConflictDoc C :=
  ⟨⟨k.subject, k.attribute, k.conflictType, k.signature sigOf⟩, k.members, k.subject⟩

def decodeConflict (D : ConflictDoc C) : Conflict C :=
  ⟨D.header.subject, D.header.attribute, D.header.conflictType, D.members⟩

/-- The derived fields agree: the signature is the members' signature and
`Disputes` points at the subject. -/
def ConflictDoc.Consistent (D : ConflictDoc C) : Prop :=
  D.header.signature = (decodeConflict D).signature sigOf ∧ D.disputes = D.header.subject

theorem decode_encodeConflict (k : Conflict C) : decodeConflict (encodeConflict sigOf k) = k := rfl

theorem encodeConflict_consistent (k : Conflict C) : (encodeConflict sigOf k).Consistent sigOf :=
  ⟨rfl, rfl⟩

/-- **A consistent conflict document is exactly the encoding of what it
means.** -/
theorem encode_decodeConflict (D : ConflictDoc C) (h : D.Consistent sigOf) :
    encodeConflict sigOf (decodeConflict D) = D := by
  obtain ⟨⟨s, a, t, sig⟩, ms, dsp⟩ := D
  obtain ⟨h1, h2⟩ := h
  simp only at h1 h2
  simp only [encodeConflict, decodeConflict, ConflictDoc.mk.injEq, ConflictHeader.mk.injEq,
    true_and, and_true]
  exact ⟨h1.symm, h2.symm⟩

/-- The atom pins of a conflict document: every member's statement pin. -/
def ConflictDoc.atomPins (D : ConflictDoc C) : List (C.SourceId × C.AtomRev) :=
  D.members.flatMap fun m => m.pin.atoms.map (m.pin.source, ·)

/-- **Every member keeps its pins: none is chosen or dropped.** -/
theorem atomPins_encodeConflict (k : Conflict C) (x : C.SourceId × C.AtomRev) :
    x ∈ (encodeConflict sigOf k).atomPins ↔ ∃ m ∈ k.members, x ∈ m.pin.atoms.map (m.pin.source, ·) := by
  simp [ConflictDoc.atomPins, encodeConflict, List.mem_flatMap]

end conflict

/-! ## `ekos/review/v1` -/

/-- A decision atom. -/
structure DecisionAtom (C : Carriers) where
  verb : Status
  reviewer : C.Name
  note : C.Digest
  deriving DecidableEq

/-- One appended decision container: the decision and a snapshot pin of the
reviewed header atom. -/
structure DecisionContainer (C : Carriers) where
  decision : DecisionAtom C
  pin : SnapshotPin C
  deriving DecidableEq

/-- An `ekos/review/v1` document. -/
structure ReviewDoc (C : Carriers) where
  reviewed : C.ClaimId
  decisions : List (DecisionContainer C)
  deriving DecidableEq

/-- What one decision means: the decision, the header document, and the one
header atom revision read. -/
structure ReviewEntry (C : Carriers) where
  decision : DecisionAtom C
  headerDoc : C.SourceId
  headerRead : C.AtomRev
  deriving DecidableEq

def ReviewEntry.toContainer (e : ReviewEntry C) : DecisionContainer C :=
  ⟨e.decision, ⟨e.headerDoc, [e.headerRead]⟩⟩

def DecisionContainer.toEntry (dc : DecisionContainer C) : Option (ReviewEntry C) :=
  match dc.pin.atoms with
  | [a] => some ⟨dc.decision, dc.pin.source, a⟩
  | _ => none

def encodeReview (reviewed : C.ClaimId) (es : List (ReviewEntry C)) : ReviewDoc C :=
  ⟨reviewed, es.map ReviewEntry.toContainer⟩

def decodeReview (D : ReviewDoc C) : Option (List (ReviewEntry C)) :=
  D.decisions.mapM DecisionContainer.toEntry

/-- Append one decision; nothing before it changes. -/
def ReviewDoc.append (D : ReviewDoc C) (e : ReviewEntry C) : ReviewDoc C :=
  { D with decisions := D.decisions ++ [e.toContainer] }

theorem toEntry_toContainer (e : ReviewEntry C) : e.toContainer.toEntry = some e := rfl

theorem decode_encodeReview (reviewed : C.ClaimId) (es : List (ReviewEntry C)) :
    decodeReview (encodeReview reviewed es) = some es := by
  simp only [decodeReview, encodeReview]
  induction es with
  | nil => rfl
  | cons e es ih => simp [List.mapM_cons, toEntry_toContainer] at ih ⊢; exact ih

/-- **A review document whose every pin names one atom is exactly the
encoding of its entries.** -/
theorem encode_decodeReview (D : ReviewDoc C) (es : List (ReviewEntry C))
    (h : decodeReview D = some es) : encodeReview D.reviewed es = D := by
  obtain ⟨rv, dcs⟩ := D
  simp only [encodeReview, ReviewDoc.mk.injEq, true_and]
  simp only [decodeReview] at h
  induction dcs generalizing es with
  | nil => simp at h; subst h; rfl
  | cons dc dcs ih =>
    rw [List.mapM_cons] at h
    cases hdc : dc.toEntry with
    | none => simp [hdc] at h
    | some e =>
      cases hr : dcs.mapM DecisionContainer.toEntry with
      | none => simp [hdc, hr] at h
      | some es' =>
        simp only [hdc, hr, Option.bind_eq_bind, Option.bind_some, Option.pure_def,
          Option.some.injEq] at h
        subst h
        have hdc' : e.toContainer = dc := by
          obtain ⟨d, ⟨src, atoms⟩⟩ := dc
          simp only [DecisionContainer.toEntry] at hdc
          split at hdc
          · rename_i a hat
            simp only [Option.some.injEq] at hdc
            subst hdc
            simp only at hat
            subst hat
            rfl
          · cases hdc
        simp [hdc', ih es' hr]

/-- **Appending is append-only.** -/
theorem append_prefix (D : ReviewDoc C) (e : ReviewEntry C) :
    D.decisions <+: (D.append e).decisions := List.prefix_append _ _

/-- The atom pins of a review document. -/
def ReviewDoc.atomPins (D : ReviewDoc C) : List (C.SourceId × C.AtomRev) :=
  D.decisions.flatMap fun dc => dc.pin.atoms.map (dc.pin.source, ·)

/-- **Each entry pins exactly its one header atom revision.** -/
theorem atomPins_encodeReview (reviewed : C.ClaimId) (es : List (ReviewEntry C))
    (x : C.SourceId × C.AtomRev) :
    x ∈ (encodeReview reviewed es).atomPins ↔ ∃ e ∈ es, x = (e.headerDoc, e.headerRead) := by
  simp [ReviewDoc.atomPins, encodeReview, ReviewEntry.toContainer, List.mem_flatMap, eq_comm]

/-! ## `ekos/compile-run/v1` and `ekos/replay-attestation/v1` -/

/-- An input pin: a snapshot of a source header, and the height it was read at. -/
structure InputPin (C : Carriers) where
  pin : SnapshotPin C
  height : Nat
  deriving DecidableEq

/-- The compiler's identity. -/
structure CompilerIdentity (C : Carriers) where
  commit : C.Digest
  logicVersion : C.Digest
  predicatesVersion : C.Digest
  redactionTable : C.Digest
  deriving DecidableEq

/-- An `ekos/compile-run/v1` document. -/
structure CompileRunDoc (C : Carriers) where
  compiler : C.Name
  inputs : List (InputPin C)
  identity : CompilerIdentity C
  /-- Each output cell and its post root. -/
  outputs : List (C.ClaimId × C.Digest)
  /-- Digest of the exact command bytes submitted. -/
  command : C.Digest
  deriving DecidableEq

/-- An `ekos/replay-attestation/v1` document: a verifier re-ran a recorded
compile and records what it got. -/
structure ReplayAttestation (C : Carriers) where
  verifier : C.Name
  outputs : List (C.ClaimId × C.Digest)
  command : C.Digest
  deriving DecidableEq

/-- The atom pins of a compile-run document. -/
def CompileRunDoc.atomPins (D : CompileRunDoc C) : List (C.SourceId × C.AtomRev × Nat) :=
  D.inputs.flatMap fun i => i.pin.atoms.map fun a => (i.pin.source, a, i.height)

/-- The label `replayedDeterministic`: some attestation by a principal other
than the compiler got the same outputs from the same command. -/
def replayedDeterministic (run : CompileRunDoc C) (atts : List (ReplayAttestation C)) : Prop :=
  ∃ a ∈ atts, a.verifier ≠ run.compiler ∧ a.outputs = run.outputs ∧ a.command = run.command

instance (run : CompileRunDoc C) (atts : List (ReplayAttestation C)) :
    Decidable (replayedDeterministic run atts) := by
  unfold replayedDeterministic; infer_instance

/-- **The compiler cannot attest its own determinism.** -/
theorem not_replayed_by_compiler (run : CompileRunDoc C) (atts : List (ReplayAttestation C))
    (h : ∀ a ∈ atts, a.verifier = run.compiler) : ¬ replayedDeterministic run atts := by
  rintro ⟨a, ha, hv, -⟩; exact hv (h a ha)

/-- **A replay that differs never earns the label** (it is a counterexample to
determinism, design P4). -/
theorem not_replayed_if_outputs_differ (run : CompileRunDoc C) (atts : List (ReplayAttestation C))
    (h : ∀ a ∈ atts, a.outputs ≠ run.outputs) : ¬ replayedDeterministic run atts := by
  rintro ⟨a, ha, -, ho, -⟩; exact h a ha ho

/-- **Each input pin keeps its atoms and its read height.** -/
theorem mem_atomPins_compileRun (D : CompileRunDoc C) (x : C.SourceId × C.AtomRev × Nat) :
    x ∈ D.atomPins ↔ ∃ i ∈ D.inputs, ∃ a ∈ i.pin.atoms, x = (i.pin.source, a, i.height) := by
  simp [CompileRunDoc.atomPins, List.mem_flatMap, eq_comm]

end World
