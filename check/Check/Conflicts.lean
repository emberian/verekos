/-
# Check.Conflicts — the `conflicts.unit` panel through `World.detectList`

What is trusted and what is not:

- **Model (trusted):** `World.detectList` (`World/Conflicts.lean:63`),
  computed by `Check.detectL`, which `CheckProofs.Detect.mem_detectL` proves
  has the same members. `World.mem_detect`, `coverage`, `soundness` and
  `detectList_perm` are about that function.
- **Mapper (UNTRUSTED, no theorem):** everything in this file. It reads the
  panel's EKOS objects and turns each into a claim, and gives the claims a
  registry whose `stated` is a port of EKOS's per-kind comparison
  (`ekos/crates/semantic/src/conflicts.rs` at `8e3c178`): `normalize_type`
  (:62), `facts` (:96), `normalize_expr` (:88) and `label_words` (:355). The
  ports use Lean's ASCII-only `Char.toLower`, `isUpper`, `isLower` and
  `isAlphanum` where Rust's are Unicode.
- **Compared on the join view (design §6):** the set of (subject key,
  attribute) pairs. EKOS's conflict ids, claims, `chosen`, signatures and the
  surviving objects are not compared; `tools/scoreboard/project_conflict_keys.py`
  projects EKOS's control to the same view.

How each item kind becomes claims:

- `duplicate_definitions`: one claim per object; schema = its kind, subject =
  its key, source = its path. EKOS compares objects that share an id, and its
  ids are a function of the key, so "same subject" is "same id".
- `merge_losses`: for each proposal with `exact_name_match`, the members
  present (other than the canonical one) and the canonical object, each a
  claim with the canonical key as subject and the canonical object's kind as
  schema. Proposals without an exact name match compare nothing (EKOS
  filters them out, conflicts.rs:333).
- `label_mismatches`: each `EnumMeaning` object is its own subject (EKOS runs
  the detector per object, conflicts.rs:386); one claim per meaning source,
  stating each of that source's labels as the attribute `label` with the
  label's word set as value. EKOS's rule is "two labels from disjoint source
  sets share no word"; the model's is "two sources state different values".
  They agree when word sets are equal or disjoint, and differ when they
  overlap; see `notes/B-check.md`.
- `normalize_type_pair`: two claims about one column, from two sources, with
  the two types; `same` is "no key detected".
-/
import Lean.Data.Json
import Check.Detect

namespace Check.Conflicts

open Lean

/-! ## Carriers and payloads -/

def CC : World.Carriers where
  SchemaId := String
  SourceId := String
  Range := Unit
  Digest := String
  Time := Unit
  RunId := Unit
  Stage := Unit
  KeyPart := String
  AtomRev := Unit
  Name := Unit
  ClaimId := String
  decSchemaId := inferInstanceAs (DecidableEq String)
  decSourceId := inferInstanceAs (DecidableEq String)
  decRange := inferInstanceAs (DecidableEq Unit)
  decDigest := inferInstanceAs (DecidableEq String)
  decTime := inferInstanceAs (DecidableEq Unit)
  decKeyPart := inferInstanceAs (DecidableEq String)
  decAtomRev := inferInstanceAs (DecidableEq Unit)
  decName := inferInstanceAs (DecidableEq Unit)
  decClaimId := inferInstanceAs (DecidableEq String)

/-- One column as EKOS's `facts` reads it (a column without a string `name`
is skipped there, and never built here). -/
structure Col where
  name : String
  dataType : Option String
  notNull : Option Bool
  primaryKey : Option Bool
  deriving DecidableEq, Repr

inductive Payload where
  /-- A table-like object: its columns and check expressions. -/
  | table (cols : List Col) (checks : List String)
  /-- The labels one source gave one enum value. -/
  | labels (ls : List String)
  deriving DecidableEq, Repr

abbrev CP : CC.SchemaId → Type := fun _ => Payload

instance (s : CC.SchemaId) : DecidableEq (CP s) := inferInstanceAs (DecidableEq Payload)

/-! ## EKOS's normalizations, ported (UNTRUSTED) -/

def lower (s : String) : String := s.map Char.toLower

def words (s : String) : List String :=
  (s.splitOn " ").filter (· ≠ "") |>.flatMap fun w =>
    ((w.split (fun c => c == '\t' || c == '\n' || c == '\r')).toList.map (·.toString)).filter (· ≠ "")

