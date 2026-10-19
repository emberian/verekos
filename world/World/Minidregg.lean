/-
# World.Minidregg — the model over minidregg's own records

This file gives the `Carriers` instance over minidregg's types, and proves
that the model's notions **are** minidregg's, not stand-ins for them. Each
theorem cites the minidregg definition or theorem it rests on, at the pinned
commit `dcab86da` (`lakefile.toml`). It imports `Kernel.ContentResource`, so it
lives in `World`, never in `WorldCore`.

The instance (`carriers`, scoped to `World.Minidregg`):

| Carrier | minidregg type |
|---|---|
| `SchemaId`, `Digest`, `Stage` | `Digest` (`Theory/TypedAuthorization.lean:53`) |
| `SourceId`, `RunId` | `DocumentId` (`Theory/Hyperdocument.lean:177`) |
| `Range` | `StableRange` (`Theory/Hyperdocument.lean:409`) |
| `AtomRev` | `AtomId × OperationId`, the shape of `TranscludeRequest.pins` (`Kernel/ContentResource.lean:96`) |
| `Name` | `PrincipalRef` (`Theory/Hyperdocument.lean:197`) |
| `ClaimId` | `ElementId` (`Theory/Hyperdocument.lean:180`), through `deriveIdentifier` |
| `KeyPart` | `List UInt8` (bytes) |
| `Time` | `Nat`: EKOS's domain validity time; minidregg has no domain clock |

The theorems, and where the model and minidregg part ways:

**(a) Staleness is minidregg's.** `Pin.staleIn store p` is "some atom the pin
read fails `pinHolds`", minidregg's own test
(`Kernel/ContentResource.lean:2177`). `staleIn_iff_moved`: stale iff
`renderSnapshot` (`:2188`) says `moved`. `same_bytes_of_not_stale`: under
`transclusion_pinned`'s hypotheses (`:2570`), a pin that is not stale renders
exactly the bytes pinned at the opening.

**Where they part ways (a).** `pinHolds` requires the atom to be in the pinned
document, at the pinned revision, **and not tombstoned**. The stand-in this
file replaced (`sourcePinFresh`) compared revisions only, so it called a
deleted atom fresh. `tombstoned_is_stale` shows minidregg calls it stale.

**(b) Receipts never alias as version events.** `Receipt.toEvent` maps a
receipt to a `VersionEventRecord` (`Theory/Hyperdocument.lean:628`). The
composite with `VersionEventRecord.toCausalPreimage` (`:649`) is injective
(`toEvent_causal_injective`), resting on minidregg's
`toCausalPreimage_injective` (`:699`) and on an injective encoding of
operations (a premise, `OpEncoding`). The principal **kind** (compiler,
agent, human) has no minidregg field; it is carried in `historyDomain`.
That is our choice.

**(c) Visibility agrees with the reader-render rule.** A reader renders a
transclusion through its **own** read of the source, `Option ContentStore`
(`renderTransclusion`, `Kernel/ContentResource.lean:2206`; the rule is stated
at `:52-56`). `viewEvidence_eq_render`: the model's `viewEvidence` is
minidregg's render, read through `toPinView`. `visibleR_iff_rendered`: a
compiled claim pinned only to sources is visible under the reader's scope
exactly when no transclusion of its cell renders `unavailable` for that
reader.

**Where they part ways (c).**
- `Context.sourceRead` (`:126`) is the *writer's* admission (a transclusion
  sent without it is refused `sourceNotCovered`, `transclude_uncovered_refused`,
  `:2243`). The reader's rule uses the reader's own read. The brief's phrase
  "over the real `sourceRead` context" mixes the two. `admit_sourceNotCovered`
  ties the model's writer-side refusal to `Context.sourceRead`, and
  `viewEvidence_eq_render` ties the reader side to the reader's read.
- The model's `PinView` has no counterpart for **live** transclusions
  (`renderLive`: `live`, `invalidated`, `unresolved`) and drops `moved`'s
  height. `toPinView` is therefore partial.

**(d) The cell's atom pins are the transclusion requests' pins.**
`Evidence.toRequest` turns an evidence container into a `TranscludeRequest`
(`Kernel/ContentResource.lean:92`). `cellAtomPins_eq_requests`: a cell's
(document, atom, revision) pins are exactly the requests' `pins`.

**Where they part ways (d).** A minidregg transclusion always names a
`StableRange`. The model allows a source pin with **no range** (the whole
document), and such a pin has no request (`toRequest_none_iff`).

