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

/-- The slice-1 carriers. -/
abbrev MC : Carriers where
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

/-- A compiled claim's payload: a table's EKOS properties, or an edge. -/
inductive Payload where
  | table (ekosId : String) (kind : String) (properties : J)
  | edge (kind : String) (toName : String)
  deriving Inhabited

abbrev Pl : MC.SchemaId → Type := fun _ => Payload

/-- Claim ids are the logical key: the subject's parts joined by `:`. -/
def derivation : ClaimIdDerivation MC := ⟨fun k => ":".intercalate k.subject⟩

/-- An edge claim's subject is `[from, kind, to]`. -/
def edgeView : EdgeView MC Pl :=
  ⟨fun c => match c.key.subject with
    | [f, _, t] => some (f, t)
    | _ => none⟩

def tableKey (name : String) : String := s!"sql-analyzer-table:{name}"

/-- A source pin of one statement atom: weight per mille 1000, the statement's
structural key as the range. -/
def statementPin (src structural atom rev : String) : Pin MC :=
  ⟨.source src (some structural), .atoms [(atom, rev)], 1000⟩

/-- A Table claim. -/
def tableClaim (name ekosId kind : String) (properties : J) (sources : List String)
    (pins : List (Pin MC)) : Claim MC Pl :=
  ⟨⟨kind, ["sql-analyzer-table", name], sources⟩, Payload.table ekosId kind properties, pins, ⟨none, none⟩⟩

/-- An edge claim from `fromName` to `toName`. -/
def edgeClaim (fromName kind toName : String) (sources : List String) (pins : List (Pin MC)) :
    Claim MC Pl :=
  ⟨⟨kind, [tableKey fromName, kind, tableKey toName], sources⟩, Payload.edge kind toName, pins,
    ⟨none, none⟩⟩

/-- The object document: `World.toDocument`. -/
def objectDocument (c : Claim MC Pl) (edges : List (Claim MC Pl)) : Except String (ObjectDocument MC Pl) :=
  match toDocument derivation edgeView c edges with
  | some d => pure d
  | none => throw s!"World.toDocument refused {derivation.claimId c.key} (an ill-shaped pin or an edge not from it)"

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
def conflictDocument (where_ : String → String × String) (k : Conflict MC) : ConflictDoc MC :=
  encodeConflict (ekosSignature where_) k

/-- The manifest after a compile that emits `emitted`: `World.Manifest.compile`. -/
def manifestAfter (current : Manifest MC) (emitted : List (List String × String)) : Manifest MC :=
  current.compile emitted

/-- A source document as imported: `World.importSource`. -/
def importedSource (atomOf : List String → String) (h : SourceHeader MC) (stmts : List (Statement MC))
    : SourceDoc MC String :=
  importSource atomOf h stmts 0

/-- A source document re-imported at revision `r`: `World.reimport`. -/
def reimportedSource (atomOf : List String → String) (d : SourceDoc MC String)
    (stmts : List (Statement MC)) (r : Nat) : SourceDoc MC String :=
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
def attestationLabel (run : CompileRunDoc MC) (att : ReplayAttestation MC) : Bool :=
  decide (replayedDeterministic run [att])

end VerekosMap
