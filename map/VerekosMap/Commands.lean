/-
# VerekosMap.Commands — the subcommands of `verekos-map`

UNTRUSTED (file handling and rendering). Each command reads the inputs
the twin read, builds the World values (`VerekosMap.Model`), renders them
(`VerekosMap.Render`), and writes the files the twin wrote, with the same
stdout line.
-/
import VerekosMap.Render

namespace VerekosMap

open World

/-- the twin's argument parser: `--k v` pairs; `source` and `current` repeat. -/
def parseArgs (argv : List String) : Except String (List (String × String)) := do
  let rec go : List String → Except String (List (String × String))
    | [] => pure []
    | k :: v :: rest => return (String.ofList (k.toList.dropWhile (· == '-')), v) :: (← go rest)
    | [k] => throw s!"{k}: missing value"
  go argv

def arg (a : List (String × String)) (k : String) : IO String :=
  match (a.reverse.find? (·.1 == k)) with
  | some (_, v) => pure v
  | none => throw (IO.userError s!"missing --{k}")

def arg? (a : List (String × String)) (k : String) : Option String := (a.reverse.find? (·.1 == k)).map (·.2)

def args (a : List (String × String)) (k : String) : List String := (a.filter (·.1 == k)).map (·.2)

def splitEq (spec : String) : String × String :=
  match spec.splitOn "=" with
  | k :: rest => (k, "=".intercalate rest)
  | [] => ("", "")

def loadSources (a : List (String × String)) : IO (List Source) :=
  (args a "source").mapM fun spec => do
    let (k, path) := splitEq spec
    liftM (Source.ofDoc k (← Doc.load path))

def writeText (path : System.FilePath) (s : String) : IO Unit := do
  if let some d := path.parent then IO.FS.createDirAll d
  IO.FS.writeFile path s

def runB (cell : String) (cur : Option Doc) (m : BM Unit) : IO B := do
  liftM ((m.run (B.new cell cur)).map (·.2))

def pad2 (i : Nat) : String := if i < 10 then s!"0{i}" else toString i

/-! ## compile and plan -/

def cmdPlan (a : List (String × String)) : IO Unit := do
  let (nodes, _) ← loadExport (← arg a "export")
  let plan ← liftM (buildPlan nodes (← loadSources a))
  IO.println (J.indented false 0 (.arr (plan.map Row.toJ)))

def statementsJ (s : Source) : J := Id.run do
  let mut m : OMap J := []
  for (k, aid) in s.order do m := m.insert k (.arr [.str aid, .str (s.doc.revision aid)])
  return .obj m

def cmdCompile (a : List (String × String)) : IO Unit := do
  let (nodes, edges) ← loadExport (← arg a "export")
  let sources ← loadSources a
  let cells ← readJsonFile (← arg a "cells")
  let mut current : OMap Doc := []
  for spec in args a "current" do
    let (name, path) := splitEq spec
    current := current.insert name (← Doc.load path)
  let x : Ctx := ⟨sources, cells, (arg? a "ekos-version").getD "unknown"⟩
  let plan ← liftM (buildPlan nodes sources)
  let missing := plan.filter fun r => (cells.get? r.cell).isNone
  if !missing.isEmpty then
    throw (IO.userError s!"cells not born yet: {missing.map (·.cell)} (run `plan` and have the owner create them)")
  let out : System.FilePath := ← arg a "out"
  IO.FS.createDirAll out
  let mut all := ""
  let mut listing : Array J := #[]
  for (row, i) in plan.zipIdx do
    let node := nodes.find? fun n => some n.id == row.node
    let m : BM Unit := match row.schema, node with
      | "ekos/object/v1", some n => do
        let (c, es) ← StateT.lift (tableClaims x n edges)
        tableActions x (← StateT.lift (objectDocument c es))
      | "ekos/conflict/v1", some n => conflictActions x n
      | _, _ => manifestActions x plan
    let b ← runB row.cell (current.get? row.cell) m
    if b.acts.isEmpty then continue
    let name := s!"{pad2 i}-{row.cell}.json"
    let data := requestBytes (invokeJ row.cell b.acts.toList b.reads)
    IO.FS.writeFile (out / name) data
    all := all ++ data
    let count := fun (ty : String) => (b.acts.filter (·.s "type" == ty)).size
    listing := listing.push (.obj [("file", .str name), ("cell", .str row.cell), ("actions", .num b.acts.size),
      ("reads", .arr ((dedupSorted b.reads).map .str)), ("transclusions", .num (count "transclude")),
      ("births", .num (count "createDocument"))])
  let digest := sha256Hex all
  IO.FS.writeFile (out / "commands.sha256") (digest ++ "\n")
  let mut inputs : OMap J := []
  for s in sources do
    inputs := inputs.insert s.key (.obj [("cell", .str s.cell), ("header", .str s.headerAtom),
      ("header_revision", .str (s.doc.revision s.headerAtom)), ("statements", statementsJ s)])
  IO.FS.writeFile (out / "commands.json")
    (J.indented true 0 (.obj [("sha256", .str digest), ("requests", .arr listing.toList), ("inputs", .obj inputs)]) ++ "\n")
  IO.println s!"{listing.size} request(s), sha256 {digest}"

