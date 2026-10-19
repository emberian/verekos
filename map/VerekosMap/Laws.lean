/-
# VerekosMap.Laws — the four document laws as minidregg `Pred` values

The laws are values of minidregg's own predicate type
(`Minidregg.Pred.Pred`, `Pred/Core.lean`), the AST the kernel evaluates: not
a copy of it. Principals are parameters; with the placeholders
(91001 importer, 91002 owner, 91003 compiler, 91004 reviewer) they are the
laws `laws/L-*.json` states, and with real subjects they are the laws
the Python laws script installed on hbox.

The JSON renderer is UNTRUSTED. It spells each constructor the way the
client serializer does (`native/resource-client/src/shell/law.rs:211-430`,
notes/W4-pred-laws.md): `all`/`any` with `predicates`, `not` with
`predicate`, `eq`/`le` with `slot` and a string `value`, `memberOf` with
`slot` and string `values`. A constructor the slice-1 laws do not use is
refused rather than spelled from memory.
-/
import Pred.Core
import VerekosMap.Json

namespace VerekosMap

open Minidregg.Pred

/-- Verb codes, as the shell templates test them: observe 1, mutate 2,
delegate 3, installPolicy 4, revoke 5. -/
def verbSlot : Slot := "request/verb"
def subjectSlot : Slot := "request/subject"

/-- The principals a law names. -/
structure Principals where
  importer : Int := 91001
  owner : Int := 91002
  compiler : Int := 91003
  reviewer : Int := 91004

/-- `L-src`: read, delegate, revoke for anyone; installPolicy for the owner;
mutate for the importer. -/
def lSrc (w : Principals) : Pred :=
  .any [.memberOf verbSlot [1, 3, 5],
        .all [.eq verbSlot 4, .memberOf subjectSlot [w.owner]],
        .all [.eq verbSlot 2, .memberOf subjectSlot [w.importer]]]

/-- `L-obj`: as `L-src`, but mutate is the compiler's, writes no annotations
or marks, and a document birth must carry a transclusion. -/
def lObj (w : Principals) : Pred :=
  .any [.memberOf verbSlot [1, 3, 5],
        .all [.eq verbSlot 4, .memberOf subjectSlot [w.owner]],
        .all [.eq verbSlot 2, .memberOf subjectSlot [w.compiler],
              .eq "content/annotations" 0, .eq "content/marks" 0,
              .any [.eq "content/document-creates" 0, .not (.le "content/transclusions" 0)]]]

/-- An append-only law for one writer: no atom edits, no tombstones. -/
def appendOnly (writer : Int) : Pred :=
  .any [.memberOf verbSlot [1, 3, 4, 5],
        .all [.eq verbSlot 2, .memberOf subjectSlot [writer],
              .eq "content/atom-edits" 0, .eq "content/tombstones" 0]]

/-- `L-rev`: the review cell, appended to by the reviewer only. -/
def lRev (w : Principals) : Pred := appendOnly w.reviewer

/-- `L-run`: the compile-run cell, appended to by the compiler only (and the
attestation cell, with the verifier in the compiler's place). -/
def lRun (w : Principals) : Pred := appendOnly w.compiler

/-- The client JSON of a predicate, keys in the order `type`, then fields. -/
partial def predJ : Pred → Except String J
  | .eq s v => pure (.obj [("type", .str "eq"), ("slot", .str s), ("value", .str (toString v))])
  | .le s v => pure (.obj [("type", .str "le"), ("slot", .str s), ("value", .str (toString v))])
  | .memberOf s vs => pure (.obj [("type", .str "memberOf"), ("slot", .str s), ("values", .arr (vs.map (.str ∘ toString)))])
  | .not p => return .obj [("type", .str "not"), ("predicate", ← predJ p)]
  | .allL ps => return .obj [("type", .str "all"), ("predicates", .arr (← ps.toList.mapM predJ))]
  | .anyL ps => return .obj [("type", .str "any"), ("predicates", .arr (← ps.toList.mapM predJ))]
  | _ => throw "a Pred constructor the slice-1 laws do not use; its client spelling is not on record here"

/-- A leaf: an object none of whose values is an object or an array of objects. -/
def isLeaf : J → Bool
  | .obj kvs => kvs.all fun (_, v) => match v with
    | .obj _ => false
    | .arr xs => xs.all fun x => match x with | .obj _ => false | _ => true
    | _ => true
  | _ => false

/-- The hand layout of `laws/L-*.json`: two-space indent, keys in build order,
arrays of strings on one line, and a leaf predicate on one line when it is an
element of a `predicates` list nested at least two lists deep. (This rule was
fitted to the four files; the receipt is that it reproduces them.) -/
partial def pretty (level : Nat) (depth : Nat) (j : J) (elem : Bool := false) : String :=
  let ind := fun (n : Nat) => "".pushn ' ' (2 * n)
  match j with
  | .obj kvs =>
    if elem && depth ≥ 2 && isLeaf j then J.flat false ", " ": " j
    else
      "{\n" ++ ",\n".intercalate (kvs.map fun (k, v) =>
        ind (level + 1) ++ J.escape k ++ ": " ++ (match v with
          | .arr xs =>
            if xs.all (fun x => match x with | .obj _ => false | _ => true) then J.flat false ", " ": " v
            else "[\n" ++ ",\n".intercalate (xs.map fun x => ind (level + 2) ++ pretty (level + 2) (depth + 1) x true) ++
              "\n" ++ ind (level + 1) ++ "]"
          | .obj _ => pretty (level + 1) depth v
          | _ => J.flat false ", " ": " v)) ++ "\n" ++ ind level ++ "}"
  | _ => J.flat false ", " ": " j

/-- The four laws by file stem. `L-run` is the compiler's. -/
def laws (w : Principals) : List (String × Pred) :=
  [("L-src", lSrc w), ("L-obj", lObj w), ("L-rev", lRev w), ("L-run", lRun w)]

end VerekosMap
