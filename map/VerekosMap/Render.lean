/-
# VerekosMap.Render — World documents as minidregg client actions

UNTRUSTED (a renderer). This file turns the values `VerekosMap.Model` builds
with the World shapes into proposal-v1 `invoke` requests, in the action
order, id derivation and JSON spelling of `slice1/mapper.py`, so that the
bytes are the same. It also diffs a recompile against the cells' current
documents (mapper.py's `Builder`). The receipt that it reproduces the twin is
byte-identity on slice 1's run-2 (`notes/W24-lean-mapper.md`).

Where the deployed documents carry something the shape does not (the meta
atoms' `pass`, `fragment_kind` and `located_by`, the header's `ekos_id`,
`compiler` and `mapper`, a conflict claim's `path`, `line` and `claimed_by`,
the manifest's source-header transclusions, the compile-run record's
statement map and `mapper_sha256`, a decision's `pick`), this file takes it
from the inputs directly. The memo lists each.
-/
import VerekosMap.Model
import VerekosMap.View

namespace VerekosMap

open World

def MAPPER_VERSION : String := "verekos-slice1-mapper/1"
def DEATH : String := "keepTombstone"

/-- Python `str.lower()`, refused for non-ASCII text (Unicode lowering is not
reproduced here). -/
def lowerAscii (s : String) : Except String String := do
  if s.toList.any (fun c => decide (c.toNat > 127)) then throw s!"non-ASCII name {s.quote}: Python's Unicode lower() is not reproduced"
  pure (String.ofList (s.toList.map asciiLower))

/-- mapper.py `safe`: lower, runs of anything but `[a-z0-9]` to `-`, trim `-`. -/
def safe (s : String) : Except String String := do
  let l ← lowerAscii s
  let mut out := ""
  let mut dash := false
  for c in l.toList do
    if ('a' ≤ c ∧ c ≤ 'z') ∨ ('0' ≤ c ∧ c ≤ '9') then
      if dash then out := out.push '-'
      dash := false
      out := out.push c
    else dash := true
  if dash then out := out.push '-'
  pure (String.ofList ((out.toList.dropWhile (· == '-')).reverse.dropWhile (· == '-')).reverse)

def tableCell (name : String) : Except String String := return "obj-" ++ (← safe name)

def sortStr (xs : List String) : List String := xs.mergeSort fun a b => decide (a ≤ b)

def dedupSorted (xs : List String) : List String :=
  (sortStr xs).foldr (fun x acc => match acc with
    | y :: _ => if x == y then acc else x :: acc
    | [] => [x]) []

/-! ## Sources -/

/-- One imported source cell (mapper.py `Source`). -/
structure Source where
  key : String
  doc : Doc
  cell : String
  path : String
  headerAtom : String
  headerRun : String
  stmtRun : String
  /-- (structural key, atom id) in run order, live atoms only. -/
  order : List (String × String)

def idsForSource (key path : String) : String × String × String × String :=
  (num ["element", key, path, "root"], num ["atom", key, path, "header"],
   num ["run", key, path, "header"], num ["run", key, path, "statements"])

def sourceHeader (d : Doc) : Except String J := do
  for (_, a) in d.atoms do
    if kindIs a "ekos/source-header/v1" then
      return ← J.parse (← unhexText (a.s "payload"))
  throw s!"read of {d.target}: no ekos/source-header/v1 atom"

/-- The structural key an atom's id was derived from (mapper.py `key_of_atom`). -/
def keyOfAtom (key path : String) (d : Doc) (aid : String) : Except String String := do
  let k ← structuralKey (← d.payload aid)
  for occ in List.range 64 do
    if num ["atom", key, path, s!"{k}#{occ}"] == aid then return s!"{k}#{occ}"
  throw s!"atom {aid} of {key}: key changed under its id (a rename is a new statement)"

def runAtoms (r : J) : List String :=
  ((r.get? "atoms").bind J.arr? |>.getD []).map fun
    | .str s => s
    | .num n => toString n
    | _ => ""

def Source.ofDoc (key : String) (d : Doc) : Except String Source := do
  let h ← sourceHeader d
  let sk := h.s "source_key"
  if sk != key then throw s!"source {key}: header says {sk}"
  let path := h.s "path"
  let (_, ha, hr, sr) := idsForSource key path
  let order := match d.runs.get? sr with
    | some r => runAtoms r
    | none => []
  let mut out : Array (String × String) := #[]
  for aid in order do
    match d.atoms.get? aid with
    | none => continue
    | some a =>
      if !isLive a then continue
      out := out.push (← keyOfAtom key path d aid, aid)
  pure ⟨key, d, h.s "cell", path, ha, hr, sr, out.toList⟩

def Source.text (s : Source) : Except String String := do
  let mut out := ""
  for (_, a) in s.order do out := out ++ (← s.doc.payload a)
  pure out

/-- (atom, revision) of a statement (mapper.py `Source.pin`): the last atom with
that key, as a Python dict would keep. -/
def Source.pin (s : Source) (structural : String) : Except String (String × String) :=
  match (s.order.reverse.find? (·.1 == structural)) with
  | some (_, a) => pure (a, s.doc.revision a)
  | none => throw s!"source {s.key}: no statement {structural}"

def Source.has (s : Source) (structural : String) : Bool := s.order.any (·.1 == structural)

def rangeJ (run atom : String) : J :=
  .obj [("start", .obj [("run", .str run), ("neighbor", .str atom), ("bias", .str "before"), ("death", .str DEATH)]),
        ("finish", .obj [("run", .str run), ("neighbor", .str atom), ("bias", .str "after"), ("death", .str DEATH)])]

/-- A snapshot transclusion request over one atom of a document at a revision. -/
def snapshotJ (target run atom rev : String) : J :=
  .obj [("source", .str target), ("range", rangeJ run atom), ("mode", .str "snapshot"),
        ("pins", .arr [.obj [("atom", .str atom), ("revision", .str rev)]])]

def Source.snapshot (s : Source) (atom : String) (run : Option String := none) : J :=
  snapshotJ s.doc.target (run.getD s.stmtRun) atom (s.doc.revision atom)

def ekosPath (s : Source) : String := s!"src/{s.key}/{s.path}"

/-! ## Requests -/

def invokeJ (cell : String) (actions : List J) (reads : List String) : J :=
  .obj [("type", .str "minidregg-workspace-proposal-v1"), ("action", .str "invoke"),
        ("targets", .arr ((.obj [("name", .str cell), ("payload", .obj [("type", .str "content"),
            ("actions", .arr actions)])]) :: (dedupSorted reads).map fun r =>
          .obj [("name", .str r), ("payload", .obj [("type", .str "read")])]))]

/-- The request file's bytes: compact JSON and a newline. -/
def requestBytes (req : J) : String := J.compact req ++ "\n"

/-! ## The export -/

structure Node where
  id : String
  n : String
  kind : String
  p : J

structure Edge where
  kind : String
  src : Node
  dst : Node

def loadExport (path : System.FilePath) : IO (List Node × List Edge) := do
  let text ← IO.FS.readFile path
  let mut kinds : List String := []
  let mut rkinds : List String := []
  let mut nodes : Array J := #[]
  let mut edges : Array J := #[]
  for line in text.splitOn "\n" do
    if line.isEmpty then continue
    let r ← liftM (J.parse line)
    match r.s "record" with
    | "header" =>
      kinds := ((r.get? "kind_index").bind J.arr? |>.getD []).map (·.str?.getD "")
      rkinds := ((r.get? "rel_kind_index").bind J.arr? |>.getD []).map (·.str?.getD "")
    | "node" => nodes := nodes.push r
    | "edge" => edges := edges.push r
    | _ => pure ()
  let idx (j : J) (k : String) : Nat := ((j.get? k).bind J.num?).getD 0 |>.toNat
  let ns := nodes.toList.map fun r =>
    ({ id := r.s "id", n := r.s "n", kind := kinds.getD (idx r "k") "",
       p := (r.get? "p").getD (.obj []) } : Node)
  let es := edges.toList.map fun r =>
    ({ kind := rkinds.getD (idx r "k") "", src := ns.getD (idx r "s") default,
       dst := ns.getD (idx r "t") default } : Edge)
  pure (ns, es)
where
  default : Node := ⟨"", "", "", .obj []⟩

/-! ## The plan -/

structure Row where
  cell : String
  schema : String
  law : String
  room : Option String
  node : Option String

def Row.toJ (r : Row) : J :=
  .obj [("cell", .str r.cell), ("schema", .str r.schema), ("law", .str r.law),
        ("room", match r.room with | some x => .str x | none => .null),
        ("node", match r.node with | some x => .str x | none => .null)]

/-- The sources defining a table, by structural key `create-table:<name>#0`
(slice-1 approximation 4: EKOS's table evidence names the file only). -/
def defining (sources : List Source) (table : String) : Except String (List (Source × String)) := do
  let key := s!"create-table:{← lowerAscii table}#0"
  pure (sources.filterMap fun s => if s.has key then some (s, key) else none)

def sortBy {α : Type} (f : α → String) (xs : List α) : List α := xs.mergeSort fun a b => decide (f a ≤ f b)

/-- One cell per Table, one per ConflictingEvidence, the manifest. A table's
room is its first defining source (approximation 8). -/
def buildPlan (nodes : List Node) (sources : List Source) : Except String (List Row) := do
  let mut plan : Array Row := #[]
  for n in sortBy (·.n) (nodes.filter (·.kind == "Table")) do
    let d ← defining sources n.n
    match d with
    | [] => throw s!"table {n.n}: no defining statement in any source"
    | (s, _) :: _ => plan := plan.push ⟨← tableCell n.n, "ekos/object/v1", "L-obj", some s.key, some n.id⟩
  for n in sortBy (·.n) (nodes.filter (·.kind == "ConflictingEvidence")) do
    plan := plan.push ⟨"cf-" ++ (← safe n.n), "ekos/conflict/v1", "L-obj", none, some n.id⟩
  plan := plan.push ⟨"manifest", "ekos/manifest/v1", "L-obj", none, none⟩
  pure plan.toList

/-! ## The builder (mapper.py `Builder`) -/

structure B where
  cell : String
  cur : Option Doc
  acts : Array J := #[]
  reads : List String := []
  root : String
  born : Bool
  rootRev : String

abbrev BM := StateT B (Except String)

def B.new (cell : String) (cur : Option Doc) : B :=
  let born := match cur with
    | none => true
    | some d => d.document.isNone
  let root := num ["element", cell, "root"]
  { cell, cur, root, born, rootRev := if born then "0" else (cur.map (·.elementRevision root)).getD "0" }

def bid (p : List String) : BM String := do
  let b ← get
  match p with
  | k :: rest => pure (num (k :: b.cell :: rest))
  | [] => pure (num [b.cell])

def emit (a : J) : BM Unit := modify fun b => { b with acts := b.acts.push a }

def addRead (r : String) : BM Unit := modify fun b => { b with reads := b.reads ++ [r] }

def curDoc : BM Doc := do
  match (← get).cur with
  | some d => pure d
  | none => throw "internal: no current document"

def birth (schemaName : String) : BM Unit := do
  let b ← get
  if b.born then
    emit (.obj [("type", .str "createDocument"), ("rootElement", .str b.root), ("schema", .str (schemaId schemaName))])

/-- Create, or edit when the bytes differ; a run over it when `run` is named.
True when created. -/
def atomAct (aid : String) (kind : J) (text : String) (run : Option String := none) : BM Bool := do
  let b ← get
  let p := hexs text
  let fresh := b.born || !(b.cur.map (·.atoms.contains aid)).getD false
  if fresh then
    emit (.obj [("type", .str "createAtom"), ("atom", .str aid), ("kind", kind), ("payload", .str p)])
    if let some r := run then
      emit (.obj [("type", .str "createRun"), ("run", .str r), ("atoms", .arr [.str aid])])
    return true
  let d ← curDoc
  if d.payloadHex aid != p then
    emit (.obj [("type", .str "editAtom"), ("atom", .str aid), ("before", d.before aid), ("kind", kind),
                ("payload", .str p), ("tombstone", .bool false)])
  return false

def editElement (el rev : String) (op : J) : J :=
  .obj [("type", .str "editElement"), ("element", .str el), ("revision", .str rev), ("op", op)]

/-- Detach `children` from the root and splice them into `container`. -/
def place (container : String) (children : List String) (containerRev : String := "0") : BM Unit := do
  let b ← get
  for (c, i) in children.zipIdx do
    emit (editElement b.root b.rootRev (.obj [("type", .str "remove"), ("child", .str c)]))
    emit (editElement container containerRev (.obj [("type", .str "splice"), ("index", .str (toString i)), ("child", .str c)]))

def parentOf (d : Doc) (el : String) : Option String :=
  match (d.elements.get? el).bind (·.get? "parent") with
  | some (.str "null") | some .null | none => none
  | some (.str s) => some s
  | some (.num n) => some (toString n)
  | some _ => none

def detach (el : String) : BM Unit := do
  let d ← curDoc
  let parent := (parentOf d el).getD "None"
  emit (editElement parent (d.elementRevision parent) (.obj [("type", .str "remove"), ("child", .str el)]))

/-- One evidence container for a pinned statement atom: a meta atom and a
snapshot transclusion. Returns (container, created). -/
def evidence (tag : String) (src : Source) (atom rev : String) (metaJ : J) : BM (String × Bool) := do
  let ids := fun (r : String) => do
    pure (← bid ["element", "ev", tag, src.key, atom, r], ← bid ["transclusion", "ev", tag, src.key, atom, r])
  let (container, tr) ← ids rev
  addRead src.cell
  let b ← get
  if !b.born then
    let d ← curDoc
    if d.transclusions.contains tr then return (container, false)
    for (_, t) in d.transclusions do
      let pins := ((t.get? "opening").bind (·.get? "pins")).bind J.arr? |>.getD []
      match pins with
      | p0 :: _ =>
        if p0.s "atom" == atom then
          let (oldC, oldT) ← ids (p0.s "revision")
          if oldT == t.s "id" && (parentOf d oldC).isSome then detach oldC
      | [] => pure ()
  let metaAtom ← bid ["atom", "ev-meta", tag, src.key, atom, rev]
  emit (.obj [("type", .str "createContainer"), ("element", .str container)])
  emit (.obj [("type", .str "createAtom"), ("atom", .str metaAtom), ("kind", objKind "ekos/evidence-meta/v1"),
              ("payload", .str (hexs (J.compact metaJ)))])
  emit (.obj [("type", .str "transclude"), ("transclusion", .str tr),
              ("link", .str (← bid ["link", "ev", tag, src.key, atom, rev])), ("request", src.snapshot atom)])
  place container [metaAtom, tr]
  return (container, true)

def evMeta (srcKey structural : String) (weight : Nat) (pass fragment locatedBy : String) : J :=
  .obj [("source_key", .str srcKey), ("structural_key", .str structural), ("confidence_milli", .num weight),
        ("pass", .str pass), ("fragment_kind", .str fragment), ("located_by", .str locatedBy)]

/-- The source of an evidence pin, and its one (atom, revision). -/
def pinParts (sources : List Source) (src : String) (atoms : List (String × String)) :
    Except String (Source × String × String) := do
  let some s := sources.find? (·.key == src) | throw s!"pin names source {src}, which was not read"
  match atoms with
  | [(a, r)] => pure (s, a, r)
  | _ => throw "an evidence pin here names exactly one atom"

/-! ## Objects -/

/-- `references\s+<to>\b` in the lowered statement (mapper.py's edge-evidence
guess, approximation 6). Refuses where Python's Unicode `\b` or `lower()`
would differ from ASCII. -/
def referencesName (text to : String) : Except String Bool := do
  if text.toList.any (fun c => c.toNat == 0x212a || c.toNat == 0x130) then
    throw "statement holds a character Python lowers to ASCII; not reproduced"
  let t := (text.toList.map asciiLower).toArray
  let w := "references".toList
  let name := (← lowerAscii to).toList
  let n := t.size
  for i in [0:n] do
    if (List.range w.length).all fun j => i + j < n && t[i + j]! == w[j]! then
      let mut k := i + w.length
      if !(k < n && pyIsSpace t[k]!) then continue
      while k < n && pyIsSpace t[k]! do k := k + 1
      if (List.range name.length).all fun j => k + j < n && t[k + j]! == name[j]! then
        let e := k + name.length
        if e < n then
          let c := t[e]!
          if c.toNat > 127 then throw "non-ASCII character after a REFERENCES name: Python's \\b is not reproduced"
          if c.isAlphanum || c == '_' then continue
        return true
  return false

structure Ctx where
  sources : List Source
  cells : J
  ekosVersion : String

def Ctx.cellId (x : Ctx) (name : String) : Except String String :=
  match x.cells.get? name with
  | some (.str s) => pure s
  | some (.num n) => pure (toString n)
  | _ => throw s!"cells.json has no {name}"

/-- The Table claim and its outgoing ForeignKey edge claims, from the export. -/
def tableClaims (x : Ctx) (node : Node) (edges : List Edge) :
    Except String (Claim MC Pl × List (Claim MC Pl)) := do
  let d ← defining x.sources node.n
  let pins ← d.mapM fun (s, k) => do
    let (a, r) ← s.pin k
    pure (statementPin s.key k a r)
  let c := tableClaim node.n node.id node.kind node.p (d.map (·.1.key)) pins
  let out := sortBy (·.dst.n) (edges.filter fun e => e.src.id == node.id && e.kind == "ForeignKey")
  let es ← out.mapM fun e => do
    let mut epins : Array (Pin MC) := #[]
    let mut esrcs : Array String := #[]
    for (s, k) in d do
      let (a, r) ← s.pin k
      if ← referencesName (← s.doc.payload a) e.dst.n then
        epins := epins.push (statementPin s.key k a r)
        esrcs := esrcs.push s.key
    pure (edgeClaim node.n e.kind e.dst.n esrcs.toList epins.toList)
  pure (c, es)

def evRange (e : Evidence MC) : String := e.info.range.getD ""

def tableActions (x : Ctx) (D : ObjectDocument MC Pl) : BM Unit := do
  let cell := D.object
  let .table ekosId kind props := (cell.properties : Payload) | throw "object cell without a table payload"
  let name := (cell.header.subject.getD 1 "")
  birth "ekos/object/v1"
  let _ ← atomAct (← bid ["atom", "header"]) (objKind "ekos/header/v1")
    (J.compact (.obj [("kind", .str kind), ("name", .str name), ("logical_key", .str (derivation.claimId cell.header)),
      ("ekos_id", .str ekosId), ("compiler", .str x.ekosVersion), ("mapper", .str MAPPER_VERSION),
      ("sources", .arr (cell.header.sources.map .str))]))
  let _ ← atomAct (← bid ["atom", "properties"]) (objKind "ekos/properties/v1") (J.compact props)
  for e in cell.evidence do
    let (s, a, r) ← StateT.lift (pinParts x.sources e.pin.source e.pin.atoms)
    let _ ← evidence "object" s a r (evMeta s.key (evRange e) e.info.weight "sql_analyzer" "create-table"
      "structural key (EKOS evidence names the file only)")
  for ec in D.edges do
    let .edge ekind to := (ec.edge.properties : Payload) | throw "edge cell without an edge payload"
    let tag := ["edge", ekind, to]
    let cont ← bid ("element" :: tag)
    let edgeAtom ← bid ("atom" :: tag)
    let run ← bid ("run" :: tag)
    let link ← bid ("link" :: tag)
    let b ← get
    if !b.born && ((b.cur.map (·.links.contains link)).getD false) then continue
    emit (.obj [("type", .str "createContainer"), ("element", .str cont)])
    let w := ec.edge.window
    let _ ← atomAct edgeAtom (objKind "ekos/edge/v1")
      (J.compact (.obj [("kind", .str ekind), ("to", .str ec.link), ("to_name", .str to), ("status", .str "confirmed"),
        ("properties", .obj []), ("valid_from", match w.validFrom with | some t => .str t | none => .null),
        ("valid_until", match w.validUntil with | some t => .str t | none => .null)])) (some run)
    let toCell ← StateT.lift (tableCell to)
    emit (.obj [("type", .str "link"), ("link", .str link), ("source", rangeJ run edgeAtom),
                ("target", .obj [("type", .str "document"), ("id", .str (← StateT.lift (x.cellId toCell)))]),
                ("relation", .str (schemaId ("relation/" ++ ekind)))])
    let mut kids := #[edgeAtom]
    for e in ec.edge.evidence do
      let (s, a, r) ← StateT.lift (pinParts x.sources e.pin.source e.pin.atoms)
      let (c, _) ← evidence ("edge-" ++ to) s a r (evMeta s.key (evRange e) e.info.weight "sql_analyzer" "foreign-key"
        "REFERENCES clause inside the referencing statement")
      kids := kids.push c
    place cont kids.toList

/-! ## Conflicts -/

/-- The conflict a ConflictingEvidence node states, as a `World.Conflict`; and
each claim's (path, line, claimed_by), which the shape does not carry. -/
def conflictOf (x : Ctx) (node : Node) : Except String (Conflict MC × List (String × String × J × String)) := do
  let p := node.p
  let subjectName := p.s "subject_name"
  let structural := s!"create-table:{← lowerAscii subjectName}#0"
  let claims := sortBy (·.s "path") ((p.get? "claims").bind J.arr? |>.getD [])
  let mut members : Array (ConflictMember MC) := #[]
  let mut side : Array (String × String × J × String) := #[]
  for c in claims do
    let path := c.s "path"
    let some s := x.sources.find? (ekosPath · == path)
      | throw s!"conflict {node.n}: claim path {path} names no imported source"
    let (a, r) ← s.pin structural
    members := members.push ⟨J.compact (c.getD "value"), ⟨s.key, [(a, r)]⟩⟩
    side := side.push (s.key, path, c.getD "line", c.s "source")
  pure (⟨tableKey subjectName, p.s "attribute", p.s "conflict_type", members.toList⟩, side.toList)

def conflictActions (x : Ctx) (node : Node) : BM Unit := do
  let (k, side) ← StateT.lift (conflictOf x node)
  let where_ := fun (src : String) =>
    match side.find? (·.1 == src) with
    | some (_, path, _, by_) => (path, by_)
    | none => ("", "")
  let D := conflictDocument where_ k
  let subjectName := node.p.s "subject_name"
  birth "ekos/conflict/v1"
  let header ← bid ["atom", "header"]
  let _ ← atomAct header (objKind "ekos/conflict-header/v1")
    (J.compact (.obj [("subject_key", .str D.header.subject), ("subject_name", .str subjectName),
      ("attribute", .str D.header.attr), ("conflict_type", .str D.header.conflictType),
      ("signature", .str D.header.signature), ("ekos_id", .str node.id), ("compiler", .str x.ekosVersion)]))
    (some (← bid ["run", "header"]))
  let structural := s!"create-table:{← StateT.lift (lowerAscii subjectName)}#0"
  for (m, (_, path, line, by_)) in D.members.zip side do
    let (s, a, r) ← StateT.lift (pinParts x.sources m.pin.source m.pin.atoms)
    let cont ← bid ["element", "claim", s.key]
    let metaA ← bid ["atom", "claim", s.key]
    let new ← atomAct metaA (objKind "ekos/claim/v1")
      (J.compact (.obj [("source_key", .str s.key), ("path", .str path), ("value", .raw m.value),
        ("line", line), ("claimed_by", .str by_)]))
    if new then emit (.obj [("type", .str "createContainer"), ("element", .str cont)])
    let (ev, landed) ← evidence "claim" s a r (evMeta s.key structural 1000 "conflicts::duplicate_definitions"
      "create-table" "claim path + subject table's structural key")
    if new then place cont [metaA, ev]
    else if landed then
      let b ← get
      let d ← curDoc
      emit (editElement b.root b.rootRev (.obj [("type", .str "remove"), ("child", .str ev)]))
      emit (editElement cont (d.elementRevision cont) (.obj [("type", .str "splice"), ("index", .str "1"), ("child", .str ev)]))
  let link ← bid ["link", "disputes"]
  let b ← get
  if b.born || !((b.cur.map (·.links.contains link)).getD false) then
    let subjectCell ← StateT.lift (tableCell (D.disputes.drop "sql-analyzer-table:".length).toString)
    emit (.obj [("type", .str "link"), ("link", .str link), ("source", .null),
                ("target", .obj [("type", .str "document"), ("id", .str (← StateT.lift (x.cellId subjectCell)))]),
                ("relation", .str (schemaId "relation/Disputes"))])

/-! ## The manifest -/

/-- The manifest's live links, read back from its current document. -/
def manifestOf (x : Ctx) (d : Option Doc) : Except String (Manifest MC) := do
  let some d := d | pure ⟨[]⟩
  let names : List (String × String) := match x.cells with
    | .obj kvs => kvs.filterMap fun (k, v) => v.str?.map (·, k)
    | _ => []
  let mut out : Array (ManifestLink MC) := #[]
  for (_, l) in d.links do
    let t := l.getD "target"
    if t.s "type" == "external" && t.s "scheme" == hexs "ekos-object" then
      let key ← unhexText (t.s "authority")
      let target ← unhexText (t.s "path")
      if let some (_, name) := names.find? (·.1 == target) then
        out := out.push ⟨[key], name, isLive l⟩
  pure ⟨out.toList⟩

def manifestActions (x : Ctx) (plan : List Row) : BM Unit := do
  birth "ekos/manifest/v1"
  for s in x.sources do
    let rev := s.doc.revision s.headerAtom
    let tag := ["input", s.key, s.headerAtom, rev]
    let tr ← bid ("transclusion" :: tag)
    addRead s.cell
    let b ← get
    if b.born || !((b.cur.map (·.transclusions.contains tr)).getD false) then
      emit (.obj [("type", .str "transclude"), ("transclusion", .str tr), ("link", .str (← bid ("link" :: tag))),
                  ("request", s.snapshot s.headerAtom (some s.headerRun))])
  let b ← get
  let current ← StateT.lift (manifestOf x (if b.born then none else b.cur))
  let emitted := (plan.filter (·.cell != "manifest")).map fun r => ([r.node.getD r.cell], r.cell)
  let after := manifestAfter current emitted
  for l in current.links do
    if l.live && !(after.current.contains (l.key, l.cell)) then
      throw s!"manifest: {l.cell} is no longer emitted; World.Manifest.compile unlinks it, and the unlink action's spelling has no receipt here"
  for l in after.links.drop current.links.length do
    let link ← bid ["link", "entry", l.cell]
    emit (.obj [("type", .str "link"), ("link", .str link), ("source", .null),
                ("target", .obj [("type", .str "external"), ("scheme", .str (hexs "ekos-object")),
                  ("authority", .str (hexs (l.key.headD ""))), ("path", .str (hexs (← StateT.lift (x.cellId l.cell))))]),
                ("relation", .str (schemaId "relation/manifest-entry"))])

end VerekosMap
