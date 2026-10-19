/-
# Check.Laws — `verekos-check laws <run-root>`: the model's laws on a run's log

Rebuilds a run's accepted writes as `World.Receipt`s and checks, on the real
log rather than on examples:

1. **The pin law** `World.AdmLog` (`World/Admission.lean:97`), decided by
   `Check.admLogB` (proved equal in `CheckProofs.Adm.admLogB_iff`).
2. **Pins nonempty** (`World.Claim.PinsNonempty`, the first half of
   `Claim.WellFormed`) for every claim the compiler puts (`pinsNonemptyB_iff`).
3. **Transaction order** `World.TxMonotone` (`World/TxOrder.lean:32`).
4. **Status** of every conflict claim in the final state, by
   `World.statusAt` (`World/Status.lean:71`) with the core taken as the
   conflict header's *revision* as read from the world, not a digest of the
   payload (design 3.1 §2, R1 finding S5: `status` itself cannot express
   that, `statusAt` with the revision supplied can). The status after every
   write is reported too, so a run shows `open → confirmed → needsReview`.

**The author is the signer.** A receipt's `author` is taken from the
`signer` of the command that wrote it (a subject in `principals.json`),
mapped to a principal kind by role, never from anything the payload says
(R1 finding S4). A payload that names a different author is reported under
`author_mismatch` and otherwise ignored.

**UNTRUSTED:** the reader of the run root (this file's JSON parsing, the role
table, the claim id derivation) has no theorem. What is checked is the
model's definitions on what this reader built.

## The run root

    <root>/principals.json   {"<role>": "<subject>", ...}   (slice 1's file)
    <root>/log.jsonl         one accepted write per line, in log order
    <root>/expect.json       optional: {"adm_log": bool, "pins_nonempty": bool,
                             "tx_monotone": bool,
                             "conflicts": [{"subject": [...], "status": "<name>",
                                            "timeline": [[tx, "<name>"], ...]}]}

A log line:

    {"tx": 3, "signer": "<subject>", "run": "c1", "stage": "compile",
     "op": "put",
     "claim": {"schema": "Conflict", "subject": ["..."], "sources": ["..."],
               "payload": <any JSON>,
               "pins": [{"source": "<doc>", "range": "<key>"|null, "atoms": ["<rev>"]},
                        {"claim_key": {"schema":…, "subject":[…], "sources":[…]},
                         "core": "<digest>"}, ...]},
     "header_rev": "<revision of the conflict header atom, as read>",
     "payload_author": "<what the payload claims>"}
    {"tx": 9, "signer": "...", "op": "retract", "claim_key": {...}}

Roles map to kinds: `compiler`, `importer` → compiler; `reviewer`, `owner`
→ human; `verifier`, `agent` → agent. Any other role, or a signer not in
`principals.json`, stops the run (exit 2): a write nobody can be held to is
not modelled.
-/
import Lean.Data.Json
import World.Status
import World.TxOrder
import Check.Adm

namespace Check.Laws

open Lean

def LC : World.Carriers where
  SchemaId := String
  SourceId := String
  Range := String
  Digest := String
  Time := String
  RunId := String
  Stage := String
  KeyPart := String
  AtomRev := String
  Name := String
  ClaimId := String
  decSchemaId := inferInstanceAs (DecidableEq String)
  decSourceId := inferInstanceAs (DecidableEq String)
  decRange := inferInstanceAs (DecidableEq String)
  decDigest := inferInstanceAs (DecidableEq String)
  decTime := inferInstanceAs (DecidableEq String)
  decKeyPart := inferInstanceAs (DecidableEq String)
  decAtomRev := inferInstanceAs (DecidableEq String)
  decName := inferInstanceAs (DecidableEq String)
  decClaimId := inferInstanceAs (DecidableEq String)

/-- A payload is its JSON text. -/
abbrev LP : LC.SchemaId → Type := fun _ => String

/-- A claim id is the JSON text of its key, which is injective on keys. -/
def keyText (k : World.ClaimKey LC) : String :=
  (Json.arr #[.str k.schema, .arr (k.subject.map Json.str).toArray,
    .arr (k.sources.map Json.str).toArray]).compress