Every name defined here is new to VerEKOS; every minidregg name is quoted.
-/
import Kernel.ContentResource
import World.Document
import World.Ranked

namespace World.Minidregg

set_option autoImplicit false

open Minidregg.Theory.Hyperdocument (DocumentId AtomId OperationId ElementId StableRange
  AtomRecord PrincipalRef DigestDerivation deriveIdentifier IdPreimage
  preimageCodec_encode_injective VersionEventRecord TransclusionMode)
open Minidregg.Theory.TypedAuthorization (Digest)
open Minidregg.Kernel.ContentResource (ContentStore TranscludeRequest RangeOpening
  renderSnapshot renderTransclusion pinHolds pinnedBytes TransclusionView documentOf
  transclusion_pinned Reaches openingHolds semanticAtom Context Progress Action step Reject
  transclude_uncovered_refused)

/-- The VerEKOS carriers over minidregg's types. -/
scoped instance carriers : Carriers where
  SchemaId := Digest
  SourceId := DocumentId
  Range := StableRange
  Digest := Digest
  Time := Nat
  RunId := DocumentId
  Stage := Digest
  KeyPart := List UInt8
  AtomRev := AtomId × OperationId
  Name := PrincipalRef
  ClaimId := ElementId
  decSchemaId := inferInstanceAs (DecidableEq Digest)
  decSourceId := inferInstanceAs (DecidableEq DocumentId)
  decRange := inferInstanceAs (DecidableEq StableRange)
  decDigest := inferInstanceAs (DecidableEq Digest)
  decTime := inferInstanceAs (DecidableEq Nat)
  decKeyPart := inferInstanceAs (DecidableEq (List UInt8))
  decAtomRev := inferInstanceAs (DecidableEq (AtomId × OperationId))
  decName := inferInstanceAs (DecidableEq PrincipalRef)
  decClaimId := inferInstanceAs (DecidableEq ElementId)

/-! ## Claim ids, through minidregg's identifier derivation -/

/-- How a deployment encodes a claim key as bytes (minidregg has no encoder
for our keys). -/
class KeyEncoding where
  encode : ClaimKey → List UInt8

/-- The deployment's digest operation: minidregg's `DigestDerivation`
(`Theory/Hyperdocument.lean:163`). -/
class DigestOp where
  derivation : DigestDerivation

/-- Claim ids derived the way minidregg derives every identifier: the v1
`element` preimage envelope, then the deployment's digest. -/
scoped instance claimIdDerivation [KeyEncoding] [DigestOp] : ClaimIdDerivation where
  claimId k := (deriveIdentifier DigestOp.derivation
    (⟨KeyEncoding.encode k⟩ : IdPreimage .v1 .element) : ElementId)

/-- **Claim ids are injective in keys** when the key encoder and the digest
are. The envelope step is minidregg's `preimageCodec_encode_injective`
(`Theory/Hyperdocument.lean:126`). The digest premise is an idealization;
minidregg attaches none to `DigestDerivation`. -/
theorem claimId_injective [KeyEncoding] [DigestOp]
    (hdd : Function.Injective (DigestOp.derivation).digestBytes)
    (henc : Function.Injective (KeyEncoding.encode)) :
    Function.Injective (ClaimIdDerivation.claimId : ClaimKey → ElementId) := by
  intro k₁ k₂ h
  have hdig := congrArg (fun x : ElementId => x.digest) h
  simp only [ClaimIdDerivation.claimId, deriveIdentifier] at hdig
  have hpre := preimageCodec_encode_injective .v1 .element (hdd hdig)
  exact henc (congrArg IdPreimage.payload hpre)

/-! ## (a) Staleness is minidregg's -/

/-- A cell number names its document (`documentOf`, `Kernel/ContentResource.lean:81`). -/
theorem documentOf_digest (doc : DocumentId) : documentOf doc.digest.value = doc := by
  obtain ⟨⟨n⟩⟩ := doc; rfl

/-- A source pin as minidregg's opening at `height`. Defined only for a pin
that names a range: a minidregg transclusion always does. -/
def _root_.World.Pin.toOpening (p : Pin) (height : Nat) : Option RangeOpening :=
  match p.target, p.revision with
  | .source doc (some range), .atoms read => some ⟨doc.digest.value, range, read, height⟩
  | _, _ => none

