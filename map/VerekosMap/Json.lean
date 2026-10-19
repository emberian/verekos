/-
# VerekosMap.Json — a JSON value with key order, and Python's spellings of it

UNTRUSTED (a renderer and a parser). Nothing here is proved. It exists so the
Lean mapper writes the same bytes `slice1/mapper.py` and `slice1/laws.py`
wrote; the receipt that it does is byte-identity on the slice-1 run
(`notes/W24-lean-mapper.md`), not a theorem.

Three spellings, each Python's `json.dumps` with `ensure_ascii=False`:
- `compact`: `sort_keys=True, separators=(",", ":")` (`mapper.py canon`);
- `spaced`: `sort_keys=True` with the default separators `", "` and `": "`
  (`laws.py`);
- `indented`: `indent=1`, with or without `sort_keys` (`commands.json`,
  `plan`).

Parsing is Lean's own `Lean.Json.parse`; numbers are accepted only when they
are integers (the inputs hold no others).
-/
import Lean.Data.Json

namespace VerekosMap

/-- A JSON value whose objects keep the order they were built in. `raw` is a
value already spelled in the compact form (spliced verbatim). -/
inductive J where
  | null
  | bool (b : Bool)
  | num (n : Int)
  | str (s : String)
  | arr (xs : List J)
  | obj (kvs : List (String × J))
  | raw (s : String)
  deriving Inhabited

namespace J

/-- Field lookup (the last binding wins, as Python's `json.loads`). -/
def get? (j : J) (k : String) : Option J :=
  match j with
  | .obj kvs => (kvs.reverse.find? (·.1 == k)).map (·.2)
  | _ => none

def getD (j : J) (k : String) : J := (j.get? k).getD .null

def str? : J → Option String
  | .str s => some s
  | _ => none

def arr? : J → Option (List J)
  | .arr xs => some xs
  | _ => none

def num? : J → Option Int
  | .num n => some n
  | _ => none

def isNull : J → Bool
  | .null => true
  | _ => false

/-- Python's `json.dumps` string escape with `ensure_ascii=False`
(`json.encoder.ESCAPE`: `"`, `\`, and every character below U+0020). -/
def escape (s : String) : String := Id.run do
  let mut out := "\""
  for c in s.toList do
    let n := c.toNat
    if c == '"' then out := out ++ "\\\""
    else if c == '\\' then out := out ++ "\\\\"
    else if c == '\n' then out := out ++ "\\n"
    else if c == '\r' then out := out ++ "\\r"
    else if c == '\t' then out := out ++ "\\t"
    else if n == 8 then out := out ++ "\\b"
    else if n == 12 then out := out ++ "\\f"
    else if n < 0x20 then
      let h := "0123456789abcdef".toList
      out := out ++ "\\u00" ++ String.singleton h[n / 16]! ++ String.singleton h[n % 16]!
    else out := out.push c
  return out.push (Char.ofNat 34)

/-- Stable sort of object members by key (Python's `sort_keys`). -/
def sortKvs (kvs : List (String × J)) : List (String × J) :=
  kvs.mergeSort fun a b => decide (a.1 ≤ b.1)

/-- `json.dumps(x, sort_keys=sk, separators=(item, key), ensure_ascii=False)`. -/
partial def flat (sk : Bool) (item key : String) : J → String
  | .null => "null"
  | .bool b => if b then "true" else "false"
  | .num n => toString n
  | .str s => escape s
  | .raw s => s
  | .arr xs => "[" ++ item.intercalate (xs.map (flat sk item key)) ++ "]"
  | .obj kvs =>
    let kvs := if sk then sortKvs kvs else kvs
    "{" ++ item.intercalate (kvs.map fun (k, v) => escape k ++ key ++ flat sk item key v) ++ "}"

/-- `mapper.py canon`: sorted keys, `(",", ":")`. -/
def compact (j : J) : String := flat true "," ":" j

/-- `laws.py`: `json.dumps(x, sort_keys=True)`. -/
def spaced (j : J) : String := flat true ", " ": " j

/-- `json.dumps(x, indent=1, sort_keys=sk)`. -/
partial def indented (sk : Bool) (level : Nat := 0) : J → String
  | .arr [] => "[]"
  | .obj [] => "{}"
  | .arr xs =>
    let pad := "\n" ++ "".pushn ' ' (level + 1)
    "[" ++ pad ++ (",".append pad).intercalate (xs.map (indented sk (level + 1))) ++
      "\n" ++ "".pushn ' ' level ++ "]"
  | .obj kvs =>
    let kvs := if sk then sortKvs kvs else kvs
    let pad := "\n" ++ "".pushn ' ' (level + 1)
    "{" ++ pad ++ (",".append pad).intercalate
        (kvs.map fun (k, v) => escape k ++ ": " ++ indented sk (level + 1) v) ++
      "\n" ++ "".pushn ' ' level ++ "}"
  | j => flat sk ", " ": " j

/-- From Lean's parsed JSON. Objects come back in key order (Lean's map is
sorted), which every caller here either looks up or re-sorts. -/
partial def ofLean : Lean.Json → Except String J
  | .null => pure .null
  | .bool b => pure (.bool b)
  | .num n => if n.exponent == 0 then pure (.num n.mantissa) else throw s!"non-integer number {n}"
  | .str s => pure (.str s)
  | .arr xs => return .arr (← xs.toList.mapM ofLean)
  | .obj kvs => return .obj (← kvs.toList.mapM fun (k, v) => return (k, ← ofLean v))

def parse (s : String) : Except String J := do
  ofLean (← Lean.Json.parse s)

end J

end VerekosMap