def derive : World.ClaimIdDerivation LC := ⟨keyText⟩

def statusOfName : String → Option World.Status
  | "observed" => some .observed | "hypothesis" => some .hypothesis
  | "proposed" => some .proposed | "open" => some .open
  | "unconfirmed" => some .unconfirmed | "confirmed" => some .confirmed
  | "rejected" => some .rejected | "needsReview" => some .needsReview
  | "resolved" => some .resolved | "dismissed" => some .dismissed
  | _ => none

def statusName : World.Status → String
  | .observed => "observed" | .hypothesis => "hypothesis" | .proposed => "proposed"
  | .open => "open" | .unconfirmed => "unconfirmed" | .confirmed => "confirmed"
  | .rejected => "rejected" | .needsReview => "needsReview" | .resolved => "resolved"
  | .dismissed => "dismissed"

/-- The schemas a run uses. Conflicts open and are decided by humans only
(EKOS RFC 0172: `resolve` is human-only); every other schema is observed
and decided by humans. Reviews decide nothing about themselves. -/
def reg : World.Registry LC LP := fun s =>
  { core := fun _ => ""
    structural := s == "Review"
    initial := if s == "Conflict" then .open else .observed
    isFact := fun _ => true
    mayDecide := fun k _ => s != "Review" && k == .human
    stated := fun _ => [] }

/-- Review claims have schema `Review`; the decision is the payload's
`decision` field. -/
def review : World.ReviewSchema LC LP where
  sid := "Review"
  decision := fun (p : String) =>
    match Json.parse p with
    | .ok j => match j.getObjVal? "decision" with
      | .ok (.str s) => (statusOfName s).getD .observed
      | _ => .observed
    | .error _ => .observed

def kindOfRole : String → Option World.PrincipalKind
  | "compiler" | "importer" => some .compiler
  | "reviewer" | "owner" => some .human
  | "verifier" | "agent" => some .agent
  | _ => none

def kindOfName : String → Option World.PrincipalKind
  | "compiler" => some .compiler | "agent" => some .agent | "human" => some .human
  | _ => none

def kindText : World.PrincipalKind → String
  | .compiler => "compiler" | .agent => "agent" | .human => "human"

/-! ## Reading the run root (UNTRUSTED) -/

def getStr (j : Json) (k : String) : Except String String :=
  match j.getObjVal? k with
  | .ok (.str s) => .ok s
  | _ => .error s!"field {k} is not a string"

def getStrList (j : Json) (k : String) : Except String (List String) :=
  match j.getObjVal? k with
  | .ok (.arr a) => a.toList.mapM fun | .str s => .ok s | _ => .error s!"{k}: not strings"
  | .error _ => .ok []
  | _ => .error s!"{k}: not a list"

def keyOf (j : Json) : Except String (World.ClaimKey LC) := do
  pure ⟨← getStr j "schema", ← getStrList j "subject", ← getStrList j "sources"⟩

def pinOf (j : Json) : Except String (World.Pin LC) := do
  let weight := match j.getObjVal? "weight" with
    | .ok (.num n) => n.mantissa.toNat
    | _ => 1000
  match j.getObjVal? "source" with
  | .ok (.str doc) =>
    let range := match j.getObjVal? "range" with
      | .ok (.str r) => some r
      | _ => none
    pure ⟨.source doc range, .atoms (← getStrList j "atoms"), weight⟩
  | _ =>
    let target ← match j.getObjVal? "claim_key" with
      | .ok k => do pure (keyText (← keyOf k))
      | .error _ => getStr j "claim"
    pure ⟨.claim target, .core ((getStr j "core").toOption.getD ""), weight⟩

def claimOf (j : Json) : Except String (World.Claim LC LP) := do
  let key ← keyOf j
  let pins ← match j.getObjVal? "pins" with
    | .ok (.arr a) => a.toList.mapM pinOf
    | .error _ => pure []
    | _ => .error "pins: not a list"
  let payload := (j.getObjValD "payload").compress
  pure { key, payload, pins, valid := ⟨none, none⟩ }

