# 05. The next three lanes

Written by the R1 review lane (Opus), 2026-10-19 night, after reading the
whole tree. Three briefs, each ready to hand to a lane: ground truth with
absolute paths, deliverables, the receipts that would prove each, and what
each needs that does not exist yet. The order matters less than the rule they
share: **each one ends in a number on the board or a receipt, not a green
build.**

Shared ground truth for all three:

- Repo `/Users/ember/dev/verekos`, branch `dev`, `origin` `emberian/verekos`.
  Rules: `/Users/ember/dev/verekos/CLAUDE.md` (quote its process block in the
  brief; never kill by pattern; PID files; named-file commits; push often).
- EKOS pin `/Users/ember/dev/EKOS` at `8e3c178`, read-only. Release binary
  `/Users/ember/dev/EKOS/ekos/target/release/ekos` (sha256 `03cf977b…`,
  recorded in `controls/ledger.ecommerce.sidecar.json`). A new build sets
  `CARGO_TARGET_DIR=/Users/ember/dev/verekos/var/ekos-build/target`.
- minidregg pin `dcab86da`, read-only; the Lean model reaches it only through
  `world/.lake/packages/minidregg`.
- hbox: binaries in `~/kn-gate/fix/tipbin/` (host, `mini`, store, verifier;
  checksums in `notes/W7-hbox-transclusion.md`); slice-1 run root
  `~/verekos-runs/slice1/run-1`; disk about 30 GB free, so small run roots
  only, `swarm-build` for anything heavy.

---

## Lane A. M1a, the reader-local compile (exploration 04 §3-4)

**The claim it demonstrates.** A reader who can see part of a world compiles
what *they* can read, on their own machine, and every answer ends in a pin
that re-checks as `same bytes` or `moved`. No node change, no kernel change,
nothing published.

**Most of it already exists, inside slice 1.** `slice1/compile.sh` is a
reader-local compile whose reader happens to be the `compiler` principal:

1. `read_to OUT WHO REF` (`slice1/world-lib.sh`, the function at the end) is a
   signed read as `WHO` of one cell, saved with its target.
2. `python3 -I slice1/mapper.py render --key K --read READ.json --out FILE`
   concatenates the source document's statement atoms into the file EKOS
   compiles (`mapper.py`, `cmd_render`).
3. `slice1/ekos-compile.sh WS OUT` runs the unchanged EKOS pipeline and writes
   `export.ndjson` (with named properties) and `conflicts.json`.

So M1a is: the same three steps run as `reader-shop` (who observes only the
`shop` room), with no submit, plus the one piece that does not exist, the
**answer-with-pin** step.

