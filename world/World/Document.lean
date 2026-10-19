/-
# World.Document — the `ekos/object/v1` document shape

Exploration 01 §2.1 describes how one compiled object is laid out as a
minidregg document (one cell). This file states that shape as Lean
structures over the abstract carriers, gives the encoding of a claim into it
and back, and proves the two directions preserve the claim's pins.

The shape, in plain words:
- a **header atom**: the claim key (schema, subject, sources);
- a **properties atom**: the payload;
- the validity **window**;
- one **evidence container** per source pin. It holds a **meta atom**
  (weight per mille, and the range) and a **snapshot-transclusion pin**: the
  source document and the atoms read, each with its revision;
- one **premise link** per claim pin: the premise id and the core digest
  read. Exploration 01 had objects pinned only to sources. Reviews, conflicts
  and edges pin claims, so their cells need this. It is our addition;
- for an object document, one **edge container** per outgoing edge. It holds
  the edge's own cell (edge atom = its header, properties and window; its
  evidence containers; its premise links) and the **link**: the id the edge
  points to.

A pin of the wrong shape (a source target read as a core digest, or a claim
target read as atoms) has no place in the document, so `encode` refuses it
(`none`).

What a reader sees of an evidence container (`viewEvidence`), and why the
kernel refuses a transclusion (`admitEvidence`), use the names the live
K12T run reports (`var/w7/run-1/steps/K12T/transclusion-rows.tsv`):
- `sourceNotCovered`: the writer sent the transclusion without a read of the
  source;
- `staleOpening`: the pin names a revision the writer never held;
- the **no-grant placeholder**: "[transclusion: n atoms of <doc>, not readable
  by you]";
- **`moved`**: the atoms are no longer at the revisions pinned.

These two names are quoted from minidregg's
`Minidregg.Kernel.ContentResource.Reject` (`sourceNotCovered`, `staleOpening`).
This file does not import `Kernel`; the constructors here are ours and only
carry the same names.

The last section ties visibility to exploration 01 §2.5's per-cell audience
rule. If a compiled claim's pins all name sources in one room, `visibleR`
under the reader's scope is true exactly when the reader holds that room's
grant.

Every other name here is new to VerEKOS.
-/
import World.Ranked
import World.Traverse

namespace World

set_option autoImplicit false

variable {C : Carriers} {P : C.SchemaId → Type}

/-! ## The shape -/

/-- The meta atom of an evidence container (`ekos/evidence-meta/v1`). -/
structure EvidenceMeta (C : Carriers) where
  /-- Confidence per mille (`confidence_milli`). -/
  weight : Nat
  /-- The range of the source the pin covers (`none` = the whole document). -/
  range : Option C.Range
  deriving DecidableEq

/-- A snapshot-transclusion pin: the source document and the atoms read, each
with its revision. -/
structure SnapshotPin (C : Carriers) where
  source : C.SourceId
  atoms : List C.AtomRev
  deriving DecidableEq

/-- One evidence container. -/
structure Evidence (C : Carriers) where
  info : EvidenceMeta C
  pin : SnapshotPin C
  deriving DecidableEq

/-- A premise link: the claim pinned, and the core digest read. -/
structure PremiseLink (C : Carriers) where
  target : C.ClaimId
  core : C.Digest
  weight : Nat
  deriving DecidableEq

/-- The cell encoding of one claim. -/
structure Cell (C : Carriers) (P : C.SchemaId → Type) where
  header : ClaimKey C
  properties : P header.schema
  window : Window C
  evidence : List (Evidence C)
  premises : List (PremiseLink C)

/-- One edge container: the edge's cell, and the link to where it points. -/
structure EdgeContainer (C : Carriers) (P : C.SchemaId → Type) where
  edge : Cell C P
  link : C.ClaimId

/-- An `ekos/object/v1` document: the object's cell and its outgoing edges. -/
structure ObjectDocument (C : Carriers) (P : C.SchemaId → Type) where
  object : Cell C P
  edges : List (EdgeContainer C P)

/-! ## Claim ↔ cell -/

/-- A pin has the right shape: a source target read as atoms, or a claim
target read as a core digest. -/
def Pin.wellTyped (p : Pin C) : Bool :=
  match p.target, p.revision with
  | .source _ _, .atoms _ => true
  | .claim _, .core _ => true
  | _, _ => false

