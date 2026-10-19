import Lean.Data.Json
import Check.Scope
import Check.Conflicts
import Check.Laws

open Lean

/-- Read panel JSONL from stdin; write one candidate line per item. -/
def runPanel (f : String → Json → List (String × Json)) : IO UInt32 := do
  let stdin ← IO.getStdin
  let stdout ← IO.getStdout
  let mut code : UInt32 := 0
  repeat
    let line ← stdin.getLine
    if line.isEmpty then break
    let line := line.trimAsciiEnd.toString
    if line.isEmpty then continue
    match Json.parse line with
    | .error e =>
      IO.eprintln s!"panel line is not JSON: {e}"
      code := 2
    | .ok j =>
      let item := (j.getObjValAs? String "item").toOption.getD ""
      let kind := (j.getObjValAs? String "kind").toOption.getD ""
      let input := j.getObjValD "input"
      let fields := f kind input
      stdout.putStrLn (Json.mkObj (("item", Json.str item) :: fields)).compress
  return code

def usage : String :=
  "usage: verekos-check scope [--mutant deny-ignored] < panel.jsonl\n       verekos-check conflicts [--clash] < panel.jsonl\n       verekos-check laws [--mutant author-from-payload] <run-root>"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["scope"] => runPanel (Check.Scope.answer .faithful)
  | ["scope", "--mutant", "deny-ignored"] => runPanel (Check.Scope.answer .denyIgnored)
  | ["conflicts"] => runPanel Check.Conflicts.answer
  | ["conflicts", "--clash"] => runPanel (Check.Conflicts.answerWith true)
  | ["laws", root] => Check.Laws.run root
  | ["laws", "--mutant", "author-from-payload", root] => Check.Laws.run root true
  | _ => IO.eprintln usage; return 2