**Deliverables** (new directory `/Users/ember/dev/verekos/reader/`; nothing
under `slice1/`, which is W17's):

1. `reader/sync.sh WHO` — signed reads of every source cell `WHO` can name
   (the refs in `$W/WHO-workspace/refs/`), a refused read recorded as a row,
   not an error; render; compile with `ekos-compile.sh` into
   `var/reader/<who>/<stamp>/`. Prints the counts exploration 04 §4 shows
   ("N documents, M statements, K objects, J I could not read").
2. `reader/answer.py` (stdlib, `python3 -I`) with three subcommands over the
   local workspace:
   - `find TEXT` — `ekos query find TEXT` with JSON output (`query.rs` takes
     a `format` of `json`; check the flag's spelling in
     `/Users/ember/dev/EKOS/ekos/crates/cli/src/commands/query.rs`);
   - `impact NAME` — two hops of `ekos ekl` or the dependents traversal;
   - `disagree` — `ekos conflicts list --json`.
   Each hit is mapped to a pin: the source cell, the statement atom (by the
   structural key the mapper already uses, `mapper.py:structural_key`, a
   GUESS because EKOS evidence names only the file, `mapper.py:344`), and the
   atom revision read at sync time.
3. `reader/check.py` — re-reads the cited cells (one signed read each) and
   prints `same bytes` or `moved` per pin, comparing the atom's current
   revision with the recorded one (`mapper.py`'s `Doc.revision(atom)`).
4. `notes/M1a-reader-local.md`.

**Receipts** (each a row in `var/reader/receipts.tsv`, the slice-1 row
format of `world-lib.sh:row`):

| # | Expected |
|---|---|
| A1 | `reader-shop`'s sync reads `src-shop`; its read of `src-legacy` is refused by the host (the refusal text recorded) |
| A2 | `reader-shop`'s local compile has 6 tables and **0 conflicts**; the compiler's compile of the same world (slice 1) has 1. A one-source reader sees no conflict because it never had the second source, not because a filter hid it |
| A3 | `find customers` returns a hit whose pin re-checks `same bytes` |
| A4 | after slice 1's step 6 edit (or an equivalent importer edit of `src-shop`), the same pin re-checks `moved`; a re-sync re-reads only the changed cell (count the reads) |
| A5 | `impact customers` two hops equals EKOS's own answer on the same copies (the control is EKOS run on the reader's own render, so this is EKOS-vs-EKOS; state that) |

**What it needs that does not exist yet.**
- Nothing on the world side: W17's setup already enrolls `reader-shop` and
  gives it a room delegation on `shop` only (`slice1/s2-setup.sh:24`, `:57`),
  and records every subject in `$RUN/principals.json`. Read W17's memo for
  the run root that survived, and write only under `~/verekos-runs/reader/`.
- An EKOS search CLI that returns ids in JSON (to be checked; `ekos ekl` is the
  fallback and certainly returns ids).
- A decision on where pins live when EKOS's evidence is file-level: the
  structural-key GUESS is the slice-1 answer and should be reused, not
  re-invented, and reported as a guess in every output line.

**Out of scope.** Prose documents (exploration 04's Mira); a model's
summaries; publishing anything; any change to `mini`.

---

## Lane B. `verekos check`: run the Lean model on the panels

**Why this is the most important lane.** Today every "agree" on the board is
EKOS against itself. The Lean model in `world/` has about 150 theorems and has
never answered a panel item. Until it does, no row can move past
`design target`, and nothing checks that the model's definitions mean what the
panels mean. This lane is the bridge.

**Ground truth.**
- The Mathlib-free part of the model: `world/World/Claim.lean`, `Log.lean`,
  `Status.lean`, `Visible.lean`, `Traverse.lean` import only each other
  (check with `grep -n '^import' world/World/*.lean`). `Conflicts.lean`,
  `WellFormed.lean`, `Identity.lean`, `Admission.lean`, `Document.lean` import
  Mathlib. `Identity.canonical` is `noncomputable` (`Identity.lean:98`).
- A concrete carrier set exists: `C₀` with `Nat` carriers and the `Cols`
  payload (defined in `world/World/Conflicts.lean`, used throughout
  `world/World/Examples.lean`), with `decide`-checked runs.
- Panels and controls: `tools/scoreboard/README.md` lists every file. The
  candidate format `score.py` reads: one JSON line per item,
  `{"item": …, <answer fields>}`, the same fields as the control.

**Deliverables.**
1. A new Lean library and executable **in a new directory**
   `/Users/ember/dev/verekos/check/` (its own `lakefile.toml`, requiring
   `world` by path), so `world/` stays the model and the runner can be
   rebuilt without touching it. Executable `verekos-check` reads a panel JSONL
   on stdin and writes candidate lines on stdout (Lean's `Lean.Json` parser).
   Import only the Mathlib-free modules for the first two panels, so the
   executable does not compile Mathlib (link time and disk matter; measure the
   build and say so).
2. **`scope.decision` (59 items) through `World.visible`.** The mapping is the
   untrusted part and must be labelled so: an EKOS `ReadScope` JSON (default,
   rules by source, path glob, object id) becomes a `World.Scope` (the four
   predicates); each `(source, path)` origin becomes a source pin; the item's
   id becomes the claim id; depth 1. The glob matcher is per-kind code (design
   §4 "stays per kind"), written in Lean or ported, and is not proved. Parse
   errors (`{"error":"parse"}`) come from the runner's own scope parser and
   are untrusted too. Expected first result: some items disagree. That is the
   point: each disagreement is a VerEKOS defect, an EKOS defect or a stated
   non-goal, classified with `score.py`.
3. **`conflicts.unit` (16 items) through `World.detect`**, compared on the
   *join view* (design §6): the set of (subject, attribute) keys EKOS reports,
   not its conflict objects' ids, claims or `chosen`. This needs a projection
   of `controls/conflicts.unit.control.jsonl` to keys, done in
   `tools/scoreboard/` as a named, tested projection, not by editing the
   control. `detect` needs Mathlib's `Finset`; either accept the link cost or
   add a `List`-based `detectList` runner and prove it equal to `detect` (the
   lemma `detectList_congr` is most of it).
4. **`verekos check laws <world-run-root>`** (the "law consumer" half): read a
   slice-1 run's receipts and the cells' read JSON, rebuild the log as
   `World.Receipt`s, and check the model's laws on the real run: `AdmLog`
   (decidable, `Admission.lean`), every compiled claim's pins nonempty
   (`Claim.WellFormed`), and `status` of the conflict after the step-6 edit is
   `needsReview` when the core is the header revision (the 3.1 correction).
   This is where the Lean admission law meets real receipts for the first
   time; disagreements are findings about the model or the mapper.
5. `board.py` gains a candidate column fed by `var/check/<panel>.jsonl` plus
   a verdict file from `score.py --out`; a row moves to `executable property`
   only when its candidate is scored.
6. `notes/B-check.md` with the numbers.

**Receipts.** `score.py` verdicts for `scope.decision` and `conflicts.unit`
with candidate sha256, panel sha256 and the `check/` build hash; every
difference classified (none left unexplained); one planted mutant (deny
ignored in the mapping) that scores worse.

**What it needs that does not exist yet.** A JSON reader for `World` types
(new); the ReadScope parser and glob matcher in Lean (new, untrusted); a
`Scope` of EKOS's "unknown source counts as denied" rule (check
`/Users/ember/dev/EKOS/ekos/crates/ledger/src/scope.rs` near `Compiled::visible`
before assuming World's "not allowed" means the same thing); the key
projection of the conflicts control; a decision from the root on whether
`check/` may link Mathlib.

**Model questions this lane will force** (say which way each goes in the memo):
an explicitly allowed id is visible even when none of its pins is allowed
(`World/Visible.lean:57`), which may not be EKOS's rule; the `author` of a
receipt is taken as given (`World/Status.lean:60`), so a runner over real
receipts must take it from the signer, not from the payload.

---

## Lane C. The remaining controls and one panel layout

**Two halves, one owner**, because both touch `control-dump` and
`regen_controls.py` and should not race.

**Half 1: controls for `redact.unit` (26 items) and `ekl.parser` /
`ekl.interpreter` (50 + 33).**
- Ground truth: inputs `panels/redact/items.jsonl`, `panels/ekl/items.jsonl`;
  expected `controls/redact.expected.jsonl`, `controls/ekl.expected.jsonl`;
  drift `panels/redact/drift.json`, `panels/ekl/drift.json` (both pass
  `panels/transcribed/drift_check.py --panel`). The functions:
  `ekos_common::redaction::{redact, redact_json, is_excluded_path}`
  (`/Users/ember/dev/EKOS/ekos/crates/common/src/redaction.rs`), the EKL
  parser and interpreter (`/Users/ember/dev/EKOS/ekos/crates/ekl/src/{parser,interpreter}.rs`).
- Deliverables: `control-dump` subcommands `redact` and `ekl` (new files
  `src/redact_dump.rs`, `src/ekl_dump.rs`; `ekos-ekl` added as a path
  dependency), each with `--expected` reproducing every transcribed assertion;
  two `REGISTRY` entries in `regen_controls.py`; `controls/redact.unit.control.jsonl`,
  `controls/ekl.parser.control.jsonl`, `controls/ekl.interpreter.control.jsonl`;
  `LABELS.json` rows gain `control_file`.
- Known traps from the W15/W16 memos: three `AS OF` tests have no fixed
  timestamp; the fuzz test asserts only "no panic"; several rejects assert
  only `is_err()`; redaction tests that assert a substring or count must be
  checked as such, not as whole-string equality. The interpreter items fix
  `Uuid::new_v4` ids to `00000000-0000-5000-8000-0000000000NN`.
- Receipt: `regen_controls.py --ekos` green with 11 controls, each
  reproducible, `Test asserts` N/N on the board for all three rows.

**Half 2: one panel layout** (after Half 1, with no other scoreboard lane
live). The target is in `CLAUDE.md` ("Panel conventions"). Moves, each with
every reader updated in the same commit (`regen_controls.py` REGISTRY,
`panels/LABELS.json`, `controls/MANIFEST.json` by a regen run, the generators
in `panels/transcribed/`, `tools/scoreboard/README.md`, the lane memos'
command lines may stay as history):

| From | To |
|---|---|
| `panels/scope/decision.jsonl`, `panels/scope/store.jsonl` | `panels/scope/decision.items.jsonl`, `panels/scope/store.items.jsonl` (two panels, one family) |
| `panels/conflicts/unit.jsonl` | `panels/conflicts/items.jsonl` |
| `panels/identity/identity.unit.jsonl` | `panels/identity/items.jsonl` |
| `panels/identity/controls/identity.unit.controls.jsonl` | `controls/identity.unit.expected.jsonl` |
| `panels/branch/controls/expected.jsonl` | `controls/branch.unit.expected.jsonl` |
| `controls/impact.expected.jsonl`, `controls/impact.control.jsonl` | `controls/impact.unit.expected.jsonl`, `controls/impact.unit.control.jsonl` |
| `controls/redact.expected.jsonl` | `controls/redact.unit.expected.jsonl` |
| `controls/ekl.expected.jsonl` | split by panel into `controls/ekl.parser.expected.jsonl` and `controls/ekl.interpreter.expected.jsonl` |
| `panels/transcribed/{scope,scope_store,conflicts}_drift.json` | `panels/scope/decision.drift.json`, `panels/scope/store.drift.json`, `panels/conflicts/drift.json` |
| `panels/transcribed/*_tests.py` | beside their panels (`panels/scope/gen_decision.py` …) |
| `panels/transcribed/drift_check.py` | `tools/scoreboard/drift_check.py` |
| `panels/identity/drift.py`, `panels/branch/drift.py` | deleted; their REGISTRY entries call `drift_check.py` (it already reproduces both records, R1 commit `6aec0eb`) |

Also: make `--expected` one shape (`{"item", "expect", "expect_from_test"}`)
across the six existing subcommands, since three spellings exist today; and
make the ledger versions control reproducible from scratch (R1 finding S3):
drop the v4 evidence ids and the evidence-bearing signatures from the
committed control (keep counts and the no-evidence signatures), and keep the
EKOS#10 demonstration as a classified difference with its own recorded
workspace hash.

Receipt: a regen run after the moves with every control `identical` (moving
a file must not change one byte of any control), `drift_check.py --panel` 0
drifted on every family, and the board unchanged except paths.

**What it needs that does not exist yet.** Nothing new in EKOS; a quiet
window with no other lane writing `controls/` or `regen_controls.py`.