/-- A source pin as an evidence container. -/
def Pin.toEvidence (p : Pin C) : Option (Evidence C) :=
  match p.target, p.revision with
  | .source doc r, .atoms read => some ⟨⟨p.weight, r⟩, ⟨doc, read⟩⟩
  | _, _ => none

/-- A claim pin as a premise link. -/
def Pin.toPremise (p : Pin C) : Option (PremiseLink C) :=
  match p.target, p.revision with
  | .claim i, .core dg => some ⟨i, dg, p.weight⟩
  | _, _ => none

/-- An evidence container back as a pin. -/
def Evidence.toPin (e : Evidence C) : Pin C :=
  ⟨.source e.pin.source e.info.range, .atoms e.pin.atoms, e.info.weight⟩

/-- A premise link back as a pin. -/
def PremiseLink.toPin (l : PremiseLink C) : Pin C := ⟨.claim l.target, .core l.core, l.weight⟩

/-- Encode a claim as a cell; `none` if any pin has the wrong shape. -/
def encode (c : Claim C P) : Option (Cell C P) :=
  if c.pins.all Pin.wellTyped then
    some ⟨c.key, c.payload, c.valid, c.pins.filterMap Pin.toEvidence,
      c.pins.filterMap Pin.toPremise⟩
  else none

/-- Decode a cell as a claim: evidence pins first, then premise pins. -/
def decode (cell : Cell C P) : Claim C P :=
  ⟨cell.header, cell.properties, cell.evidence.map Evidence.toPin ++
    cell.premises.map PremiseLink.toPin, cell.window⟩

/-- Is this a source pin? -/
def Pin.isSource (p : Pin C) : Bool :=
  match p.target with
  | .source _ _ => true
  | .claim _ => false

theorem toEvidence_map (p : Pin C) (h : p.wellTyped = true) :
    (p.toEvidence).map Evidence.toPin = if p.isSource then some p else none := by
  obtain ⟨t, r, w⟩ := p
  cases t <;> cases r <;> simp_all [Pin.wellTyped, Pin.toEvidence, Pin.isSource, Evidence.toPin]

theorem toPremise_map (p : Pin C) (h : p.wellTyped = true) :
    (p.toPremise).map PremiseLink.toPin = if p.isSource then none else some p := by
  obtain ⟨t, r, w⟩ := p
  cases t <;> cases r <;> simp_all [Pin.wellTyped, Pin.toPremise, Pin.isSource, PremiseLink.toPin]