/-- A source pin is stale in `store` (a reader's view of the source) when some
atom it read fails minidregg's `pinHolds`. An ill-shaped pin is stale. -/
def _root_.World.Pin.staleIn (store : ContentStore) (p : Pin) : Bool :=
  match p.target, p.revision with
  | .source doc _, .atoms read => !(read.all (pinHolds store doc))
  | _, _ => true

/-- **(a) Stale is exactly `moved`.** For a pin with a range, `staleIn` holds
iff minidregg's `renderSnapshot` (`Kernel/ContentResource.lean:2188`) says
`moved`. -/
theorem staleIn_iff_moved (store : ContentStore) (p : Pin) (height : Nat) (o : RangeOpening)
    (ho : p.toOpening height = some o) :
    p.staleIn store = true ↔ renderSnapshot store o = .moved height := by
  obtain ⟨t, rv, w⟩ := p
  cases t with
  | claim _ => simp [Pin.toOpening] at ho
  | source doc r =>
    cases rv with
    | core _ => simp [Pin.toOpening] at ho
    | atoms read =>
      cases r with
      | none => simp [Pin.toOpening] at ho
      | some range =>
        simp only [Pin.toOpening, Option.some.injEq] at ho
        subst ho
        simp only [Pin.staleIn, renderSnapshot, documentOf_digest]
        split
        · rename_i h; simp [h]
        · rename_i h; simp [h]

/-- **(a) A pin that is not stale shows the bytes pinned at the opening**,
by minidregg's `transclusion_pinned` (`Kernel/ContentResource.lean:2570`):
there, after accepted runs not rewriting the pinned revisions, the snapshot
shows the opening's bytes or says `moved`; not stale rules out `moved`. -/
theorem same_bytes_of_not_stale (earlier later : ContentStore) (ops : List OperationId)
    (request : TranscludeRequest) (height : Nat)
    (admitted : openingHolds earlier request = true) (reached : Reaches earlier later ops)
    (fresh : ∀ pin ∈ request.pins, pin.2 ∉ ops)
    (p : Pin) (hp : p.toOpening height = some (.ofRequest request height))
    (hnot : p.staleIn later = false) :
    renderSnapshot later (.ofRequest request height) =
      .snapshot (request.pins.map (pinnedBytes earlier)) := by
  obtain ⟨-, hlater⟩ := transclusion_pinned earlier later ops request height admitted reached fresh
  rcases hlater with h | h
  · exact h
  · have := (staleIn_iff_moved later p height _ hp).mpr h
    rw [hnot] at this
    cases this

/-- **Where the stand-in was wrong: a tombstoned atom is stale**, even at the
pinned revision and document. -/
theorem tombstoned_is_stale (store : ContentStore) (doc : DocumentId) (r : Option StableRange)
    (a : AtomId × OperationId) (rec : AtomRecord) (w : Nat)
    (hrec : semanticAtom store a.1 = some rec) (htomb : rec.tombstonedAt.isSome = true) :
    Pin.staleIn store ⟨.source doc r, .atoms [a], w⟩ = true := by
  simp [World.Pin.staleIn, pinHolds, hrec]
  exact Or.inr htomb

/-! ## (b) Receipts never alias as version events -/

/-- How a deployment encodes an operation (a put or retract of a claim) as an
`OperationId`. Injectivity is a premise where needed. -/
class OpEncoding (P : Digest → Type) where
  encode : Op P → OperationId

/-- The principal kind, as a digest (distinct for each kind). -/
def kindDigest : PrincipalKind → Digest
  | .compiler => ⟨0⟩
  | .agent => ⟨1⟩
  | .human => ⟨2⟩

theorem kindDigest_injective : Function.Injective kindDigest := by
  intro a b h; cases a <;> cases b <;> first | rfl | (simp [kindDigest] at h)

/-- A receipt as a version event of the log document `doc`: the transaction
number is the semantic version, the operation is encoded, the run names the
request, the stage the effect, the principal kind the history domain. Roots
and parents are left for the host to fill; no theorem here reads them. -/
def _root_.World.Receipt.toEvent {P : Digest → Type} [OpEncoding P] (doc : DocumentId)
    (schema : Minidregg.Theory.CausalVersionDag.SchemaRef) (r : Receipt P) :
    VersionEventRecord where
  historyDomain := kindDigest r.author.1
  document := doc
  schema := schema
  semanticVersion := r.tx
  operation := OpEncoding.encode r.op
  parents := []
  preStateRoot := ⟨0⟩
  postStateRoot := ⟨0⟩
  requestId := r.run.digest
  effectId := r.stage
  author := r.author.2

/-- **(b) Distinct receipts never alias as causal events.** The last step is
minidregg's `VersionEventRecord.toCausalPreimage_injective`
(`Theory/Hyperdocument.lean:699`); the rest needs only an injective
operation encoding. -/
theorem toEvent_causal_injective {P : Digest → Type} [OpEncoding P] (doc : DocumentId)
    (schema : Minidregg.Theory.CausalVersionDag.SchemaRef)
    (henc : Function.Injective (OpEncoding.encode : Op P → OperationId)) :
    Function.Injective fun r : Receipt P => (r.toEvent doc schema).toCausalPreimage := by
  intro r₁ r₂ h
  have he := VersionEventRecord.toCausalPreimage_injective h
  obtain ⟨tx₁, op₁, ⟨k₁, n₁⟩, run₁, st₁⟩ := r₁
  obtain ⟨tx₂, op₂, ⟨k₂, n₂⟩, run₂, st₂⟩ := r₂
  simp only [Receipt.toEvent, VersionEventRecord.mk.injEq] at he
  obtain ⟨hk, -, -, htx, hop, -, -, -, hrun, hst, hn⟩ := he
  have hk' := kindDigest_injective hk
  have hop' := henc hop
  have hrun' : run₁ = run₂ := by
    obtain ⟨d₁⟩ := run₁; obtain ⟨d₂⟩ := run₂; simp only at hrun; rw [hrun]
  subst htx hop' hk' hrun' hst hn
  rfl

/-! ## (c) Visibility agrees with the reader-render rule -/

/-- The model's view, read off minidregg's (snapshot mode). Live-mode views
have no model counterpart. -/
def toPinView : TransclusionView → Option PinView
  | .unavailable n _ => some (.noGrant n)
  | .snapshot _ => some .sameBytes
  | .moved _ => some .moved
  | _ => none

/-- An evidence container as minidregg's opening at `height` (defined when it
names a range). -/
def _root_.World.Evidence.toOpening (e : Evidence) (height : Nat) : Option RangeOpening :=
  e.info.range.map fun range => ⟨e.pin.source.digest.value, range, e.pin.atoms, height⟩