/-- `normalize_type` (conflicts.rs:62). -/
def normalizeType (t : String) : String :=
  let t := lower t.trimAscii.toString
  let t := " ".intercalate (words t)
  let (base, args) := match t.splitOn "(" with
    | [_] => (t, "")
    | b :: rest => ((b.trimAscii.toString), ("(" ++ "(".intercalate rest).replace " " "")
    | [] => (t, "")
  let base := match base with
    | "int" | "integer" | "int4" | "serial" | "serial4" => "int"
    | "bigint" | "int8" | "bigserial" | "serial8" => "bigint"
    | "smallint" | "int2" | "smallserial" | "serial2" => "smallint"
    | "bool" | "boolean" => "bool"
    | "varchar" | "character varying" => "varchar"
    | "char" | "character" | "bpchar" => "char"
    | "decimal" | "numeric" => "numeric"
    | "float8" | "double precision" | "double" => "double"
    | "float4" | "real" => "real"
    | "timestamp" | "timestamp without time zone" => "timestamp"
    | "timestamptz" | "timestamp with time zone" => "timestamptz"
    | "time" | "time without time zone" => "time"
    | "timetz" | "time with time zone" => "timetz"
    | other => other
  base ++ args

/-- `normalize_expr` (conflicts.rs:88). -/
def normalizeExpr (e : String) : String := lower (" ".intercalate (words e))

