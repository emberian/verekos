# map/ — the slice-1 mapper and laws, in Lean

`verekos-map` turns two imported SQL sources and an EKOS graph export into the
minidregg request files that build slice 1's cells, and writes the four
document laws. It replaced the Python twin and the Python laws script (slice 1's
first mapper and law renderer, deleted in `bddd85f`; they are in git history), and
makes `laws/L-*.json` an output instead of a hand-written input
(`laws/GENERATED.md`).

Everything that calls it runs on the Mac: `slice1/run.sh` maps here and sends
hbox only the request files to submit (`slice1/mac-lib.sh`), and `reader/`
uses it for ids, statement keys, source documents and cell names.

**What is computed by the model.** What goes into each cell comes from the
World shapes: `toDocument` (a table and its foreign-key edges), `encodeConflict`
(a conflict, with its signature computed by the model and checked against
EKOS's), `Manifest.compile`, `importSource` / `reimport` (source documents),
`ReviewDoc.append`, and `replayedDeterministic` (the attestation's label). The
laws are values of minidregg's own predicate type `Minidregg.Pred.Pred`, the
one the kernel evaluates.

**What is not trusted.** Turning those values into client JSON, reading the
signed views and the export, and splitting SQL into statements are new code
with no proofs. The evidence that they are right is the receipt below.

## Build and run

    cd map && nice -n 10 lake build        # ~11 s from clean; nothing is downloaded
    bash map/receipt.sh                    # from the repo root; never builds

World is pinned to one commit of this repository (`lakefile.toml`) and
cloned under `.lake/packages/world`; only its Mathlib-free part (`WorldCore`
modules) is imported, so the executable does not link Mathlib. minidregg is a
local clone at the pinned commit; the Mathlib-family packages are symlinks, as
in `check/`.

## Subcommands (the same flags as the twin)

| Command | Writes |
|---|---|
| `import --source-key K --path P --file F --cell C [--read R] --out REQ` | the source cell's import request (or prints `nothing to submit`) |
| `render --key K --read R --out FILE` | the source text EKOS compiles |
| `plan --export E --source K=R ...` | the cells a compile needs (stdout) |
| `compile --export E --source K=R ... --cells CELLS --out DIR [--current NAME=R ...] [--ekos-version S]` | one request per changed cell, `commands.json`, `commands.sha256` |
| `runrec --dir DIR --source K=R ... --cell C [--read R] [--ekos-version S] [--mapper-file F \| --mapper-sha256 H] --out REQ` | the compile-run record; `mapper_sha256` is H, or the SHA-256 of `--mapper-file` (default: this executable) |
| `attest --compile-run R --claimed SHA --replayed SHA --cell C --source-cell C [--replayer N] --out REQ` | the replay attestation |
| `review --conflict R --conflict-cell C --cell C --pick K [--verb V] [--note T] --out REQ` | a reviewer's decision |
| `laws --out DIR` | `L-{src,obj,rev,run}.json` with placeholder principals, in the layout of `laws/` |
| `laws --out DIR --owner S --importer S --compiler S --reviewer S --verifier S` | the five installed law files, as the Python laws script wrote them |
| `split FILE`, `id PART...` | diagnostics: the statement atoms of a file; one derived id |
| `source [--key K] --read R` | a source document's live statements in run order, as JSON (for `reader/`) |
| `edit-atom --read R --source-key K --structural S --cell C --file F --out REQ` | one `editAtom` replacing one statement atom's text (the reader scene's importer edit) |
| `structural-key TEXT`, `table-cell NAME` | one statement key; the compiled cell of a table |

## The receipt

`map/receipt.sh` reruns every command on slice 1's run-2 inputs
(`var/w17/run-2/`, local) and compares each output byte for byte with the file
the twin wrote (now: the committed request files under `var/w17/run-2/`,
`laws/L-*.json`, and `map/fixtures/`, the twin's split/id/key/cell outputs
recorded before it was deleted). On 2026-10-19: 95 of 95 identical, including compile 1
(SHA-256 of the nine request files `bcd84c64…`) and compile 2 (`2d0da4d2…`).
`MapProofs.lean` runs minidregg's evaluator on the generated laws and shows
they refuse slice 1's R2 and R3 requests and admit the controls.

## One deliberate difference from the twin

When a re-import **adds** a statement, the twin wrote `createAtom` +
`insertRun`, which the deployed client refuses ("unknown workspace content
action", minidregg `native/resource-client/src/content_privacy.rs:83`). This
mapper folds the new statement into the preceding live statement atom with one
`editAtom` (lane A's shape). The receipts never exercised that path.
