/-
`verekos-map`: the slice-1 mapper and laws, computed by the World shapes and
minidregg's `Pred`. Subcommands and flags are the twin's (and the laws script's for
`laws`); see map/README.md.
-/
import VerekosMap

open VerekosMap

def usage : String := "usage: verekos-map (split FILE | id PART... | import | render | plan | compile | runrec | attest | review | laws) --flag value ...
  import  --source-key K --path P --file F --cell NAME [--read READ.json] --out REQ.json
  render  --key K --read READ.json --out FILE
  plan    --export E --source K=READ.json ...
  compile --export E --source K=READ.json ... --cells CELLS.json --out DIR [--current NAME=READ.json ...] [--ekos-version S]
  runrec  --dir DIR --source K=READ.json ... --cell NAME [--read READ.json] [--ekos-version S] [--mapper-file F | --mapper-sha256 HEX] --out REQ.json
  attest  --compile-run READ.json --claimed SHA --replayed SHA --cell NAME --source-cell NAME [--read READ.json] [--replayer N] --out REQ.json
  review  --conflict READ.json --conflict-cell NAME --cell NAME [--read READ.json] --pick K [--verb V] [--note TEXT] --out REQ.json
  laws    --out DIR [--owner S --importer S --compiler S --reviewer S --verifier S]
  source  [--key K] --read READ.json          (JSON: a source document's statements, for reader/)
  edit-atom --read R --source-key K --structural S --cell C --file F --out REQ.json
  structural-key TEXT | table-cell NAME"

def cmdLaws (a : List (String × String)) : IO Unit := do
  let out : System.FilePath := ← arg a "out"
  IO.FS.createDirAll out
  match arg? a "owner" with
  | none =>
    for (stem, p) in laws {} do
      IO.FS.writeFile (out / s!"{stem}.json") (pretty 0 0 (← liftM (predJ p)) ++ "\n")
      IO.println s!"{stem}.json"
  | some owner =>
    let int := fun (k : String) => do
      match (← arg a k).toInt? with
      | some n => pure n
      | none => throw (IO.userError s!"--{k} is not an integer")
    let w : Principals := ⟨← int "importer", owner.toInt!, ← int "compiler", ← int "reviewer"⟩
    let files := [("L-src", lSrc w), ("L-obj", lObj w), ("L-rev", lRev w),
      ("L-run-compiler", lRun w), ("L-run-verifier", lRun { w with compiler := ← int "verifier" })]
    for (stem, p) in files do
      IO.FS.writeFile (out / s!"{stem}.json") (J.spaced (← liftM (predJ p)) ++ "\n")
    for (stem, p) in sortBy (·.1) files do
      IO.println s!"{stem}.json\t{J.spaced (← liftM (predJ p))}"

def run (argv : List String) : IO Bool := do
  match argv with
  | "split" :: file :: _ => cmdSplit file; pure true
  | "id" :: parts => IO.println (num parts); pure true
  | ["structural-key", text] => cmdStructuralKey text; pure true
  | ["table-cell", name] => cmdTableCell name; pure true
  | cmd :: rest =>
    let a ← liftM (parseArgs rest)
    match cmd with
    | "import" => cmdImport a; pure true
    | "render" => cmdRender a; pure true
    | "plan" => cmdPlan a; pure true
    | "compile" => cmdCompile a; pure true
    | "runrec" => cmdRunrec a; pure true
    | "attest" => cmdAttest a; pure true
    | "review" => cmdReview a; pure true
    | "laws" => cmdLaws a; pure true
    | "source" => cmdSource a; pure true
    | "edit-atom" => cmdEditAtom a; pure true
    | _ => pure false
  | [] => pure false

def main (argv : List String) : IO UInt32 := do
  try
    if ← run argv then pure 0 else
      IO.eprintln usage
      pure 2
  catch e =>
    IO.eprintln s!"verekos-map: {e}"
    pure 1