/-- **(c) The model's view is minidregg's render.** For a reader whose own
read of each source is `readerSource` (`none` = no read, minidregg's
`renderTransclusion`, `Kernel/ContentResource.lean:2206`), `viewEvidence`
with "readable = has a read" and "current = `pinHolds` in that read" is
exactly the render, in snapshot mode. -/
theorem viewEvidence_eq_render (readerSource : DocumentId → Option ContentStore)
    (e : Evidence) (height : Nat) (o : RangeOpening) (ho : e.toOpening height = some o) :
    some (viewEvidence (fun doc => (readerSource doc).isSome)
        (fun doc a => match readerSource doc with
          | some store => pinHolds store doc a
          | none => false) e) =
      toPinView (renderTransclusion (readerSource e.pin.source) o .snapshot) := by
  obtain ⟨⟨w, r⟩, ⟨src, atoms⟩⟩ := e
  cases r with
  | none => simp [Evidence.toOpening] at ho
  | some range =>
    simp only [Evidence.toOpening, Option.map_some, Option.some.injEq] at ho
    subst ho
    simp only [viewEvidence, renderTransclusion]
    by_cases h : readerSource src = none
    · simp [h, toPinView]
    · obtain ⟨store, hst⟩ := Option.ne_none_iff_exists'.mp h
      simp only [hst, Option.isSome_some, Bool.not_true, Bool.false_eq_true, if_false,
        renderSnapshot, documentOf_digest]
      split <;> simp [toPinView]

/-- In snapshot mode, a transclusion renders `unavailable` iff the reader has
no read of the source. -/
theorem render_unavailable_iff (source : Option ContentStore) (o : RangeOpening) :
    (∃ n s, renderTransclusion source o .snapshot = .unavailable n s) ↔ source = none := by
  cases source with
  | none => simp [renderTransclusion]
  | some store =>
    simp only [renderTransclusion, renderSnapshot, reduceCtorEq, iff_false, not_exists]
    intro n s
    split <;> simp