/-- A sorted, duplicate-free list, as a JSON array text (EKOS compares the
`BTreeSet`'s JSON). -/
def setText (xs : List String) : String :=
  let sorted := (xs.eraseDups.toArray.qsort (· < ·)).toList
  (Json.arr (sorted.map Json.str).toArray).compress

/-- Insert into an association list, replacing the key (a `BTreeMap`). -/
def put (m : List (String × String)) (k v : String) : List (String × String) :=
  (m.filter (·.1 ≠ k)) ++ [(k, v)]

def trimQuotes (s : String) : String :=
  let cs := s.toList.dropWhile (· == '"')
  String.ofList (cs.reverse.dropWhile (· == '"')).reverse

/-- `facts` (conflicts.rs:96): the comparable facts an object states. -/
def facts (cols : List Col) (checks : List String) : List (String × String) := Id.run do
  let mut out : List (String × String) := []
  let mut names : List String := []
  for c in cols do
    let n := lower (trimQuotes c.name)
    if let some t := c.dataType then
      out := put out s!"columns.{n}.data_type" (Json.str (normalizeType t)).compress
    if let some b := c.notNull then
      out := put out s!"columns.{n}.not_null" (toString b)
    if let some b := c.primaryKey then
      out := put out s!"columns.{n}.primary_key" (toString b)
    names := names ++ [n]
  if !names.isEmpty then out := put out "columns" (setText names)
  let exprs := checks.map normalizeExpr
  if !exprs.isEmpty then out := put out "check_constraints" (setText exprs)
  return out

/-- `label_words` (conflicts.rs:355): split camel case, lower-case, split on
anything not alphanumeric. -/
def labelWords (label : String) : List String := Id.run do
  let mut spaced : List Char := []
  let mut prevLower := false
  for ch in label.toList do
    if ch.isUpper && prevLower then spaced := spaced ++ [' ']
    prevLower := ch.isLower
    spaced := spaced ++ [ch]
  let low := lower (String.ofList spaced)
  return ((low.split (fun c => !c.isAlphanum)).toList.map (·.toString)).filter (· ≠ "")

/-- The registry: every schema states what `facts` or the label words say. -/
def reg : World.Registry CC CP := fun _ =>
  { core := fun _ => ""
    structural := false
    initial := .open
    isFact := fun _ => true
    mayDecide := fun k _ => k == .human
    stated := fun
      | .table cols checks => facts cols checks
      | .labels ls => ls.map fun l => ("label", setText (labelWords l)) }

/-! ## Panel objects → claims (UNTRUSTED) -/

def claim (schema : String) (subject : List String) (source : String) (p : Payload) :
    World.Claim CC CP :=
  { key := ⟨schema, subject, [source]⟩
    payload := p
    pins := [⟨.source source none, .atoms [], 1000⟩]
    valid := ⟨none, none⟩ }

def str? (j : Json) (k : String) : Option String :=
  match j.getObjVal? k with
  | .ok (.str s) => some s
  | _ => none

def bool? (j : Json) (k : String) : Option Bool :=
  match j.getObjVal? k with
  | .ok (.bool b) => some b
  | _ => none

def arr (j : Json) (k : String) : List Json :=
  match j.getObjVal? k with
  | .ok (.arr a) => a.toList
  | _ => []

/-- An object's kind as a schema id: the kind's JSON text (`"Table"`, or a
custom kind's name). -/
def kindOf (j : Json) : String :=
  match j.getObjVal? "kind" with
  | .ok (.str s) => s
  | .ok k => match k.getObjVal? "Custom" with
    | .ok (.str s) => s
    | _ => k.compress
  | .error _ => ""

def tableOf (o : Json) : Payload :=
  let cols := (arr o "columns").filterMap fun c =>
    (str? c "name").map fun n =>
      { name := n, dataType := str? c "data_type", notNull := bool? c "not_null",
        primaryKey := bool? c "primary_key" }
  let checks := (arr o "check_constraints").filterMap (str? · "expression")
  .table cols checks

structure Obj where
  key : String
  kind : String
  path : String
  payload : Payload

def objOf (o : Json) : Obj :=
  { key := (str? o "key").getD "", kind := kindOf o, path := (str? o "path").getD "",
    payload := tableOf o }

def dupClaims (objs : List Obj) : List (World.Claim CC CP) :=
  objs.map fun o => claim o.kind [o.key] o.path o.payload

def mergeClaims (objs : List Obj) (proposals : List Json) : List (World.Claim CC CP) :=
  -- EKOS's `by_id` is a map: a later object with the same key replaces an earlier one
  let byKey (k : String) : Option Obj := (objs.filter (·.key == k)).getLast?
  proposals.flatMap fun p =>
    if bool? p "exact_name_match" != some true then [] else
    let canonKey := (str? p "canonical_key").getD ""
    match byKey canonKey with
    | none => []
    | some canon =>
      let members := ((arr p "source_keys").filterMap fun k =>
        match k with | .str s => some s | _ => none).filter (· != canonKey) |>.filterMap byKey
      if members.isEmpty then [] else
      (members ++ [canon]).map fun m => claim canon.kind [canonKey] m.path m.payload

def labelClaims (enums : List Json) : List (World.Claim CC CP) :=
  (enums.zipIdx).flatMap fun (e, i) =>
    if kindOf e != "EnumMeaning" then [] else
    let key := (str? e "key").getD ""
    let meanings := match e.getObjVal? "properties" with
      | .ok props => arr props "meanings"
      | .error _ => []
    let pairs := meanings.filterMap fun m =>
      match str? m "label" with
      | some l =>
        let l := l.trimAscii.toString
        if l.isEmpty then none else some ((str? m "source").getD "", l)
      | none => none
    let sources := (pairs.map (·.1)).eraseDups
    sources.map fun s =>
      claim "EnumMeaning" [key, toString i] s
        (.labels ((pairs.filter (·.1 == s)).map (·.2)))

/-! ## One item → one candidate line -/

/-- The join view of a key list: sorted, duplicate-free [subject key,
attribute] pairs. The subject's first part is the EKOS key. -/
def keysJson (ks : List (String × List String × String)) : Json :=
  let pairs := (ks.map fun (_, subj, a) => (subj.headD "", a)).eraseDups
  let sorted := (pairs.toArray.qsort fun x y => x.1 < y.1 || (x.1 == y.1 && x.2 < y.2)).toList
  Json.arr (sorted.map fun (s, a) => Json.arr #[.str s, .str a]).toArray

def sameSet (a b : List (String × List String × String)) : Bool :=
  a.all (· ∈ b) && b.all (· ∈ a)

def answer (kind : String) (input : Json) : List (String × Json) :=
  let detect := detectL reg
  match kind with
  | "normalize_type_pair" =>
    let col (t : String) : Payload :=
      .table [{ name := "c", dataType := some t, notNull := none, primaryKey := none }] []
    let a := (str? input "a").getD ""
    let b := (str? input "b").getD ""
    let ks := detect [claim "Table" ["t"] "a" (col a), claim "Table" ["t"] "b" (col b)]
    [("same", .bool ks.isEmpty)]
  | "duplicate_definitions" =>
    let cs := dupClaims ((arr input "objects").map objOf)
    let ks := detect cs
    let base := [("keys", keysJson ks)]
    if bool? input "also_reversed" == some true then
      base ++ [("permuted_stable", .bool (sameSet ks (detect cs.reverse)))]
    else base
  | "merge_losses" =>
    [("keys", keysJson (detect (mergeClaims ((arr input "objects").map objOf)
      (arr input "proposals"))))]
  | "label_mismatches" =>
    [("keys", keysJson (detect (labelClaims (arr input "enums"))))]
  | other => [("error", .str s!"unknown kind {other}")]

end Check.Conflicts
