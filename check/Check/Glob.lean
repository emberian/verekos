/-
# Check.Glob — the `glob` crate's pattern, ported (UNTRUSTED, not proved)

A port of `glob` 0.3.4 (`Pattern::new`, `Pattern::matches_with`, lib.rs
lines 612-1060), the pattern library EKOS's read scope uses
(`ekos/crates/ledger/src/scope.rs`, `Compiled::new`). Only the options EKOS
uses are ported: case sensitive, `require_literal_separator = true`,
`require_literal_leading_dot = false`, and `/` as the only separator (a Unix
build of EKOS).

Design §4 says the matcher "stays per kind": it is code the runner trusts
without a theorem. Every difference it causes on a panel is a VerEKOS defect
of this port, not of the model.
-/

namespace Check.Glob

inductive CharSpec where
  | single (c : Char)
  | range (lo hi : Char)
  deriving Repr, BEq

inductive Tok where
  | char (c : Char)
  | anyChar
  | anySeq
  | anyRecSeq
  | within (cs : List CharSpec)
  | except (cs : List CharSpec)
  deriving Repr, BEq, Inhabited

def isSep (c : Char) : Bool := c == '/'

/-- `parse_char_specifiers`: `a-z` is a range, anything else a single char. -/
partial def charSpecs : List Char → List CharSpec
  | a :: '-' :: b :: rest => .range a b :: charSpecs rest
  | a :: rest => .single a :: charSpecs rest
  | [] => []

/-- `in_char_specifiers`, case sensitive. -/
def inSpecs (cs : List CharSpec) (c : Char) : Bool :=
  cs.any fun
    | .single s => c == s
    | .range lo hi => lo ≤ c && c ≤ hi

/-- The index of the first `]` at or after `start`, as an offset from `start`. -/
def findClose (a : Array Char) (start : Nat) : Option Nat := Id.run do
  let mut j := start
  while j < a.size do
    if a[j]! == ']' then return some (j - start)
    j := j + 1
  return none

/-- `Pattern::new`. `none` is a `PatternError`. -/
def compile (pattern : String) : Option (List Tok) := Id.run do
  let chars := pattern.toList.toArray
  let n := chars.size
  let mut toks : Array Tok := #[]
  let mut i := 0
  let mut fuel := n + 1
  while i < n && fuel > 0 do
    fuel := fuel - 1
    let c := chars[i]!
    if c == '?' then
      toks := toks.push .anyChar
      i := i + 1
    else if c == '*' then
      let old := i
      while i < n && chars[i]! == '*' do
        i := i + 1
      let count := i - old
      if count > 2 then
        return none
      else if count == 2 then
        if i == 2 || isSep chars[i - count - 1]! then
          if i < n && isSep chars[i]! then
            i := i + 1
          else if i == n then
            pure ()
          else
            return none
        else
          return none
        -- collapse consecutive recursive sequences (the crate's own test is
        -- `tokens_len > 1`, kept as written)
        let len := toks.size
        if !(len > 1 && toks[len - 1]! == Tok.anyRecSeq) then
          toks := toks.push .anyRecSeq
      else
        toks := toks.push .anySeq
    else if c == '[' then
      let mut done := false
      if i + 4 ≤ n && chars[i + 1]! == '!' then
        match findClose chars (i + 3) with
        | some j =>
          toks := toks.push (.except (charSpecs (chars.extract (i + 2) (i + 3 + j)).toList))
          i := i + j + 4
          done := true
        | none => pure ()
      else if i + 3 ≤ n && chars[i + 1]! != '!' then
        match findClose chars (i + 2) with
        | some j =>
          toks := toks.push (.within (charSpecs (chars.extract (i + 1) (i + 2 + j)).toList))
          i := i + j + 3
          done := true
        | none => pure ()
      if !done then return none
    else
      toks := toks.push (.char c)
      i := i + 1
  return some toks.toList

inductive Res where
  | ok | sub | entire
  deriving BEq, Repr, Inhabited

mutual
/-- `Pattern::matches_from`, with the three-valued result of the crate. -/
partial def matchFrom (fs : Bool) (file : List Char) : List Tok → Res
  | [] => if file.isEmpty then .ok else .sub
  | t :: rest =>
    match t with
    | .anySeq | .anyRecSeq =>
      match matchFrom fs file rest with
      | .sub => seqLoop t rest fs file
      | m => m
    | _ =>
      match file with
      | [] => .entire
      | c :: file' =>
        let sep := isSep c
        let ok := match t with
          | .anyChar => !sep
          | .within cs => !sep && inSpecs cs c
          | .except cs => !sep && !inSpecs cs c
          | .char c2 => c == c2
          | _ => false
        if !ok then .sub else matchFrom sep file' rest

/-- The crate's `while let Some(c) = file.next()` loop for a `*` or `**`
token `t`: try every split point; when the input runs out, carry on with the
remaining tokens on the empty input. -/
partial def seqLoop (t : Tok) (rest : List Tok) (fs : Bool) : List Char → Res
  | [] => matchFrom fs [] rest
  | c :: file' =>
    let fs' := isSep c
    match t with
    | .anyRecSeq =>
      if !fs' then seqLoop t rest fs' file'
      else match matchFrom fs' file' rest with
        | .sub => seqLoop t rest fs' file'
        | m => m
    | _ =>
      if fs' then .sub
      else match matchFrom fs' file' rest with
        | .sub => seqLoop t rest fs' file'
        | m => m
end

/-- `Pattern::matches_with` under EKOS's `MATCH` options. -/
def globMatches (toks : List Tok) (s : String) : Bool :=
  matchFrom true s.toList toks == .ok

end Check.Glob
