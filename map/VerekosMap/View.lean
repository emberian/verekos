/-
# VerekosMap.View — reading a signed view and an EKOS graph export

UNTRUSTED (a parser). A `mini workspace --action read` view is the cell's
entries; this file indexes them by type and id, in the order they appear
(Python dict order, which the twin iterates). An EKOS `graph export
--format ndjson` is a header, nodes and edges.
-/
import VerekosMap.Json
import VerekosMap.Split

namespace VerekosMap

/-- An insertion-ordered map (Python `dict`: a repeated key keeps its first
position and takes the last value). -/
abbrev OMap (α : Type) := List (String × α)

def OMap.insert {α : Type} (m : OMap α) (k : String) (v : α) : OMap α :=
  if m.any (·.1 == k) then m.map fun (k', v') => if k' == k then (k', v) else (k', v')
  else m ++ [(k, v)]

def OMap.get? {α : Type} (m : OMap α) (k : String) : Option α := (m.find? (·.1 == k)).map (·.2)

def OMap.contains {α : Type} (m : OMap α) (k : String) : Bool := m.any (·.1 == k)

def readJsonFile (path : System.FilePath) : IO J := do
  match J.parse (← IO.FS.readFile path) with
  | .ok j => pure j
  | .error e => throw (IO.userError s!"{path}: {e}")

def liftM {α : Type} (x : Except String α) : IO α :=
  match x with
  | .ok a => pure a
  | .error e => throw (IO.userError e)

/-- The fields of one entry as a string, or "" when absent or not a string
(the mapper only compares them with ids). -/
def J.s (j : J) (k : String) : String := ((j.get? k).bind J.str?).getD ""

/-- The parts of a read view the mapper uses (the twin's `Doc`). -/
structure Doc where
  target : String
  atoms : OMap J
  runs : OMap J
  elements : OMap J
  transclusions : OMap J
  links : OMap J
  document : Option J

def Doc.ofView (view : J) : Except String Doc := do
  let target ← match view.get? "target" with
    | some (.str s) => pure s
    | some (.num n) => pure (toString n)
    | _ => throw "read view has no target (the runner adds the reference's target)"
  let entries := (((view.get? "cell").bind (·.get? "entries")).bind J.arr?).getD []
  let index (ty : String) : OMap J :=
    entries.foldl (fun m e => if e.s "type" == ty then m.insert (e.s "id") e else m) []
  let docs := entries.filter (·.s "type" == "document")
  pure ⟨target, index "atom", index "run", index "element", index "transclusion", index "link",
    docs.head?⟩

def Doc.load (path : System.FilePath) : IO Doc := do liftM (Doc.ofView (← readJsonFile path))

/-- The exact prior record `editAtom` is guarded on: the atom minus `type`,
`id`, `canonical`. -/
def Doc.before (d : Doc) (atom : String) : J :=
  match d.atoms.get? atom with
  | some (.obj kvs) => .obj (kvs.filter fun (k, _) => k != "type" && k != "id" && k != "canonical")
  | _ => .null

def Doc.payloadHex (d : Doc) (atom : String) : String := ((d.atoms.get? atom).map (·.s "payload")).getD ""

def Doc.payload (d : Doc) (atom : String) : Except String String := unhexText (d.payloadHex atom)

def Doc.revision (d : Doc) (atom : String) : String := ((d.atoms.get? atom).map (·.s "revision")).getD ""

def Doc.elementRevision (d : Doc) (el : String) : String :=
  ((d.elements.get? el).map (·.s "revision")).getD ""

def isLive (e : J) : Bool := match e.get? "tombstonedAt" with
  | none | some .null => true
  | some (.str "null") => true
  | _ => false

/-- An atom kind's JSON: `{"type":"inlineObject","schema":…}`. -/
def objKind (name : String) : J := .obj [("type", .str "inlineObject"), ("schema", .str (schemaId name))]

def textKind : J := .obj [("type", .str "text")]

/-- Python `==` on the `kind` dicts (order-free). -/
def kindIs (e : J) (name : String) : Bool :=
  match e.get? "kind" with
  | some k => k.s "type" == "inlineObject" && k.s "schema" == schemaId name &&
      (match k with | .obj kvs => kvs.length == 2 | _ => false)
  | none => false

end VerekosMap
