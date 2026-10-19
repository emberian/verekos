/-
# VerekosMap.Split — statements of a SQL file, and their structural keys

UNTRUSTED (a recognizer). This is the twin's `split` and `structural_key`,
ported line for line so that the atoms, and therefore the atom ids, are the
same. Python's string semantics are reproduced where they matter here:
`str.splitlines(keepends=True)`, `str.strip()` / `str.split()` (Unicode
whitespace), and the `CREATE` regex. Where Python's regex would compare a
non-ASCII character case-insensitively or as a word character (`\w`, and
`re.I` folds such as U+212A KELVIN SIGN to `k`), this file refuses with an
error instead of guessing: the slice-1 fixtures are ASCII.
-/
import VerekosMap.Bytes

namespace VerekosMap

/-- `str.isspace` for one character (Python 3: bidi class WS/B/S or category Zs). -/
def pyIsSpace (c : Char) : Bool :=
  let n := c.toNat
  (9 ≤ n ∧ n ≤ 13) || (0x1c ≤ n ∧ n ≤ 0x20) || n == 0x85 || n == 0xa0 || n == 0x1680 ||
    (0x2000 ≤ n ∧ n ≤ 0x200a) || n == 0x2028 || n == 0x2029 || n == 0x202f || n == 0x205f ||
    n == 0x3000

/-- A line boundary for `str.splitlines` (`\r\n` is handled by the caller). -/
def pyLineBreak (c : Char) : Bool :=
  let n := c.toNat
  n == 10 || n == 13 || n == 11 || n == 12 || n == 0x1c || n == 0x1d || n == 0x1e ||
    n == 0x85 || n == 0x2028 || n == 0x2029

/-- `s.splitlines(keepends=True)`. -/
def splitLinesKeep (s : String) : List String := Id.run do
  let cs := s.toList.toArray
  let mut out : Array String := #[]
  let mut cur := ""
  let mut i := 0
  while i < cs.size do
    let c := cs[i]!
    cur := cur.push c
    if pyLineBreak c then
      if c == '\r' && i + 1 < cs.size && cs[i + 1]! == '\n' then
        cur := cur.push '\n'
        i := i + 1
      out := out.push cur
      cur := ""
    i := i + 1
  if cur != "" then out := out.push cur
  return out.toList

/-- `s.strip()`. -/
def pyStrip (s : String) : String :=
  String.ofList ((s.toList.dropWhile pyIsSpace).reverse.dropWhile pyIsSpace).reverse

/-- `" ".join(s.split())`. -/
def pyNormSpace (s : String) : String := Id.run do
  let mut words : Array String := #[]
  let mut cur := ""
  for c in s.toList do
    if pyIsSpace c then
      if cur != "" then words := words.push cur; cur := ""
    else cur := cur.push c
  if cur != "" then words := words.push cur
  return " ".intercalate words.toList

/-! ## The CREATE regex

`^\s*create\s+(?:or\s+replace\s+)?(?:unique\s+)?(table|index|view|materialized\s+view|function|procedure|trigger)\s+(?:if\s+not\s+exists\s+)?([\w."]+)`
with `re.I`, tried in the order Python's backtracking tries it: each optional
group first present, then absent; the alternatives left to right. -/

abbrev M := Except String

def asciiLower (c : Char) : Char := if 'A' ≤ c ∧ c ≤ 'Z' then Char.ofNat (c.toNat + 32) else c

/-- `\s*`. -/
def ws0 (cs : List Char) : List Char := cs.dropWhile pyIsSpace

/-- `\s+`. -/
def ws1 (cs : List Char) : Option (List Char) :=
  match cs with
  | c :: _ => if pyIsSpace c then some (ws0 cs) else none
  | [] => none