/-- One log line, with what the model's receipt leaves out. -/
structure Line where
  receipt : World.Receipt LC LP
  signer : String
  headerRev : Option String
  payloadAuthor : Option String

/-- `authorFromPayload` is the planted mutant: when the payload names an
author kind, believe it. It exists to show that the signer rule changes the
answer on a run where a payload lies. -/
def lineOf (principals : List (String × String)) (authorFromPayload : Bool) (j : Json) :
    Except String Line := do
  let tx ← match j.getObjVal? "tx" with
    | .ok (.num n) => pure n.mantissa.toNat
    | _ => .error "tx is not a number"
  let signer ← getStr j "signer"
  let role ← match principals.find? (·.2 == signer) with
    | some (r, _) => pure r
    | none => .error s!"tx {tx}: signer {signer} is not in principals.json"
  let kind ← match kindOfRole role with
    | some k => pure k
    | none => .error s!"tx {tx}: role {role} may not write"
  let claimed := (getStr j "payload_author").toOption
  let kind := match authorFromPayload, claimed.bind kindOfName with
    | true, some k => k
    | _, _ => kind
  let op ← match (← getStr j "op") with
    | "put" => do pure (World.Op.put (← claimOf (j.getObjValD "claim")))
    | "retract" => do pure (World.Op.retract (keyText (← keyOf (j.getObjValD "claim_key"))))
    | o => .error s!"tx {tx}: op {o}"
  pure { receipt := { tx, op, author := (kind, signer),
                      run := (getStr j "run").toOption.getD "",
                      stage := (getStr j "stage").toOption.getD "" }
         signer
         headerRev := (getStr j "header_rev").toOption
         payloadAuthor := claimed }

/-! ## The report -/

def keyJson (k : World.ClaimKey LC) : Json :=
  Json.mkObj [("schema", .str k.schema), ("subject", .arr (k.subject.map Json.str).toArray),
    ("sources", .arr (k.sources.map Json.str).toArray)]

/-- The header revision last written for a conflict id, up to log prefix `n`. -/
def headerRevAt (lines : List Line) (id : String) : Option String :=
  (lines.filterMap fun l => match l.receipt.op with
    | .put c => if c.id derive == id then some l.headerRev else none
    | .retract _ => none).getLast?.join

