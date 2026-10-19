/-
# World.Claim — the claim and the receipt

This file states the two records of the VerEKOS model (design 2026-10-19 §2,
exploration 02 §1.2), with every carrier left abstract. `World.Minidregg`
instantiates the carriers with minidregg's real identifier types; nothing here
imports minidregg or Mathlib.

In plain words:
- A **claim** is a typed statement about one subject. What it is "about" is
  its key: (schema, subject, the source documents that assert it). It carries
  one or more pins and a domain validity window.
- A **pin** is a target plus the revision it was read at. The target is a part
  of an imported source document, or another claim.
- A **receipt** is one log entry: a transaction number, a put or a retract of
  a claim, who wrote it, and in which run and stage.
- A claim has no status field. Status is computed from reviews
  (`World.Status`).

Every name in this file is new to VerEKOS; none is taken from minidregg.
-/

namespace World

set_option autoImplicit false

/-- The abstract carriers of the model, with decidable equality where the
model compares values. `World.Minidregg` fills them with minidregg's types.

`ClaimId` is a carrier, not an opaque constant: how an id is computed from a
key is the separate `ClaimIdDerivation`, and whether that computation is
injective is a premise each theorem states when it needs it (the same stance
as minidregg's `DigestDerivation`, which carries no injectivity proof). -/
class Carriers where
  /-- Which kind of claim (Table, ForeignKey, Review, Conflict, …). -/
  SchemaId : Type
  /-- One imported source document. -/
  SourceId : Type
  /-- A part of a source document. -/
  Range : Type
  /-- Digests: core digests, normalized attribute names and values. -/
  Digest : Type
  /-- Domain time, for validity windows. Never compared with transaction numbers. -/
  Time : Type
  /-- One compiler run. -/
  RunId : Type
  /-- One compiler stage (build, recover, compile, commit, review, …). -/
  Stage : Type
  /-- One component of a subject key (a path segment, an index, a normalized name). -/
  KeyPart : Type
  /-- The revision of one source atom as read (minidregg: `AtomId × OperationId`). -/
  AtomRev : Type
  /-- A named principal. -/
  Name : Type
  /-- Claim identities. -/
  ClaimId : Type
  [decSchemaId : DecidableEq SchemaId]
  [decSourceId : DecidableEq SourceId]
  [decRange : DecidableEq Range]
  [decDigest : DecidableEq Digest]
  [decTime : DecidableEq Time]
  [decKeyPart : DecidableEq KeyPart]
  [decAtomRev : DecidableEq AtomRev]
  [decName : DecidableEq Name]
  [decClaimId : DecidableEq ClaimId]

/-- The carriers' decidable equalities, as instances. -/
instance [C : Carriers] : DecidableEq C.SchemaId := C.decSchemaId
instance [C : Carriers] : DecidableEq C.SourceId := C.decSourceId
instance [C : Carriers] : DecidableEq C.Range := C.decRange
instance [C : Carriers] : DecidableEq C.Digest := C.decDigest
instance [C : Carriers] : DecidableEq C.Time := C.decTime
instance [C : Carriers] : DecidableEq C.KeyPart := C.decKeyPart
instance [C : Carriers] : DecidableEq C.AtomRev := C.decAtomRev
instance [C : Carriers] : DecidableEq C.Name := C.decName
instance [C : Carriers] : DecidableEq C.ClaimId := C.decClaimId

variable [C : Carriers]

/-- What a claim's identity is computed from. It holds no run, no time, no
range and no revision, so an id cannot depend on any of them.
`sources` is meant to be sorted and duplicate-free; this file does not enforce
that, and an importer that builds two keys for one source set would mint two
ids. -/
structure ClaimKey where
  schema : C.SchemaId
  subject : List C.KeyPart
  sources : List C.SourceId
  deriving DecidableEq

/-- How a deployment computes a claim id from a key. No injectivity is
attached: theorems that need "different keys give different ids" take
`Function.Injective ClaimIdDerivation.claimId` as a hypothesis. -/
class ClaimIdDerivation where
  claimId : ClaimKey → C.ClaimId

/-- What a pin points at: part of a source document (`none` = the whole
document), or another claim. -/
inductive PinTarget where
  | source (doc : C.SourceId) (range : Option C.Range)
  | claim (id : C.ClaimId)
  deriving DecidableEq

/-- The revision a pin read: the atoms of a source range with the revision of
each, or the core digest of a premise claim. -/
inductive PinRevision where
  | atoms (read : List C.AtomRev)
  | core (digest : C.Digest)
  deriving DecidableEq

/-- A pin. `weight` is per mille (0–1000); EKOS stores it as a float
(`KirEvidence.confidence`). Nothing here bounds it by 1000. -/
structure Pin where
  target : PinTarget
  revision : PinRevision
  weight : Nat
  deriving DecidableEq

/-- Domain validity, never a transaction number. -/
structure Window where
  validFrom : Option C.Time
  validUntil : Option C.Time
  deriving DecidableEq

/-- A claim. The payload's type depends on the schema. The law "pins are
nonempty" is not part of the type; `World.Visible` treats an unpinned claim as
hidden, so breaking the law fails closed. -/
structure Claim (P : C.SchemaId → Type) where
  key : ClaimKey
  payload : P key.schema
  pins : List (Pin)
  valid : Window

section claimDecEq
variable {C} {P : C.SchemaId → Type} [∀ s, DecidableEq (P s)]

/-- Claims are equal when key, payload, pins and window are equal. -/
instance Claim.decEq : DecidableEq (Claim P) := fun a b =>
  match a, b with
  | ⟨k₁, x₁, p₁, w₁⟩, ⟨k₂, x₂, p₂, w₂⟩ =>
    if hk : k₁ = k₂ then by
      subst hk
      exact
        if hx : x₁ = x₂ then
          if hp : p₁ = p₂ then
            if hw : w₁ = w₂ then isTrue (by subst hx hp hw; rfl)
            else isFalse (fun h => hw (by cases h; rfl))
          else isFalse (fun h => hp (by cases h; rfl))
        else isFalse (fun h => hx (by cases h; rfl))
    else isFalse (fun h => hk (by cases h; rfl))

end claimDecEq

/-- Claim states. Which one a schema starts in is `Schema.initial`. -/
inductive Status where
  | observed | hypothesis | proposed | open | unconfirmed
  | confirmed | rejected | needsReview | resolved | dismissed
  deriving DecidableEq, Repr

/-- Who wrote a receipt, by kind. -/
inductive PrincipalKind where
  | compiler | agent | human
  deriving DecidableEq, Repr

/-- Everything VerEKOS needs to know about one schema `s`.
- `core`: the digest a review and a staleness check compare.
- `structural`: claims of this schema are identified by a structural key and
  are never merge candidates (EKOS `structurally_keyed`).
- `initial`: the status before any admitted review.
- `isFact`: may a traversal cross a claim in this status?
- `mayDecide k`: may a principal of kind `k` move a claim of this schema to
  status `d`?
- `stated`: the (attribute, normalized value) pairs the payload states
  outright; conflicts compare only these. -/
structure Schema (P : C.SchemaId → Type) (s : C.SchemaId) where
  core : P s → C.Digest
  structural : Bool
  initial : Status
  isFact : Status → Bool
  mayDecide : PrincipalKind → Status → Bool
  stated : P s → List (C.Digest × C.Digest)

/-- The schema table: one `Schema` per schema id. -/
abbrev Registry (P : C.SchemaId → Type) := (s : C.SchemaId) → Schema P s

/-- A log operation: install a claim value, or remove the claim with this id. -/
inductive Op (P : C.SchemaId → Type) where
  | put (c : Claim P)
  | retract (id : C.ClaimId)

/-- A log entry. Provenance and observation time live here, never on the
claim. -/
structure Receipt (P : C.SchemaId → Type) where
  tx : Nat
  op : Op P
  author : PrincipalKind × C.Name
  run : C.RunId
  stage : C.Stage

variable {C}

/-- The id a claim is stored under. -/
def Claim.id {P : C.SchemaId → Type} [d : ClaimIdDerivation] (c : Claim P) : C.ClaimId :=
  ClaimIdDerivation.claimId c.key

/-- The id an operation touches. -/
def Op.id {P : C.SchemaId → Type} [d : ClaimIdDerivation] : Op P → C.ClaimId
  | .put c => c.id
  | .retract i => i

/-- A claim's core digest, read through its schema. -/
def Claim.core {P : C.SchemaId → Type} (reg : Registry P) (c : Claim P) : C.Digest :=
  (reg c.key.schema).core c.payload

end World