/-- **(c) A compiled claim pinned only to sources is visible to a reader
exactly when none of its cell's transclusions renders `unavailable` for that
reader.** `σ` and `rank` are any state and rank (source pins never consult
them). -/
theorem visibleR_iff_rendered {P : Digest → Type} [ClaimIdDerivation]
    (σ : ElementId → Option (Claim P)) (rank : Claim P → Nat)
    (readerSource : DocumentId → Option ContentStore) (height : Nat)
    (c : Claim P) (cell : Cell P) (hc : encode c = some cell) (hne : c.PinsNonempty)
    (hsrc : ∀ p ∈ c.pins, ∃ doc r, p.target = .source doc r)
    (hrange : ∀ e ∈ cell.evidence, ∃ o, e.toOpening height = some o) :
    visibleR σ (readerScope fun doc => (readerSource doc).isSome) rank c = true ↔
      ∀ e ∈ cell.evidence, ∀ o, e.toOpening height = some o →
        ¬ ∃ n s, renderTransclusion (readerSource e.pin.source) o .snapshot = .unavailable n s := by
  rw [visibleR_iff_readable σ rank _ c cell hc hne hsrc]
  constructor
  · intro h e he o _ hu
    rw [render_unavailable_iff] at hu
    have := h e he
    rw [hu] at this
    cases this
  · intro h e he
    obtain ⟨o, ho⟩ := hrange e he
    have := h e he o ho
    rw [render_unavailable_iff] at this
    cases hs : readerSource e.pin.source with
    | none => exact absurd hs this
    | some _ => rfl

/-- The writer side: a transclusion of an evidence container whose source the
transaction carries no read of is refused `sourceNotCovered`, in the model
(`admitEvidence`) and in minidregg (`transclude_uncovered_refused`,
`Kernel/ContentResource.lean:2243`). -/
theorem admit_sourceNotCovered (context : Context) (held : DocumentId → AtomId × OperationId → Bool)
    (e : Evidence) (range : StableRange) (mode : TransclusionMode)
    (huncovered : context.sourceRead e.pin.source.digest.value = none)
    (author : PrincipalRef) (operation : OperationId) (document : DocumentId)
    (progress : Progress) (transclusion : Minidregg.Theory.Hyperdocument.TransclusionId)
    (link : Minidregg.Theory.Hyperdocument.LinkId) :
    admitEvidence (fun doc : DocumentId => (context.sourceRead doc.digest.value).isSome) held e =
        some .sourceNotCovered ∧
      step author operation document context progress
          (.transclude transclusion link ⟨e.pin.source.digest.value, range, mode, e.pin.atoms⟩) =
        .error .sourceNotCovered := by
  refine ⟨?_, transclude_uncovered_refused author operation document context progress
    transclusion link _ huncovered⟩
  simp [admitEvidence, huncovered]

/-! ## (d) A cell's atom pins are its transclusion requests' pins -/

/-- An evidence container as minidregg's `TranscludeRequest` (snapshot mode),
defined when it names a range. -/
def _root_.World.Evidence.toRequest (e : Evidence) : Option TranscludeRequest :=
  e.info.range.map fun range => ⟨e.pin.source.digest.value, range, .snapshot, e.pin.atoms⟩

/-- **Where they part ways (d):** a pin of the whole document has no request. -/
theorem toRequest_none_iff (e : Evidence) : e.toRequest = none ↔ e.info.range = none := by
  simp [Evidence.toRequest]

/-- **(d) The cell's (document, atom, revision) pins are exactly the
requests' `pins`**, each paired with the document its request names
(`documentOf`). -/
theorem cellAtomPins_eq_requests {P : Digest → Type} (cell : Cell P)
    (reqs : List TranscludeRequest) (h : cell.evidence.mapM Evidence.toRequest = some reqs) :
    cellAtomPins cell = reqs.flatMap fun q => q.pins.map (documentOf q.source, ·) := by
  unfold cellAtomPins
  generalize cell.evidence = evs at h
  induction evs generalizing reqs with
  | nil => simp at h; subst h; rfl
  | cons e es ih =>
    rw [List.mapM_cons] at h
    cases he : e.toRequest with
    | none => simp [he] at h
    | some q =>
      cases hr : es.mapM Evidence.toRequest with
      | none => simp [he, hr] at h
      | some qs =>
        simp [he, hr] at h
        subst h
        rw [List.flatMap_cons, List.flatMap_cons, ih qs hr]
        obtain ⟨⟨w, r⟩, ⟨src, atoms⟩⟩ := e
        cases r with
        | none => simp [Evidence.toRequest] at he
        | some range =>
          simp only [Evidence.toRequest, Option.map_some, Option.some.injEq] at he
          subst he
          simp [documentOf_digest]

end World.Minidregg
