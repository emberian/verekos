/-
# MapProofs — what the generated laws decide on slice 1's refusals

The laws `verekos-map laws` renders are minidregg `Pred` values
(`VerekosMap.Laws`). Here minidregg's own evaluator (`Minidregg.Pred.eval`)
is run on the request shapes of slice 1's receipts R2 and R3 (W17 memo), with
run-2's real principals. Each statement is about one concrete state, closed
by `decide`; none is a general theorem about every request.

Hypotheses: none. What links these to the hbox refusals is that the
rendered JSON of the same values is byte-identical to the installed law files
(`map/receipt.sh`); that renderer is untrusted.

Built as its own library, never linked into `verekos-map`.
-/
import VerekosMap.Laws

namespace VerekosMap.Proofs

open Minidregg.Pred

/-- run-2's principals (`var/w17/run-2/principals.json`). -/
def run2 : Principals :=
  { importer := 12811640889601477773, owner := 7, compiler := 17155919447801168794,
    reviewer := 17742909249709527374 }

def st (xs : List (Slot × Int)) : State := ⟨xs⟩

/-- A content write by `who`: mutate (verb 2) with these content counters. -/
def write (who : Int) (counters : List (Slot × Int)) : State :=
  st ([("request/verb", 2), ("request/subject", who)] ++ counters)

/-- R2: the compiler's birth of an object cell with no transclusion is refused by L-obj. -/
theorem r2_birth_without_transclusion_refused :
    eval (lObj run2) (st []) (write run2.compiler
      [("content/annotations", 0), ("content/marks", 0), ("content/document-creates", 1),
       ("content/transclusions", 0)]) = false := by decide

/-- The control: the same birth with one transclusion is admitted. -/
theorem r1_birth_with_transclusion_admitted :
    eval (lObj run2) (st []) (write run2.compiler
      [("content/annotations", 0), ("content/marks", 0), ("content/document-creates", 1),
       ("content/transclusions", 1)]) = true := by decide

/-- R3: the compiler appending a decision to the review cell is refused by L-rev. -/
theorem r3_compiler_review_refused :
    eval (lRev run2) (st []) (write run2.compiler
      [("content/atom-edits", 0), ("content/tombstones", 0)]) = false := by decide

/-- The control: the reviewer's append is admitted, and the reviewer's edit of an atom is not. -/
theorem reviewer_append_admitted :
    eval (lRev run2) (st []) (write run2.reviewer
      [("content/atom-edits", 0), ("content/tombstones", 0)]) = true := by decide

theorem reviewer_edit_refused :
    eval (lRev run2) (st []) (write run2.reviewer
      [("content/atom-edits", 1), ("content/tombstones", 0)]) = false := by decide

/-- L-src: only the owner may install a policy on a source cell. -/
theorem src_install_by_importer_refused :
    eval (lSrc run2) (st []) (st [("request/verb", 4), ("request/subject", run2.importer)]) = false := by
  decide

end VerekosMap.Proofs