def report (lines : List Line) (expect : Option Json) : Json × Bool := Id.run do
  let L := lines.map (·.receipt)
  let adm := admLogB derive L
  let firstBad : Option Nat := (List.range L.length).find? fun k =>
    match L[k]? with
    | some r => !admissibleL derive (L.take k) r
    | none => false
  let compiled := L.filterMap fun r => match r.op with
    | .put c => if r.author.1 == .compiler then some (r.tx, c) else none
    | .retract _ => none
  let unpinned := compiled.filter fun (_, c) => !pinsNonemptyB c
  let txMono := decide (World.TxMonotone L)
  let mismatches := lines.filter fun l => match l.payloadAuthor with
    | some a => a != kindText l.receipt.author.1
    | none => false
  -- conflicts in the final state, and their status after every write
  let final := World.latest derive L
  let conflictIds := (L.filterMap fun r => match r.op with
    | .put c => if c.key.schema == "Conflict" then some (c.id derive) else none
    | .retract _ => none).eraseDups
  let mut conflicts : Array Json := #[]
  let mut statusOk := true
  for id in conflictIds do
    let some c := final id | continue
    let mut timeline : Array Json := #[]
    let mut last : Option String := none
    for n in List.range (L.length + 1) do
      let pre := L.take n
      if (World.latest derive pre id).isNone then continue
      let some hr := headerRevAt (lines.take n) id | continue
      let s := statusName (World.statusAt review reg derive pre c.key hr)
      if last != some s then
        timeline := timeline.push (Json.arr #[.num (pre.getLast?.map (·.tx) |>.getD 0), .str s])
        last := some s
    let some hr := headerRevAt lines id | continue
    let s := statusName (World.statusAt review reg derive L c.key hr)
    let want : Option String := expect.bind fun e =>
      match e.getObjVal? "conflicts" with
      | .ok (.arr a) => a.toList.findSome? fun x =>
          match x.getObjVal? "subject", x.getObjVal? "status" with
          | .ok subj, .ok (.str st) =>
            if subj == Json.arr (c.key.subject.map Json.str).toArray then some st else none
          | _, _ => none
      | _ => none
    if let some w := want then
      if w != s then statusOk := false
    let wantTimeline : Option Json := expect.bind fun e =>
      match e.getObjVal? "conflicts" with
      | .ok (.arr a) => a.toList.findSome? fun x =>
          match x.getObjVal? "subject", x.getObjVal? "timeline" with
          | .ok subj, .ok tl =>
            if subj == Json.arr (c.key.subject.map Json.str).toArray then some tl else none
          | _, _ => none
      | _ => none
    if let some tl := wantTimeline then
      if tl != Json.arr timeline then statusOk := false
    conflicts := conflicts.push (Json.mkObj ([("key", keyJson c.key), ("header_rev", .str hr),
      ("status", .str s), ("timeline", .arr timeline)] ++
      (match want with | some w => [("expected", .str w)] | none => [])))
  let expBool (k : String) (got : Bool) : Bool :=
    match expect with
    | some e => match e.getObjVal? k with
      | Except.ok (Json.bool b) => b == got
      | _ => true
    | none => true
  let ok := statusOk && expBool "adm_log" adm && expBool "pins_nonempty" unpinned.isEmpty &&
    expBool "tx_monotone" txMono && (expect.isSome || (adm && unpinned.isEmpty && txMono))
  let j := Json.mkObj [
    ("receipts", .num L.length),
    ("adm_log", .bool adm),
    ("first_inadmissible_tx", match firstBad.bind (L[·]?) with
      | some r => .num r.tx | none => .null),
    ("compiled_puts", .num compiled.length),
    ("pins_nonempty", .bool unpinned.isEmpty),
    ("unpinned_compiled_tx", .arr (unpinned.map (fun (t, _) => Json.num t)).toArray),
    ("tx_monotone", .bool txMono),
    ("author_mismatch", .arr (mismatches.map fun l => Json.mkObj [
        ("tx", .num l.receipt.tx), ("signer", .str l.signer),
        ("signer_kind", .str (kindText l.receipt.author.1)),
        ("payload_says", .str (l.payloadAuthor.getD ""))]).toArray),
    ("conflicts", .arr conflicts),
    ("expectations_met", .bool ok)]
  return (j, ok)

def readJsonFile (p : System.FilePath) : IO Json := do
  match Json.parse (← IO.FS.readFile p) with
  | .ok j => pure j
  | .error e => throw (IO.userError s!"{p}: {e}")

def run (root : System.FilePath) (authorFromPayload : Bool := false) : IO UInt32 := do
  try
    let pj ← readJsonFile (root / "principals.json")
    let principals ← match pj with
      | .obj kvs => pure (kvs.toList.filterMap fun (k, v) => match v with
          | .str s => some (k, s) | _ => none)
      | _ => throw (IO.userError "principals.json is not an object")
    let text ← IO.FS.readFile (root / "log.jsonl")
    let mut lines : Array Line := #[]
    for raw in text.splitOn "\n" do
      if raw.trimAscii.isEmpty then continue
      let j ← match Json.parse raw with
        | .ok j => pure j
        | .error e => throw (IO.userError s!"log.jsonl: {e}")
      match lineOf principals authorFromPayload j with
      | .ok l => lines := lines.push l
      | .error e => throw (IO.userError s!"log.jsonl: {e}")
    let expect ← if ← (root / "expect.json").pathExists then
        some <$> readJsonFile (root / "expect.json") else pure none
    let (j, ok) := report lines.toList expect
    IO.println j.pretty
    return (if ok then 0 else 1 : UInt32)
  catch e =>
    IO.eprintln s!"verekos-check laws: {e}"
    return 2

end Check.Laws