theorem filterMap_map_eq_filter {α β : Type} (f : α → Option β) (g : β → α) (q : α → Bool)
    (l : List α) (h : ∀ a ∈ l, (f a).map g = if q a then some a else none) :
    (l.filterMap f).map g = l.filter q := by
  induction l with
  | nil => rfl
  | cons a l ih =>
    have ha := h a List.mem_cons_self
    have ih' := ih (fun b hb => h b (List.mem_cons_of_mem _ hb))
    cases hfa : f a with
    | none =>
      rw [hfa] at ha
      simp only [Option.map_none] at ha
      split at ha
      · cases ha
      · rename_i hq
        simp [hfa, hq, ih']
    | some b =>
      rw [hfa] at ha
      simp only [Option.map_some] at ha
      split at ha
      · rename_i hq
        injection ha with ha
        simp [hfa, hq, ih', ha]
      · cases ha

/-- **Decoding an encoded claim gives back the same claim up to the order of
its pins**: same key, payload and window; its pins are a permutation of the
original (source pins first). -/
theorem decode_encode (c : Claim C P) (cell : Cell C P) (h : encode c = some cell) :
    ∃ ps, decode cell = { c with pins := ps } ∧ ps.Perm c.pins := by
  unfold encode at h
  split at h
  · rename_i hwt
    injection h with h
    subst h
    rw [List.all_eq_true] at hwt
    refine ⟨_, rfl, ?_⟩
    rw [filterMap_map_eq_filter _ _ Pin.isSource c.pins (fun p hp => toEvidence_map p (hwt p hp)),
      filterMap_map_eq_filter _ _ (fun p => !p.isSource) c.pins
        (fun p hp => by rw [toPremise_map p (hwt p hp)]; cases hs : p.isSource <;> simp [hs])]
    exact List.filter_append_perm _ _
  · cases h

/-- **Encoding a decoded cell gives back exactly the same cell.** -/
theorem encode_decode (cell : Cell C P) : encode (decode cell) = some cell := by
  obtain ⟨k, x, w, ev, pr⟩ := cell
  unfold encode decode
  have hwt : (ev.map Evidence.toPin ++ pr.map PremiseLink.toPin).all Pin.wellTyped = true := by
    simp [List.all_eq_true, Pin.wellTyped, Evidence.toPin, PremiseLink.toPin]
  rw [if_pos hwt]
  simp only [List.filterMap_append, List.filterMap_map]
  have h1 : ev.filterMap (Pin.toEvidence ∘ Evidence.toPin) = ev := by
    have : (Pin.toEvidence ∘ Evidence.toPin : Evidence C → Option (Evidence C)) = some := by
      funext e; simp [Pin.toEvidence, Evidence.toPin]
    rw [this, List.filterMap_some]
  have h2 : ev.filterMap (Pin.toPremise ∘ Evidence.toPin) = [] := by
    simp [Pin.toPremise, Evidence.toPin]
  have h3 : pr.filterMap (Pin.toEvidence ∘ PremiseLink.toPin) = [] := by
    simp [Pin.toEvidence, PremiseLink.toPin]
  have h4 : pr.filterMap (Pin.toPremise ∘ PremiseLink.toPin) = pr := by
    have : (Pin.toPremise ∘ PremiseLink.toPin : PremiseLink C → Option (PremiseLink C)) = some := by
      funext l; simp [Pin.toPremise, PremiseLink.toPin]
    rw [this, List.filterMap_some]
  rw [h1, h2, h3, h4]
  simp

/-! ## The (source document, atom revision) pins -/

/-- Every (source document, atom revision) a claim's pins read. -/
def claimAtomPins (c : Claim C P) : List (C.SourceId × C.AtomRev) :=
  c.pins.flatMap fun p =>
    match p.target, p.revision with
    | .source doc _, .atoms read => read.map (doc, ·)
    | _, _ => []

/-- Every (source document, atom revision) a cell's evidence containers pin. -/
def cellAtomPins (cell : Cell C P) : List (C.SourceId × C.AtomRev) :=
  cell.evidence.flatMap fun e => e.pin.atoms.map (e.pin.source, ·)

theorem claimAtomPins_perm (c c' : Claim C P) (h : c'.pins.Perm c.pins) (x : C.SourceId × C.AtomRev) :
    x ∈ claimAtomPins c' ↔ x ∈ claimAtomPins c := by
  unfold claimAtomPins
  simp only [List.mem_flatMap]
  exact ⟨fun ⟨p, hp, hx⟩ => ⟨p, h.subset hp, hx⟩, fun ⟨p, hp, hx⟩ => ⟨p, h.symm.subset hp, hx⟩⟩

/-- Decoding keeps exactly the cell's atom pins. -/
theorem claimAtomPins_decode (cell : Cell C P) (x : C.SourceId × C.AtomRev) :
    x ∈ claimAtomPins (decode cell) ↔ x ∈ cellAtomPins cell := by
  simp only [claimAtomPins, cellAtomPins, decode, List.mem_flatMap, List.mem_append, List.mem_map]
  constructor
  · rintro ⟨p, (⟨e, he, rfl⟩ | ⟨l, hl, rfl⟩), hx⟩
    · exact ⟨e, he, by simpa [Evidence.toPin] using hx⟩
    · simp [PremiseLink.toPin] at hx
  · rintro ⟨e, he, hx⟩
    exact ⟨e.toPin, Or.inl ⟨e, he, rfl⟩, by simpa [Evidence.toPin] using hx⟩

/-- **Encoding keeps exactly the claim's atom pins.** -/
theorem cellAtomPins_encode (c : Claim C P) (cell : Cell C P) (h : encode c = some cell)
    (x : C.SourceId × C.AtomRev) : x ∈ cellAtomPins cell ↔ x ∈ claimAtomPins c := by
  obtain ⟨ps, hd, hperm⟩ := decode_encode c cell h
  rw [← claimAtomPins_decode, hd]
  exact claimAtomPins_perm c { c with pins := ps } hperm x

/-! ## Object documents -/

section document
variable (d : ClaimIdDerivation C) (E : EdgeView C P)

/-- Encode the outgoing edges of the object with id `from`. Refuses an edge
that is ill-shaped or does not start at `from`. -/
def encodeEdges (from_ : C.ClaimId) : List (Claim C P) → Option (List (EdgeContainer C P))
  | [] => some []
  | e :: es =>
    match encode e, E.ends e, encodeEdges from_ es with
    | some cell, some (a, b), some rest => if a = from_ then some (⟨cell, b⟩ :: rest) else none
    | _, _, _ => none

/-- Lay out a claim and its outgoing edge claims as an object document. -/
def toDocument (c : Claim C P) (outgoing : List (Claim C P)) : Option (ObjectDocument C P) :=
  match encode c, encodeEdges E (c.id d) outgoing with
  | some cell, some edges => some ⟨cell, edges⟩
  | _, _ => none

/-- Read an object document back as the object and its edge claims. -/
def fromDocument (D : ObjectDocument C P) : Claim C P × List (Claim C P) :=
  (decode D.object, D.edges.map fun ec => decode ec.edge)

/-- Every (source document, atom revision) a document pins. -/
def docAtomPins (D : ObjectDocument C P) : List (C.SourceId × C.AtomRev) :=
  cellAtomPins D.object ++ D.edges.flatMap fun ec => cellAtomPins ec.edge

theorem encodeEdges_atomPins (from_ : C.ClaimId) :
    ∀ (es : List (Claim C P)) (ecs : List (EdgeContainer C P)),
      encodeEdges E from_ es = some ecs → ∀ x,
        x ∈ ecs.flatMap (fun ec => cellAtomPins ec.edge) ↔ ∃ e ∈ es, x ∈ claimAtomPins e
  | [], ecs, h, x => by
    simp only [encodeEdges, Option.some.injEq] at h
    subst h; simp
  | e :: es, ecs, h, x => by
    unfold encodeEdges at h
    split at h
    · rename_i cell a b rest hc he hr
      split at h
      · injection h with h
        subst h
        rw [List.flatMap_cons, List.mem_append, cellAtomPins_encode e cell hc,
          encodeEdges_atomPins from_ es rest hr x]
        simp
      · cases h
    · cases h

/-- **Laying out a claim as a document keeps exactly its atom pins and those
of its outgoing edges.** -/
theorem toDocument_atomPins (c : Claim C P) (outgoing : List (Claim C P))
    (D : ObjectDocument C P) (h : toDocument d E c outgoing = some D)
    (x : C.SourceId × C.AtomRev) :
    x ∈ docAtomPins D ↔ x ∈ claimAtomPins c ∨ ∃ e ∈ outgoing, x ∈ claimAtomPins e := by
  unfold toDocument at h
  split at h
  · rename_i cell edges hc he
    injection h with h
    subst h
    rw [docAtomPins, List.mem_append, cellAtomPins_encode c cell hc,
      encodeEdges_atomPins E (c.id d) outgoing edges he x]
  · cases h

/-- **Reading a document back keeps exactly its atom pins.** -/
theorem fromDocument_atomPins (D : ObjectDocument C P) (x : C.SourceId × C.AtomRev) :
    x ∈ docAtomPins D ↔
      x ∈ claimAtomPins (fromDocument D).1 ∨ ∃ e ∈ (fromDocument D).2, x ∈ claimAtomPins e := by
  simp only [docAtomPins, fromDocument, List.mem_append, List.mem_flatMap, List.mem_map,
    claimAtomPins_decode]
  constructor
  · rintro (h | ⟨ec, hec, hx⟩)
    · exact Or.inl h
    · exact Or.inr ⟨_, ⟨ec, hec, rfl⟩, (claimAtomPins_decode _ x).mpr hx⟩
  · rintro (h | ⟨_, ⟨ec, hec, rfl⟩, hx⟩)
    · exact Or.inl h
    · exact Or.inr ⟨ec, hec, (claimAtomPins_decode _ x).mp hx⟩

end document

/-! ## Admission refusals and what a reader sees -/

/-- Why the kernel refuses a transclusion (names as in minidregg's
`Minidregg.Kernel.ContentResource.Reject`). -/
inductive TranscludeRefusal where
  /-- Sent without the writer's read of the source. -/
  | sourceNotCovered
  /-- The pin names a revision the writer never held. -/
  | staleOpening
  deriving DecidableEq, Repr

/-- Admission of one evidence container: the writer must read the source, and
must have held every revision pinned. -/
def admitEvidence (writerReads : C.SourceId → Bool) (held : C.SourceId → C.AtomRev → Bool)
    (e : Evidence C) : Option TranscludeRefusal :=
  if !writerReads e.pin.source then some .sourceNotCovered
  else if !(e.pin.atoms.all (held e.pin.source)) then some .staleOpening
  else none

/-- What one reader sees of one evidence container. -/
inductive PinView where
  /-- The pinned bytes, unchanged. -/
  | sameBytes
  /-- The atoms are no longer at the revisions pinned. -/
  | moved
  /-- No grant on the source: the placeholder
  "[transclusion: n atoms of <doc>, not readable by you]". -/
  | noGrant (atoms : Nat)
  deriving DecidableEq, Repr

/-- The view: no grant gives the placeholder; otherwise the same bytes when
every atom is still at its pinned revision, else `moved`. -/
def viewEvidence (readable : C.SourceId → Bool) (current : C.SourceId → C.AtomRev → Bool)
    (e : Evidence C) : PinView :=
  if !readable e.pin.source then .noGrant e.pin.atoms.length
  else if e.pin.atoms.all (current e.pin.source) then .sameBytes else .moved

/-- **A reader without a grant gets only the placeholder, never bytes.** -/
theorem viewEvidence_noGrant (readable : C.SourceId → Bool)
    (current : C.SourceId → C.AtomRev → Bool) (e : Evidence C) :
    readable e.pin.source = false ↔ viewEvidence readable current e = .noGrant e.pin.atoms.length := by
  unfold viewEvidence
  constructor
  · intro h; simp [h]
  · intro h
    cases hr : readable e.pin.source
    · rfl
    · simp only [hr, Bool.not_true, Bool.false_eq_true, if_false] at h
      split at h <;> cases h

/-- **Same bytes or `moved`, never other bytes.** A reader with a grant sees
`sameBytes` exactly when every pinned atom is still at its pinned revision. -/
theorem viewEvidence_sameBytes (readable : C.SourceId → Bool)
    (current : C.SourceId → C.AtomRev → Bool) (e : Evidence C)
    (hr : readable e.pin.source = true) :
    viewEvidence readable current e = .sameBytes ↔ ∀ a ∈ e.pin.atoms, current e.pin.source a = true := by
  unfold viewEvidence
  simp only [hr, Bool.not_true, Bool.false_eq_true, if_false]
  split
  · rename_i h; simp only [List.all_eq_true] at h; exact iff_of_true rfl h
  · rename_i h
    simp only [List.all_eq_true] at h
    simp only [reduceCtorEq, false_iff]
    exact h

/-- **An admitted container was read by its writer at revisions it held.** -/
theorem admitEvidence_none (writerReads : C.SourceId → Bool)
    (held : C.SourceId → C.AtomRev → Bool) (e : Evidence C) :
    admitEvidence writerReads held e = none ↔
      writerReads e.pin.source = true ∧ ∀ a ∈ e.pin.atoms, held e.pin.source a = true := by
  unfold admitEvidence
  cases hw : writerReads e.pin.source <;> simp

/-! ## Visibility agrees with the per-room audience rule (exploration 01 §2.5) -/

section audience
variable (d : ClaimIdDerivation C) (σ : C.ClaimId → Option (Claim C P))

/-- The scope of a reader who can read exactly the source documents
`readable`: it allows those origins, denies nothing, and allows no id
outright. -/
def readerScope (readable : C.SourceId → Bool) : Scope C :=
  ⟨fun _ => false, fun _ => false, fun doc _ => readable doc, fun _ _ => false⟩

/-- **Visibility is "may read every transcluded source".** For a claim whose
pins are all source pins, and which has at least one, `visibleR` under the
reader's scope is true exactly when the reader may read the source of every
evidence container of its cell.

The two hypotheses are needed. Without "at least one pin", an unpinned claim
is hidden while "every source is readable" holds vacuously. With a claim pin,
visibility also depends on the premise's visibility, which the cell's
evidence alone does not show. -/
theorem visibleR_iff_readable (rank : Claim C P → Nat) (readable : C.SourceId → Bool)
    (c : Claim C P) (cell : Cell C P) (hc : encode c = some cell)
    (hne : c.PinsNonempty) (hsrc : ∀ p ∈ c.pins, ∃ doc r, p.target = .source doc r) :
    visibleR d σ (readerScope readable) rank c = true ↔
      ∀ e ∈ cell.evidence, readable e.pin.source = true := by
  unfold visibleR
  rw [visible_iff_sourcePins d σ (readerScope readable) (rank c) c hne hsrc rfl rfl]
  unfold encode at hc
  split at hc
  · rename_i hwt
    injection hc with hc
    subst hc
    rw [List.all_eq_true] at hwt
    simp only [readerScope, and_true]
    constructor
    · intro h e he
      rw [List.mem_filterMap] at he
      obtain ⟨p, hp, hpe⟩ := he
      obtain ⟨t, rv, w⟩ := p
      cases t with
      | claim i => simp [Pin.toEvidence] at hpe
      | source doc r =>
        cases rv with
        | core _ => simp [Pin.toEvidence] at hpe
        | atoms read =>
          simp only [Pin.toEvidence, Option.some.injEq] at hpe
          subst hpe
          exact h _ hp doc r rfl
    · intro h p hp doc r ht
      obtain ⟨t, rv, w⟩ := p
      simp only at ht
      subst ht
      cases rv with
      | core _ => simp [Pin.wellTyped] at hwt; exact absurd (hwt _ hp) (by simp)
      | atoms read =>
        exact h ⟨⟨w, r⟩, ⟨doc, read⟩⟩ (List.mem_filterMap.mpr ⟨_, hp, rfl⟩)
  · cases hc

/-- **The per-room audience rule.** Put each source in a room (`roomOf`), and
let a reader read exactly the sources of the rooms it holds a grant for. A
compiled claim whose pins (at least one) all name sources in room `ρ` is
visible to the reader exactly when the reader holds `ρ`'s grant. -/
theorem visibleR_iff_room {Room : Type} (rank : Claim C P → Nat) (roomOf : C.SourceId → Room)
    (grants : Room → Bool) (ρ : Room) (c : Claim C P) (cell : Cell C P)
    (hc : encode c = some cell) (hne : c.PinsNonempty)
    (hroom : ∀ p ∈ c.pins, ∃ doc r, p.target = .source doc r ∧ roomOf doc = ρ) :
    visibleR d σ (readerScope fun doc => grants (roomOf doc)) rank c = true ↔
      grants ρ = true := by
  have hsrc : ∀ p ∈ c.pins, ∃ doc r, p.target = .source doc r := fun p hp => by
    obtain ⟨doc, r, ht, -⟩ := hroom p hp; exact ⟨doc, r, ht⟩
  rw [visibleR_iff_readable d σ rank _ c cell hc hne hsrc]
  unfold encode at hc
  split at hc
  · injection hc with hc
    subst hc
    constructor
    · intro h
      obtain ⟨p, hp⟩ := List.exists_mem_of_ne_nil c.pins hne
      obtain ⟨doc, r, ht, hroomp⟩ := hroom p hp
      obtain ⟨t, rv, w⟩ := p
      simp only at ht
      subst ht
      rename_i hwt
      rw [List.all_eq_true] at hwt
      cases rv with
      | core _ => exact absurd (hwt _ hp) (by simp [Pin.wellTyped])
      | atoms read =>
        have := h ⟨⟨w, r⟩, ⟨doc, read⟩⟩ (List.mem_filterMap.mpr ⟨_, hp, rfl⟩)
        rw [← hroomp]; exact this
    · intro hg e he
      rw [List.mem_filterMap] at he
      obtain ⟨p, hp, hpe⟩ := he
      obtain ⟨doc, r, ht, hroomp⟩ := hroom p hp
      obtain ⟨t, rv, w⟩ := p
      simp only at ht
      subst ht
      cases rv with
      | core _ => simp [Pin.toEvidence] at hpe
      | atoms read =>
        simp only [Pin.toEvidence, Option.some.injEq] at hpe
        subst hpe
        simp only
        rw [hroomp]; exact hg
  · cases hc

end audience

end World