/-! ## render and split -/

def cmdRender (a : List (String × String)) : IO Unit := do
  let src ← liftM (Source.ofDoc (← arg a "key") (← Doc.load (← arg a "read")))
  let out ← arg a "out"
  writeText out (← liftM src.text)
  IO.println s!"{src.key}: {src.order.length} statement atom(s) -> {out}"

/-- Python `repr` of an ASCII string (`split`'s diagnostic column). -/
def pyRepr (s : String) : String :=
  let q := if s.contains '\'' && !s.contains '"' then '"' else '\''
  let body := s.toList.foldl (fun acc c =>
    if c == q || c == '\\' then (acc.push '\\').push c
    else if c == '\n' then acc ++ "\\n" else if c == '\r' then acc ++ "\\r" else if c == '\t' then acc ++ "\\t"
    else if c.toNat < 0x20 || c.toNat == 0x7f then
      let h := "0123456789abcdef".toList
      acc ++ "\\x" ++ String.singleton h[c.toNat / 16]! ++ String.singleton h[c.toNat % 16]!
    else acc.push c) ""
  (String.singleton q ++ body).push q

def cmdSplit (file : String) : IO Unit := do
  for (k, t) in ← liftM (splitStatements (← IO.FS.readFile file)) do
    let line := ((splitLinesKeep t).headD "").toList
    let first := match line.reverse with
      | '\n' :: '\r' :: r => r.reverse
      | c :: r => if pyLineBreak c then r.reverse else line
      | [] => []
    IO.println s!"{k}\t{t.utf8ByteSize}\t{pyRepr (String.ofList (first.take 60))}"

/-! ## import -/

def MAPPER_REDACTION : String :=
  "not run: the Redact kernel is not built and ekos_common::redaction has no CLI entry; fixtures carry no secrets"

/-- The source header as the model holds it. The empty `pipeline` digest is
written `null` (the deployed header has no pipeline version). -/
def sourceHeaderJ (cell : String) (h : SourceHeader) : J :=
  .obj [("cell", .str cell), ("source_key", .str (h.sourceKey.headD "")), ("path", .str h.path),
        ("importer", .str h.importer), ("redaction", .str h.redactionTable),
        ("pipeline_logic_version", if h.pipeline.isEmpty then .null else .str h.pipeline)]

def cmdImport (a : List (String × String)) : IO Unit := do
  let data ← IO.FS.readFile (← arg a "file")
  let key ← arg a "source-key"
  let path ← arg a "path"
  let cell ← arg a "cell"
  let (root, headerId, headerRun, stmtRun) := idsForSource key path
  let atomOf := fun (k : List String) => num ["atom", key, path, k.headD ""]
  let stmts ← liftM (splitStatements data)
  let statements : List (Statement) := stmts.map fun (k, t) => ⟨[k], t⟩
  let h : SourceHeader := ⟨[key], path, MAPPER_REDACTION, MAPPER_VERSION, ""⟩
  let doc ← match arg? a "read" with
    | some p => some <$> Doc.load p
    | none => pure none
  let mut acts : Array J := #[]
  match doc.filter (·.document.isSome) with
  | none =>
    let D := importedSource atomOf h statements
    acts := acts.push (.obj [("type", .str "createDocument"), ("rootElement", .str root), ("schema", .str (schemaId "ekos/source/v1"))])
    acts := acts.push (.obj [("type", .str "createAtom"), ("atom", .str headerId), ("kind", objKind "ekos/source-header/v1"),
      ("payload", .str (hexs (J.compact (sourceHeaderJ cell D.header))))])
    for t in D.atoms do
      acts := acts.push (.obj [("type", .str "createAtom"), ("atom", .str t.id), ("kind", textKind), ("payload", .str (hexs t.bytes))])
    acts := acts.push (.obj [("type", .str "createRun"), ("run", .str headerRun), ("atoms", .arr [.str headerId])])
    acts := acts.push (.obj [("type", .str "createRun"), ("run", .str stmtRun), ("atoms", .arr (D.atoms.map (.str ·.id)))])
  | some d =>
    -- the current document as the model's SourceDoc: live atoms of the statement run, in run order
    let present := match d.runs.get? stmtRun with
      | some r => runAtoms r
      | none => []
    let live := present.filter fun x => (d.atoms.get? x).map isLive |>.getD true
    let wantIds := statements.map fun s => atomOf s.key
    if (wantIds.filter live.contains) != (live.filter wantIds.contains) then
      throw (IO.userError "import: statements were reordered; editElement .move is not implemented in slice 1")
    let mut cur : Array (TextAtom String) := #[]
    for x in live do
      let k ← liftM (keyOfAtom key path d x)
      cur := cur.push ⟨x, [k], (d.revision x).toNat!, ← liftM (d.payload x)⟩
    let D : SourceDoc String := ⟨h, cur.toList⟩
    let r := cur.foldl (fun m t => max m t.rev) 0 + 1
    let N := reimportedSource atomOf D statements r
    -- A statement the current document lacks is NOT written as `createAtom` + `insertRun`
    -- (the twin's spelling): the deployed client refuses `insertRun` ("unknown workspace content
    -- action", minidregg native/resource-client/src/content_privacy.rs:83; lane A,
    -- notes/A-reader-local.md). It is folded into the preceding live statement atom with one
    -- `editAtom` (lane A's shape), or into the following one when it comes first. The model's
    -- SourceDoc still has one atom per statement; the deployed document then does not.
    let mut hosts : Array (String × String) := #[]   -- (atom id, new payload text), first-touch order
    let mut pending := ""                             -- new statements before any live atom
    let mut host : Option String := none
    let setHost := fun (hs : Array (String × String)) (id txt : String) =>
      if hs.any (·.1 == id) then hs.map fun (i, x) => if i == id then (i, txt) else (i, x) else hs.push (id, txt)
    let hostText := fun (hs : Array (String × String)) (id : String) (dflt : String) =>
      ((hs.find? (·.1 == id)).map (·.2)).getD dflt
    for t in N.atoms do
      match D.atoms.find? (·.key == t.key) with
      | some old =>
        let base := if old.rev != t.rev then t.bytes else old.bytes
        if old.rev != t.rev || !pending.isEmpty then
          hosts := setHost hosts t.id (pending ++ base)
        pending := ""
        host := some t.id
      | none =>
        if d.atoms.contains t.id then
          throw (IO.userError s!"import: {t.key.headD ""} returns under a tombstoned id; not handled in slice 1")
        match host with
        | none => pending := pending ++ t.bytes
        | some h =>
          if (h.length > 0) && ((D.atoms.find? (·.id == h)).map (·.key.headD "") |>.getD "").startsWith "anon:" then
            throw (IO.userError s!"import: {t.key.headD ""} would be folded into an anonymous atom, whose id is derived from its whole text; not handled")
          let hostCur := hostText hosts h ((D.atoms.find? (·.id == h)).map (·.bytes) |>.getD "")
          hosts := setHost hosts h (hostCur ++ t.bytes)
    if !pending.isEmpty then
      throw (IO.userError "import: new statements with no live statement atom to fold them into; not handled")
    for (id, txt) in hosts do
      acts := acts.push (.obj [("type", .str "editAtom"), ("atom", .str id), ("before", d.before id), ("kind", textKind),
        ("payload", .str (hexs txt)), ("tombstone", .bool false)])
    for old in D.atoms do
      if !(N.atoms.any (·.key == old.key)) then
        acts := acts.push (.obj [("type", .str "editAtom"), ("atom", .str old.id), ("before", d.before old.id), ("kind", textKind),
          ("payload", .str (d.payloadHex old.id)), ("tombstone", .bool true)])
  if acts.isEmpty then
    IO.println "nothing to submit"
    return
  IO.FS.writeFile (← arg a "out") (requestBytes (invokeJ cell acts.toList []))
  IO.println s!"{acts.size} action(s): {", ".intercalate (dedupSorted (acts.toList.map (·.s "type")))}"

/-! ## runrec, attest, review -/

def cmdRunrec (a : List (String × String)) : IO Unit := do
  let sources ← loadSources a
  let dir : System.FilePath := ← arg a "dir"
  let metaJ ← readJsonFile (dir / "commands.json")
  let cur ← match arg? a "read" with
    | some p => some <$> Doc.load p
    | none => pure none
  let mapperFile ← match arg? a "mapper-file" with
    | some p => pure p
    | none => do pure (← IO.appPath).toString
  let mapperSha ← match arg? a "mapper-sha256" with
    | some h => pure h
    | none => do pure (hexBytes (sha256 (← IO.FS.readBinFile mapperFile)))
  let cell ← arg a "cell"
  let k := metaJ.s "sha256"
  let outputs := ((metaJ.get? "requests").bind J.arr? |>.getD []).map (·.s "cell")
  let run : CompileRunDoc :=
    { compiler := "compiler"
      inputs := sources.map fun s => ⟨⟨s.key, [(s.headerAtom, s.doc.revision s.headerAtom)]⟩, 0⟩
      identity := ⟨(arg? a "ekos-version").getD "unknown", MAPPER_VERSION, "", ""⟩
      outputs := outputs.map (·, "")
      command := k }
  let m : BM Unit := do
    birth "ekos/compile-run/v1"
    let cont ← bid ["element", "run", run.command]
    let rec_ ← bid ["atom", "run", run.command]
    let rrun ← bid ["run", "run", run.command]
    emit (.obj [("type", .str "createContainer"), ("element", .str cont)])
    emit (.obj [("type", .str "createAtom"), ("atom", .str rec_), ("kind", objKind "ekos/compile-run/v1"),
      ("payload", .str (hexs (J.compact (.obj [("commands_sha256", .str run.command), ("mapper", .str run.identity.logicVersion),
        ("mapper_sha256", .str mapperSha), ("ekos", .str run.identity.commit), ("inputs", metaJ.getD "inputs"),
        ("outputs", .arr (run.outputs.map (.str ·.1)))]))))])
    emit (.obj [("type", .str "createRun"), ("run", .str rrun), ("atoms", .arr [.str rec_])])
    let mut kids := #[rec_]
    for i in run.inputs do
      let (s, a, _) ← StateT.lift (pinParts sources i.pin.source i.pin.atoms)
      let tr ← bid ["transclusion", "input", run.command, s.key]
      addRead s.cell
      emit (.obj [("type", .str "transclude"), ("transclusion", .str tr),
        ("link", .str (← bid ["link", "input", run.command, s.key])), ("request", s.snapshot a (some s.headerRun))])
      kids := kids.push tr
    place cont kids.toList
  let b ← runB cell cur m
  IO.FS.writeFile (← arg a "out") (requestBytes (invokeJ cell b.acts.toList b.reads))
  IO.println s!"compile-run record {num ["atom", cell, "run", k]} for {k}"

def cmdAttest (a : List (String × String)) : IO Unit := do
  let runDoc ← Doc.load (← arg a "compile-run")
  let want ← arg a "claimed"
  let replayed ← arg a "replayed"
  let cell ← arg a "cell"
  let sourceCell ← arg a "source-cell"
  let mut found : Option J := none
  for (_, x) in runDoc.atoms do
    if kindIs x "ekos/compile-run/v1" then
      let r ← liftM (J.parse (← liftM (unhexText (x.s "payload"))))
      if r.s "commands_sha256" == want then found := some x; break
  let some rec_ := found | throw (IO.userError s!"no compile-run record with commands_sha256 {want}")
  let run : CompileRunDoc := { compiler := "compiler", inputs := [], identity := ⟨"", "", "", ""⟩, outputs := [], command := want }
  let att : ReplayAttestation := ⟨(arg? a "replayer").getD "verifier", [], replayed⟩
  let label := attestationLabel run att
  let same := run.command == att.command
  let rrun := num ["run", sourceCell, "run", want]
  let cur ← match arg? a "read" with
    | some p => some <$> Doc.load p
    | none => pure none
  let m : BM Unit := do
    birth "ekos/replay-attestation/v1"
    let cont ← bid ["element", "attest", want]
    let atom ← bid ["atom", "attest", want]
    let tr ← bid ["transclusion", "attest", want]
    let link ← bid ["link", "attest", want]
    emit (.obj [("type", .str "createContainer"), ("element", .str cont)])
    emit (.obj [("type", .str "createAtom"), ("atom", .str atom), ("kind", objKind "ekos/replay-attestation/v1"),
      ("payload", .str (hexs (J.compact (.obj [("claimed_commands_sha256", .str run.command),
        ("replayed_commands_sha256", .str att.command), ("match", .bool same),
        ("liveness", .str (if label then "replayedDeterministic" else "reconstructedApproximate")),
        ("replayer", .str att.verifier)]))))])
    emit (.obj [("type", .str "transclude"), ("transclusion", .str tr), ("link", .str link),
      ("request", snapshotJ runDoc.target rrun (rec_.s "id") (rec_.s "revision"))])
    place cont [atom, tr]
  let b ← runB cell cur m
  IO.FS.writeFile (← arg a "out") (requestBytes (invokeJ cell b.acts.toList [sourceCell]))
  IO.println s!"attestation: match={if same then "True" else "False"}"

def cmdReview (a : List (String × String)) : IO Unit := do
  let cf ← Doc.load (← arg a "conflict")
  let cname ← arg a "conflict-cell"
  let cell ← arg a "cell"
  let verb := (arg? a "verb").getD "resolve"
  let some status := verbStatus verb | throw (IO.userError s!"review verb {verb}: not one of resolve, confirm, reject, dismiss")
  let header := num ["atom", cname, "header"]
  let hrun := num ["run", cname, "header"]
  let rev := cf.revision header
  let entry : ReviewEntry := ⟨⟨status, "", (arg? a "note").getD ""⟩, cf.target, (header, rev)⟩
  let D := (⟨cname, []⟩ : ReviewDoc).append entry
  let cur ← match arg? a "read" with
    | some p => some <$> Doc.load p
    | none => pure none
  let pick ← arg a "pick"
  let m : BM Unit := do
    birth "ekos/review/v1"
    for dc in D.decisions do
      let (ha, hr) ← match dc.pin.atoms with
        | [x] => pure x
        | _ => throw "a decision pins exactly one header atom"
      let tag := ["decision", cname, ha, hr]
      let cont ← bid ("element" :: tag)
      let atom ← bid ("atom" :: tag)
      let tr ← bid ("transclusion" :: tag)
      let link ← bid ("link" :: tag)
      emit (.obj [("type", .str "createContainer"), ("element", .str cont)])
      emit (.obj [("type", .str "createAtom"), ("atom", .str atom), ("kind", objKind "ekos/decision/v1"),
        ("payload", .str (hexs (J.compact (.obj [("verb", .str (statusVerb dc.decision.verb)), ("pick", .str pick),
          ("note", .str dc.decision.note), ("conflict_cell", .str D.reviewed)]))))])
      emit (.obj [("type", .str "transclude"), ("transclusion", .str tr), ("link", .str link),
        ("request", snapshotJ dc.pin.source hrun ha hr)])
      place cont [atom, tr]
  let b ← runB cell cur m
  IO.FS.writeFile (← arg a "out") (requestBytes (invokeJ cell b.acts.toList [cname]))
  IO.println s!"decision {num ["atom", cell, "decision", cname, header, rev]} on {cname} header at revision {rev}"

end VerekosMap

namespace VerekosMap

/-! ## Library commands for reader/ (JSON on stdout) -/

/-- `source --key K --read R`: a source document as the mapper reads it: key, cell, path, target, the
header atom and runs, and its live statement atoms in run order with structural keys and revisions.
Exit 1 when the read is not a source document. -/
def cmdSource (a : List (String × String)) : IO Unit := do
  let d ← Doc.load (← arg a "read")
  let key ← match arg? a "key" with
    | some k => pure k
    | none => do pure ((← liftM (sourceHeader d)).s "source_key")
  let s ← liftM (Source.ofDoc key d)
  IO.println (J.compact (.obj [("key", .str s.key), ("cell", .str s.cell), ("path", .str s.path), ("target", .str d.target),
    ("header_atom", .str s.headerAtom), ("header_revision", .str (d.revision s.headerAtom)), ("header_run", .str s.headerRun),
    ("stmt_run", .str s.stmtRun),
    ("statements", .arr (s.order.map fun (k, aid) => .obj [("key", .str k), ("atom", .str aid), ("revision", .str (d.revision aid))]))]))

/-- `structural-key TEXT`: the structural key of one statement text (no occurrence suffix). -/
def cmdStructuralKey (text : String) : IO Unit := do
  IO.println (← liftM (structuralKey text))

/-- `table-cell NAME`: the compiled cell a table lives in (`obj-<safe name>`). -/
def cmdTableCell (name : String) : IO Unit := do
  IO.println (← liftM (tableCell name))

/-- `edit-atom --read R --source-key K --structural S --cell C --file F --out REQ`: one `editAtom`
that replaces the payload of the statement atom named by its structural key with F's bytes (lane
A's scene tool, `reader/remote/edit-atom.py`, which this replaces). -/
def cmdEditAtom (a : List (String × String)) : IO Unit := do
  let d ← Doc.load (← arg a "read")
  let s ← liftM (Source.ofDoc (← arg a "source-key") d)
  let structural ← arg a "structural"
  let (aid, _) ← liftM (s.pin structural)
  let text ← IO.FS.readFile (← arg a "file")
  let cell ← arg a "cell"
  let act : J := .obj [("type", .str "editAtom"), ("atom", .str aid), ("before", d.before aid), ("kind", textKind),
    ("payload", .str (hexs text)), ("tombstone", .bool false)]
  IO.FS.writeFile (← arg a "out") (requestBytes (invokeJ cell [act] []))
  IO.println s!"1 action(s): editAtom (atom {String.ofList (aid.toList.take 12)}…, {structural}, {text.utf8ByteSize} bytes)"

end VerekosMap