/-- A keyword, case-insensitively. A non-ASCII character where a letter is
expected is refused (Python's `re.I` folds some of them to ASCII). -/
def kw (w : String) (cs : List Char) : M (Option (List Char)) := do
  let mut rest := cs
  for k in w.toList do
    match rest with
    | c :: r =>
      if c.toNat > 127 then throw s!"non-ASCII character U+{c.toNat} where `{w}` is matched"
      if asciiLower c != k then return none
      rest := r
    | [] => return none
  return some rest

/-- A keyword followed by `\s+`. -/
def kwWs (w : String) (cs : List Char) : M (Option (List Char)) := do
  match ← kw w cs with
  | some r => pure (ws1 r)
  | none => pure none

def kinds : List (String × List String) :=
  [("table", ["table"]), ("index", ["index"]), ("view", ["view"]),
   ("materialized-view", ["materialized", "view"]), ("function", ["function"]),
   ("procedure", ["procedure"]), ("trigger", ["trigger"])]

/-- A kind's words separated by `\s+`. -/
def kindWords : List String → List Char → M (Option (List Char))
  | [], cs => pure (some cs)
  | [w], cs => kw w cs
  | w :: ws, cs => do
    match ← kwWs w cs with
    | some r => kindWords ws r
    | none => pure none

/-- `[\w."]+`, greedy. -/
def nameRun (cs : List Char) : M String := do
  let mut out := ""
  for c in cs do
    if c.toNat > 127 then throw s!"non-ASCII character U+{c.toNat} in a statement name"
    if c.isAlphanum || c == '_' || c == '.' || c == '"' then out := out.push c else break
  return out

/-- Optional group: try with it, then without. -/
def opt (g : List Char → M (Option (List Char))) (k : List Char → M (Option α))
    (cs : List Char) : M (Option α) := do
  if let some r ← g cs then
    if let some x ← k r then return some x
  k cs

def orReplace (cs : List Char) : M (Option (List Char)) := do
  match ← kwWs "or" cs with
  | some r => kwWs "replace" r
  | none => pure none

def ifNotExists (cs : List Char) : M (Option (List Char)) := do
  match ← kwWs "if" cs with
  | some r => match ← kwWs "not" r with
    | some r => kwWs "exists" r
    | none => pure none
  | none => pure none

/-- The regex's (kind, name), or `none` when it does not match. -/
def createMatch (text : String) : M (Option (String × String)) := do
  let some s ← kwWs "create" (ws0 text.toList) | return none
  opt orReplace (opt (kwWs "unique") fun s => do
      for (kind, words) in kinds do
        if let some r ← kindWords words s then
          if let some r := ws1 r then
            let found ← opt ifNotExists (fun r => do
              let n ← nameRun r
              pure (if n.isEmpty then none else some n)) r
            if let some n := found then return some (kind, n)
      return none) s

/-- the twin's `structural_key`. -/
def structuralKey (text : String) : M String := do
  match ← createMatch text with
  | some (kind, name) =>
    let name := String.ofList ((name.toList.dropWhile (· == '"')).reverse.dropWhile (· == '"')).reverse
    pure s!"create-{kind}:{String.ofList (name.toList.map asciiLower)}"
  | none => pure ("anon:" ++ (sha256Hex (pyNormSpace text)).take 16)

/-- the twin's `split`: statement atoms whose concatenation is the file, with
keys `<structural key>#<occurrence>`. -/
def splitStatements (data : String) : M (List (String × String)) := do
  let mut chunks : Array String := #[]
  let mut cur : Array String := #[]
  let mut state := "gap"
  let mut gapHasText := false
  for line in splitLinesKeep data do
    let s := pyStrip line
    if state == "stmt" then
      cur := cur.push line
      if s.endsWith ";" then state := "tail"
      continue
    if state == "tail" then
      if s == "" then
        cur := cur.push line
        continue
      chunks := chunks.push (String.join cur.toList); cur := #[]; state := "gap"; gapHasText := false
    if s == "" || s.startsWith "--" then
      cur := cur.push line
      gapHasText := gapHasText || s.startsWith "--"
      continue
    if !cur.isEmpty then
      if gapHasText || chunks.isEmpty then
        chunks := chunks.push (String.join cur.toList)
      else
        chunks := chunks.set! (chunks.size - 1) (chunks[chunks.size - 1]! ++ String.join cur.toList)
      cur := #[]
    cur := cur.push line
    state := if s.endsWith ";" then "tail" else "stmt"
  if !cur.isEmpty then chunks := chunks.push (String.join cur.toList)
  if String.join chunks.toList != data then throw "split lost bytes"
  let mut seen : List (String × Nat) := []
  let mut out : Array (String × String) := #[]
  for text in chunks do
    let key ← structuralKey text
    let occ := ((seen.find? (·.1 == key)).map (·.2)).getD 0
    seen := (key, occ + 1) :: seen.filter (·.1 != key)
    out := out.push (s!"{key}#{occ}", text)
  return out.toList

end VerekosMap
