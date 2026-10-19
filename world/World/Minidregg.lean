/-
# World.Minidregg — the carriers, instantiated with minidregg's types

The core model (`World.Claim` and the files built on it) leaves its carriers
abstract. This file fills them with minidregg's identifier types from
`Minidregg.Theory.Hyperdocument` (minidregg commit dcab86da, the pin in
`lakefile.toml`). Only this file imports minidregg.

Choices made here (all ours, none is minidregg's):
- a claim id is an `ElementId`: exploration 02 §4 makes a claim an element of a
  compiled document;
- a schema id is a `Digest`, as `DocumentRecord.schema` is;
- a source is a `DocumentId`, a range is a `StableRange`;
- a revision read from a source is `AtomId × OperationId`, the shape of
  minidregg's transclusion pins, compared against `AtomRecord.revision`;
- a principal name is a `Digest` (what `PrincipalRef.principalId` returns);
- a compile run is named by the `DocumentId` of its run record
  (exploration 01's `ekos/compile-run/v1`). minidregg's own `RunId` is a text
  run inside a stable range, a different thing, and is not used here;
- domain time is `Nat`; a stage is a `Digest`; a subject key part is bytes.

Quoted from minidregg, never redefined: `Digest`, `DocumentId`, `AtomId`,
`OperationId`, `ElementId`, `StableRange`, `AtomRecord`, `AtomRecord.revision`,
`DigestDerivation`, `DigestDerivation.digestBytes`, `deriveIdentifier`,
`IdPreimage`, `encodePreimage`, `preimageCodec_encode_injective`.
-/
import Theory.Hyperdocument
import World.Claim

namespace World.Minidregg

set_option autoImplicit false

open Minidregg.Theory.Hyperdocument (DocumentId AtomId OperationId ElementId StableRange
  AtomRecord DigestDerivation deriveIdentifier IdPreimage encodePreimage
  preimageCodec_encode_injective)
open Minidregg.Theory.TypedAuthorization (Digest)

/-- The VerEKOS carriers over minidregg's types. -/
def carriers : Carriers where
  SchemaId := Digest
  SourceId := DocumentId
  Range := StableRange
  Digest := Digest
  Time := Nat
  RunId := DocumentId
  Stage := Digest
  KeyPart := List UInt8
  AtomRev := AtomId × OperationId
  Name := Digest
  ClaimId := ElementId
  decSchemaId := inferInstanceAs (DecidableEq Digest)
  decSourceId := inferInstanceAs (DecidableEq DocumentId)
  decRange := inferInstanceAs (DecidableEq StableRange)
  decDigest := inferInstanceAs (DecidableEq Digest)
  decTime := inferInstanceAs (DecidableEq Nat)
  decKeyPart := inferInstanceAs (DecidableEq (List UInt8))
  decAtomRev := inferInstanceAs (DecidableEq (AtomId × OperationId))
  decName := inferInstanceAs (DecidableEq Digest)
  decClaimId := inferInstanceAs (DecidableEq ElementId)

/-- A claim id derived the way minidregg derives every identifier: encode the
key to bytes (`encode`, supplied by the deployment; minidregg has no encoder
for our keys), wrap it in the v1 `element` preimage envelope, and digest it
with the deployment's `DigestDerivation`. -/
def claimIdDerivation (dd : DigestDerivation) (encode : ClaimKey → List UInt8) :
    ClaimIdDerivation where
  claimId k := (deriveIdentifier dd (⟨encode k⟩ : IdPreimage .v1 .element) : ElementId)

/-- **Where the injectivity premise comes from.** If the key encoder is
injective and the deployment's digest function is injective, claim ids are
injective in keys. The envelope step is minidregg's own theorem
(`preimageCodec_encode_injective`).

The digest premise is an idealization: a real hash is not injective, and
minidregg deliberately attaches no such property to `DigestDerivation`. Every
theorem in `World.Status` that needs injective ids takes it as a hypothesis,
and this theorem says what would discharge it. -/
theorem claimId_injective (dd : DigestDerivation) (encode : ClaimKey → List UInt8)
    (hdd : Function.Injective dd.digestBytes) (henc : Function.Injective encode) :
    Function.Injective (claimIdDerivation dd encode).claimId := by
  intro k₁ k₂ h
  simp only [claimIdDerivation, deriveIdentifier] at h
  have hdig := congrArg (fun x : ElementId => x.digest) h
  simp only at hdig
  have hpre := preimageCodec_encode_injective .v1 .element (hdd hdig)
  have hbytes := congrArg IdPreimage.payload hpre
  exact henc hbytes

/-- A source pin's read atoms are all still at the revision read, according
to a lookup of the current atom records. -/
def sourcePinFresh (lookup : AtomId → Option AtomRecord) (read : List (AtomId × OperationId)) :
    Bool :=
  read.all fun ar =>
    match lookup ar.1 with
    | some rec => decide (rec.revision = ar.2)
    | none => false

/-- Freshness, exactly: every atom read exists and still has the revision read. -/
theorem sourcePinFresh_iff (lookup : AtomId → Option AtomRecord)
    (read : List (AtomId × OperationId)) :
    sourcePinFresh lookup read = true ↔
      ∀ ar ∈ read, ∃ rec, lookup ar.1 = some rec ∧ rec.revision = ar.2 := by
  unfold sourcePinFresh
  rw [List.all_eq_true]
  refine forall₂_congr fun ar _ => ?_
  cases lookup ar.1 <;> simp

/-- **An edit makes the pin stale.** If an atom a pin read now has a different
`AtomRecord.revision` (minidregg moves the revision on every semantic edit),
or is gone, the pin is not fresh. -/
theorem stale_of_moved (lookup : AtomId → Option AtomRecord)
    (read : List (AtomId × OperationId)) (a : AtomId) (r : OperationId)
    (hread : (a, r) ∈ read) (hmoved : ∀ rec, lookup a = some rec → rec.revision ≠ r) :
    sourcePinFresh lookup read = false := by
  cases h : sourcePinFresh lookup read
  · rfl
  · obtain ⟨rec, hl, hr⟩ := (sourcePinFresh_iff lookup read).mp h (a, r) hread
    exact absurd hr (hmoved rec hl)

end World.Minidregg
