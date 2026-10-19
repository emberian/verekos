/-
# Check.Scope — the `scope.decision` panel through `World.visible`

What is trusted and what is not:

- **Model (trusted, proved about):** `World.visible` (`World/Visible.lean:66`)
  at depth 1. Its theorems (`deny_wins_id`, `deny_wins_origin`,
  `unpinned_hidden`, `visible_pins`) are about exactly the function called
  here.
- **Mapper (UNTRUSTED, no theorem):** everything else in this file. It parses
  an EKOS `ReadScope` JSON text, compiles path patterns with the `glob` port
  (`Check.Glob`), and turns the scope into a `World.Scope` (the four
  predicates) and an item into a claim. The predicates are given EKOS's own
  rules from `ekos/crates/ledger/src/scope.rs` at the pin `8e3c178`:
  `denies` (:211) for `deniesOrigin`, `allows` (:224) for
  `allowsOrigin`, object rules for `deniesId`/`allowsId`, and the scope's
  `default` folded into `allowsOrigin` (a default-allow scope allows every
  origin). An object's `(source, path)` origins become source pins
  (`source` → the pin's document, `path` → its range); its id becomes the
  claim id; no claim pins, so depth 1 is exact.
- **Parser (UNTRUSTED):** the `{"error":"parse"}` and `{"error":"rule"}`
  answers come from this file's reading of serde's derived deserializer and
  `Compiled::new`, not from EKOS. Known gaps: duplicate JSON keys (serde
  refuses them; Lean's JSON reader keeps the last), and Lean's JSON grammar
  where it differs from serde_json's.
- `unrestricted` and `origins` items are answered by the mapper alone (they
  are properties of the parsed scope and of EKOS's `origins()`), not by
  `World.visible`.
-/
import Lean.Data.Json
import WorldCore
import Check.Glob

namespace Check.Scope

open Lean

/-! ## Carriers: what the scope panel needs from `World.Carriers` -/

/-- Source ids are `Option String` (an origin may have no source); a range is
a path; a claim id is the object's UUID text, lower-case and hyphenated. -/
scoped instance SC : World.Carriers where
  SchemaId := Unit
  SourceId := Option String
  Range := String
  Digest := Unit
  Time := Unit
  RunId := Unit
  Stage := Unit
  KeyPart := String
  AtomRev := Unit
  Name := Unit
  ClaimId := String
  decSchemaId := inferInstanceAs (DecidableEq Unit)
  decSourceId := inferInstanceAs (DecidableEq (Option String))
  decRange := inferInstanceAs (DecidableEq String)
  decDigest := inferInstanceAs (DecidableEq Unit)
  decTime := inferInstanceAs (DecidableEq Unit)
  decKeyPart := inferInstanceAs (DecidableEq String)
  decAtomRev := inferInstanceAs (DecidableEq Unit)
  decName := inferInstanceAs (DecidableEq Unit)
  decClaimId := inferInstanceAs (DecidableEq String)

/-- No payload: visibility never reads it. -/
abbrev SP : SC.SchemaId → Type := fun _ => Unit

/-- The claim id is the key's single subject part (the object's id). -/
scoped instance derive : World.ClaimIdDerivation := ⟨fun k => k.subject.headD ""⟩

/-! ## The ReadScope, as EKOS's serde derive reads it (UNTRUSTED) -/

inductive Effect where
  | allow | deny
  deriving DecidableEq, Repr

structure Rule where
  effect : Effect
  source : Option String
  path : Option String
  object : Option String
  deriving Repr

structure ReadScope where
  default : Effect
  rules : List Rule
  deriving Repr

/-- What went wrong: `parse` is `ScopeError::Parse`, `rule` is
`ScopeError::Rule`. -/
inductive Err where
  | parse | rule
  deriving DecidableEq, Repr

def Err.text : Err → String
  | .parse => "parse"
  | .rule => "rule"

def isHex (c : Char) : Bool := c.isDigit || ('a' ≤ c && c ≤ 'f') || ('A' ≤ c && c ≤ 'F')

/-- A UUID in any form the `uuid` crate's `parse_str` accepts (simple,
hyphenated, braced, urn), as lower-case hyphenated text. -/
def parseUuid (s : String) : Option String :=
  let s := if s.startsWith "urn:uuid:" then (s.drop 9).toString else s
  let s := if s.startsWith "{" && s.endsWith "}" then ((s.drop 1).dropEnd 1).toString else s
  let cs := s.toList
  let hex : Option (List Char) :=
    if cs.length == 32 && cs.all isHex then some cs
    else if cs.length == 36 && cs.all (fun c => isHex c || c == '-') &&
        [8, 13, 18, 23].all (fun i => cs[i]! == '-') &&
        (cs.filter (· == '-')).length == 4 then some (cs.filter (· != '-'))
    else none
  hex.map fun h =>
    let h := String.ofList (h.map Char.toLower)
    let p (a b : Nat) := ((h.drop a).take (b - a)).toString
    s!"{p 0 8}-{p 8 12}-{p 12 16}-{p 16 20}-{p 20 32}"

def keysOf (kvs : Std.TreeMap.Raw String Json compare) : List String :=
  kvs.toList.map (·.1)

def effectOf : Json → Except Err Effect
  | .str "allow" => .ok .allow
  | .str "deny" => .ok .deny
  | _ => .error .parse

/-- `Option<String>`: absent or `null` is `None`. -/
def optStr (o : Json) (k : String) : Except Err (Option String) :=
  match o.getObjVal? k with
  | .error _ => .ok none
  | .ok .null => .ok none
  | .ok (.str s) => .ok (some s)
  | .ok _ => .error .parse

def ruleOf (j : Json) : Except Err Rule := do
  let .obj kvs := j | .error .parse
  unless (keysOf kvs).all (· ∈ ["effect", "source", "path", "object"]) do .error .parse
  let effect ← match j.getObjVal? "effect" with
    | .ok e => effectOf e
    | .error _ => .error .parse
  let source ← optStr j "source"
  let path ← optStr j "path"
  let object ← optStr j "object"
  let object ← match object with
    | none => pure none
    | some s => match parseUuid s with
      | some u => pure (some u)
      | none => .error .parse
  pure { effect, source, path, object }

/-- Does any JSON object in `text` name the same key twice? serde's derived
`Deserialize` refuses a repeated field ("duplicate field"), which
`ReadScope::from_json` reports as `ScopeError::Parse`; Lean's `Json.parse`
keeps the last value instead, so the runner scans the raw text first. Keys
are compared after JSON unescaping, as serde compares them. (EKOS's other
entry point, `ReadScope::from_value`, receives an already-parsed
`serde_json::Value`, whose map has already kept the last value, so there a
duplicate is not refused; the panel exercises `from_json`.) -/
partial def hasDuplicateKey (text : String) : Bool :=
  let cs := text.toList.toArray
  -- stack: `some keys` for an open object, `none` for an open array
  let rec go (i : Nat) (stack : List (Option (List String))) : Bool :=
    if h : i < cs.size then
      let c := cs[i]
      if c == '"' then
        -- find the closing quote, honouring backslash escapes
        let rec close (j : Nat) : Nat :=
          if h : j < cs.size then
            if cs[j] == '\\' then close (j + 2)
            else if cs[j] == '"' then j else close (j + 1)
          else j
        let e := close (i + 1)
        let rec skipWs (k : Nat) : Nat :=
          if h : k < cs.size then
            if cs[k] == ' ' || cs[k] == '\n' || cs[k] == '\t' || cs[k] == '\r' then skipWs (k + 1)
            else k
          else k
        let k := skipWs (e + 1)
        let isKey := k < cs.size && cs[k]! == ':'
        match stack, isKey with
        | some keys :: rest, true =>
          let raw := String.ofList (cs.extract i (e + 1)).toList
          let key := match Json.parse raw with
            | .ok (.str s) => s
            | _ => raw
          if key ∈ keys then true else go (e + 1) (some (key :: keys) :: rest)
        | _, _ => go (e + 1) stack
      else if c == '{' then go (i + 1) (some [] :: stack)
      else if c == '[' then go (i + 1) (none :: stack)
      else if c == '}' || c == ']' then go (i + 1) stack.tail
      else go (i + 1) stack
    else false
  go 0 []

/-- `ReadScope::from_json` up to the shape check (`ScopeError::Parse`). -/
def parseScope (text : String) : Except Err ReadScope := do
  if hasDuplicateKey text then .error .parse
  let j ← match Json.parse text with
    | .ok j => pure j
    | .error _ => .error .parse
  let .obj kvs := j | .error .parse
  unless (keysOf kvs).all (· ∈ ["default", "rules"]) do .error .parse
  let default ← match j.getObjVal? "default" with
    | .ok e => effectOf e
    | .error _ => .error .parse
  let rules ← match j.getObjVal? "rules" with
    | .error _ => pure []
    | .ok (.arr a) => a.toList.mapM ruleOf
    | .ok _ => .error .parse
  pure { default, rules }

/-- `normalize` (scope.rs:147): forward slashes, no leading `./`. -/
def normalizePath (p : String) : String :=
  let p := p.replace "\\" "/"
  if p.startsWith "./" then (p.drop 2).toString else p

structure CRule where
  effect : Effect
  source : Option String
  path : Option (List Glob.Tok)
  object : Option String

structure Compiled where
  default : Effect
  rules : List CRule

/-- `Compiled::new` (scope.rs:153): `ScopeError::Rule` cases. -/
def compileScope (s : ReadScope) : Except Err Compiled := do
  let rules ← s.rules.mapM fun r => do
    if r.object.isSome && (r.source.isSome || r.path.isSome) then .error .rule
    if r.source == some "" || r.path == some "" then .error .rule
    let path ← match r.path with
      | none => pure none
      | some p => match Glob.compile (normalizePath p) with
        | some t => pure (some t)
        | none => .error .rule
    pure { effect := r.effect, source := r.source, path, object := r.object : CRule }
  pure { default := s.default, rules }

def readScope (text : String) : Except Err Compiled := parseScope text >>= compileScope

/-! ## EKOS's per-origin rules (scope.rs:195-235), ported -/

structure Origin where
  source : Option String
  path : Option String
  deriving DecidableEq, Repr

/-- `path_matches` (scope.rs:195): the path as recorded, or with its
source in front removed. -/
def pathMatches (pat : List Glob.Tok) (source : Option String) (path : String) : Bool :=
  Glob.globMatches pat path ||
  match source with
  | some s =>
    if path.startsWith s then
      let rest := (path.drop s.length).toString
      rest.startsWith "/" && Glob.globMatches pat (rest.drop 1).toString
    else false
  | none => false

/-- `Compiled::denies`: an unknown source or path counts as covered. -/
def ruleDenies (r : CRule) (o : Origin) : Bool :=
  let srcOk := match r.source, o.source with
    | some w, some a => w == a
    | _, _ => true
  srcOk && match r.path, o.path with
    | none, _ => true
    | some _, none => true
    | some pat, some p => pathMatches pat o.source p

/-- `Compiled::allows`: a rule with a source does not match "no source", one
with a path does not match "no path". -/
def ruleAllows (r : CRule) (o : Origin) : Bool :=
  let srcOk := match r.source with
    | some s => o.source == some s
    | none => true
  srcOk && match r.path, o.path with
    | none, _ => true
    | some _, none => false
    | some pat, some p => pathMatches pat o.source p

/-! ## The mapping into `World.Scope` (UNTRUSTED) -/

/-- Which mapping to run. `denyIgnored` is the planted mutant: both deny
predicates are constantly false. It exists to show the score moves. -/
inductive Mode where
  | faithful | denyIgnored
  deriving DecidableEq

def toWorld (mode : Mode) (c : Compiled) : World.Scope where
  allowsId i := c.rules.any fun r => r.effect == .allow && r.object == some i
  deniesId i := mode == .faithful &&
    c.rules.any fun r => r.effect == .deny && r.object == some i
  allowsOrigin s p := c.default == .allow ||
    c.rules.any fun r => r.effect == .allow && r.object.isNone && ruleAllows r ⟨s, p⟩
  deniesOrigin s p := mode == .faithful &&
    c.rules.any fun r => r.effect == .deny && r.object.isNone && ruleDenies r ⟨s, p⟩

/-- An object as a claim: its id is the key's subject; one source pin per
origin. -/
def toClaim (id : String) (origins : List Origin) : World.Claim SP where
  key := ⟨(), [id], []⟩
  payload := ()
  pins := origins.map fun o => ⟨.source o.source o.path, .atoms [], 1000⟩
  valid := ⟨none, none⟩

/-- The decision: `World.visible` at depth 1 with an empty state (no claim
pins exist, so nothing is looked up). -/
def decide (mode : Mode) (c : Compiled) (id : String) (origins : List Origin) : Bool :=
  World.visible (fun _ => none) (toWorld mode c) 1 (toClaim id origins)

/-- `origins()` (scope.rs:290): sources crossed with normalized paths. -/
def crossOrigins (sources paths : List String) : List Origin :=
  let ss : List (Option String) := if sources.isEmpty then [none] else sources.map some
  let ps : List (Option String) :=
    if paths.isEmpty then [none] else paths.map (some ∘ normalizePath)
  ss.flatMap fun s => ps.map fun p => ⟨s, p⟩

/-- `ReadScope::is_unrestricted`. -/
def unrestricted (c : Compiled) : Bool :=
  c.default == .allow && c.rules.all (·.effect == .allow)

/-! ## One panel item → one candidate line -/

def DEFAULT_ID : String := "00000000-0000-5000-8000-000000000000"

def strList (j : Json) (k : String) : Except String (List String) :=
  match j.getObjVal? k with
  | .error _ | .ok .null => .ok []
  | .ok (.arr a) => a.toList.mapM fun
      | .str s => .ok s
      | _ => .error s!"{k} must be a list of strings"
  | .ok _ => .error s!"{k} must be a list of strings"

def optField (o : Json) (k : String) : Except String (Option String) :=
  match o.getObjVal? k with
  | .error _ | .ok .null => .ok none
  | .ok (.str s) => .ok (some s)
  | .ok _ => .error s!"origin.{k} is not a string or null"

def originsOf (input : Json) : Except String (List Origin) :=
  match input.getObjVal? "origins" with
  | .ok (.arr a) => a.toList.mapM fun o => do
      pure ⟨← optField o "source", ← optField o "path"⟩
  | _ => do pure (crossOrigins (← strList input "sources") (← strList input "paths"))

def originJson (o : Origin) : Json :=
  Json.mkObj [("source", match o.source with | some s => .str s | none => .null),
              ("path", match o.path with | some s => .str s | none => .null)]

/-- The answer fields for one item (without `item`). -/
def answer (mode : Mode) (kind : String) (input : Json) : List (String × Json) :=
  let err (e : String) := [("error", Json.str e)]
  let scopeText := match input.getObjVal? "scope" with
    | .ok (.str s) => some s
    | _ => none
  match kind with
  | "parse" =>
    match scopeText with
    | none => err "input.scope is not a string"
    | some t => match readScope t with
      | .ok _ => [("parsed", .bool true)]
      | .error e => err e.text
  | "unrestricted" =>
    match scopeText with
    | none => err "input.scope is not a string"
    | some t => match readScope t with
      | .ok c => [("unrestricted", .bool (unrestricted c))]
      | .error e => err e.text
  | "origins" =>
    match (do pure (crossOrigins (← strList input "sources") (← strList input "paths"))) with
    | .ok os => [("origins", Json.arr (os.map originJson).toArray)]
    | .error e => err e
  | "visible" =>
    match scopeText with
    | none => err "input.scope is not a string"
    | some t =>
      let id : Option String := match input.getObjVal? "id" with
        | .ok (.str s) => parseUuid s
        | _ => some DEFAULT_ID
      match id, originsOf input with
      | none, _ => err "id is not a UUID"
      | _, .error e => err e
      | some id, .ok os => match readScope t with
        | .error e => err e.text
        | .ok c => [("visible", .bool (decide mode c id os))]
  | other => err s!"unknown kind {other}"

end Check.Scope
