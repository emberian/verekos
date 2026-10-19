/-
# VerekosMap.Model — the slice-1 documents as values of the World shapes

The cell contents are computed by the model's own definitions:
`World.toDocument` / `World.encode` (objects and their edges),
`World.encodeConflict` (conflicts, with the signature derived by the model),
`World.Manifest.compile` (the manifest's links), `World.importSource` and
`World.reimport` (source documents), `World.ReviewDoc.append` (review
decisions), `World.CompileRunDoc` and `World.replayedDeterministic`
(compile runs and the attestation label).

The carriers are concrete strings: a source is named by its key (`shop`), a
range by a statement's structural key (`create-table:customers#0`), an atom
revision is (atom id, revision) as the deployed Host spells them, and a claim
id is a logical key (`sql-analyzer-table:customers`).

What turns these values into client actions is `VerekosMap.Render`, which is
untrusted. Building the values from EKOS's export and the signed reads is
parsing, also untrusted.
-/
import World.Shapes
import VerekosMap.Json
import VerekosMap.Bytes

namespace VerekosMap

open World

/-- The slice-1 carriers: the one `Carriers` instance in scope here (map/ imports only WorldCore
modules, not `World.Minidregg`, whose instance is minidregg's own record types). -/
instance mapCarriers : Carriers where
  SchemaId := String
  SourceId := String
  Range := String
  Digest := String
  Time := String
  RunId := String
  Stage := String
  KeyPart := String
  AtomRev := String × String
  Name := String
  ClaimId := String

/-- The carriers are strings; these let messages interpolate them. -/
instance : ToString Carriers.KeyPart := inferInstanceAs (ToString String)
instance : ToString Carriers.ClaimId := inferInstanceAs (ToString String)
instance : ToString Carriers.SourceId := inferInstanceAs (ToString String)

/-- A compiled claim's payload: a table's EKOS properties, or an edge. -/
inductive Payload where
  | table (ekosId : String) (kind : String) (properties : J)
  | edge (kind : String) (toName : String)
  deriving Inhabited

abbrev Pl : Carriers.SchemaId → Type := fun _ => Payload

/-- Claim ids are the logical key: the subject's parts joined by `:`. The one
`ClaimIdDerivation` instance in scope. -/
instance mapDerivation : ClaimIdDerivation := ⟨fun k => ":".intercalate k.subject⟩

/-- The logical key of a claim key (the derivation above). -/
def logicalKey (k : ClaimKey) : String := ClaimIdDerivation.claimId k

/-- An edge claim's subject is `[from, kind, to]`. -/
def edgeView : EdgeView Pl :=
  ⟨fun c => match c.key.subject with
    | [f, _, t] => some (f, t)
    | _ => none⟩

def tableKey (name : String) : String := s!"sql-analyzer-table:{name}"

/-- A source pin of one statement atom: weight per mille 1000, the statement's
structural key as the range. -/
def statementPin (src structural atom rev : String) : Pin :=
  ⟨.source src (some structural), .atoms [(atom, rev)], 1000⟩

/-- A Table claim. -/
def tableClaim (name ekosId kind : String) (properties : J) (sources : List String)
    (pins : List (Pin)) : Claim Pl :=
  ⟨⟨kind, ["sql-analyzer-table", name], sources⟩, Payload.table ekosId kind properties, pins, ⟨none, none⟩⟩

/-- An edge claim from `fromName` to `toName`. -/
def edgeClaim (fromName kind toName : String) (sources : List String) (pins : List (Pin)) :
    Claim Pl :=
  ⟨⟨kind, [tableKey fromName, kind, tableKey toName], sources⟩, Payload.edge kind toName, pins,
    ⟨none, none⟩⟩

/-- The object document: `World.toDocument`. -/
def objectDocument (c : Claim Pl) (edges : List (Claim Pl)) : Except String (ObjectDocument Pl) :=
  match toDocument edgeView c edges with
  | some d => pure d
  | none => throw s!"World.toDocument refused {logicalKey c.key} (an ill-shaped pin or an edge not from it)"

/-- `ekos_common::ContentHash::of_str` over `{"attribute":…,"claims":[[value,path,source],…]}`
(EKOS `conflicts.rs` `signature`), here as the model's `sigOf`. `where_` gives each
source's (path, claimed_by). -/
def ekosSignature (where_ : String → String × String) (attr : String) (members : List (String × String)) :
    String :=
  sha256Hex (J.compact (.obj [("attribute", .str attr),
    ("claims", .arr (members.map fun (v, src) =>
      let (path, by_) := where_ src
      .arr [.raw v, .str path, .str by_]))]))

/-- The conflict document: `World.encodeConflict`, signature derived by the model. -/
def conflictDocument (where_ : String → String × String) (k : Conflict) : ConflictDoc :=
  encodeConflict (ekosSignature where_) k

/-- The manifest after a compile that emits `emitted`: `World.Manifest.compile`. -/
def manifestAfter (current : Manifest) (emitted : List (List String × String)) : Manifest :=
  current.compile emitted

/-- A source document as imported: `World.importSource`. -/
def importedSource (atomOf : List String → String) (h : SourceHeader) (stmts : List (Statement))
    : SourceDoc String :=
  importSource atomOf h stmts 0

/-- A source document re-imported at revision `r`: `World.reimport`. -/
def reimportedSource (atomOf : List String → String) (d : SourceDoc String)
    (stmts : List (Statement)) (r : Nat) : SourceDoc String :=
  reimport atomOf d stmts r

/-- The CLI's review verbs as model statuses. -/
def verbStatus : String → Option Status
  | "resolve" => some .resolved
  | "confirm" => some .confirmed
  | "reject" => some .rejected
  | "dismiss" => some .dismissed
  | _ => none

def statusVerb : Status → String
  | .resolved => "resolve"
  | .confirmed => "confirm"
  | .rejected => "reject"
  | .dismissed => "dismiss"
  | _ => "unknown"

/-- The attestation's label: `World.replayedDeterministic`, decided. -/
def attestationLabel (run : CompileRunDoc) (att : ReplayAttestation) : Bool :=
  decide (replayedDeterministic run [att])

end VerekosMap
