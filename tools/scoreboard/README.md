# The scoreboard tools (W5 + W9, 2026-10-19)

What lives here, in plain words. The design documents are
`docs/design/explorations/03-scoreboard.md` (the spec) and
`docs/design/VEREKOS-DESIGN-2026-10-19.md §6`; the lane memos are
`notes/W5-control-dump.md` (the control binary) and
`notes/W9-scoreboard-machinery.md` (the scorer, board, regen, store panel).

## Layout

```
tools/scoreboard/
  control-dump/          the control binary, its own Cargo workspace
    Cargo.toml           path deps on /Users/ember/dev/EKOS/ekos/crates/{ledger,kir,semantic,identity,common}
    rust-toolchain.toml  copied from EKOS (1.98.0), so the control builds with EKOS's compiler
    src/main.rs          arg dispatch, panel reader, expected-file checker
    src/scope_dump.rs    the Scope decision control (Compiled::visible & co)
    src/scope_store_dump.rs the ScopedStore control (a real Ledger, built via public API)
    src/conflicts_dump.rs the Conflicts kernel control
  score.py               score a candidate against a control (§3, §5.3)
  board.py               render docs/parity/BOARD.md (§4)
  regen_controls.py      the one control-regeneration command (§5.2)
panels/
  scope/decision.jsonl      inputs only (59 items from 17 EKOS tests)
  scope/store.jsonl         ordered step scenarios (8 items from 8 store tests)
  conflicts/unit.jsonl      inputs only (16 items from 8 EKOS tests)
  LABELS.json               assurance label + measures/does-not-measure per panel
  transcribed/
    scope_tests.py          the transcription data + generator (scope decisions)
    scope_store_tests.py    ditto, the ScopedStore scenarios
    conflicts_tests.py      the transcription data + generator (conflicts)
    drift_check.py          fails when a transcribed EKOS test's source text changes
    scope_drift.json        recorded sha256 of each transcribed scope test function
    scope_store_drift.json  ditto, store tests + the object/world/scoped/names helpers
    conflicts_drift.json    same, for conflicts
controls/
  MANIFEST.json                       what was pinned when the control was built (regen writes it)
  classified.jsonl                     explained differences, sha256-keyed (§3.4, one manifest)
  scope.decision.expected.jsonl       what the transcribed tests assert (expect_from_test)
  scope.decision.control.jsonl        EKOS's own answers on the panel
  scope.store.expected.jsonl          per-step assertions of the store tests
  scope.store.control.jsonl           EKOS's own answers (results per step)
  conflicts.unit.expected.jsonl       ditto, conflicts
  conflicts.unit.control.jsonl        ditto, conflicts
docs/parity/
  README.md                           how to read the board; the five assurance labels
  BOARD.md                            the board (generated, never hand-edited)
```

A panel item is an input and nothing else; EKOS's answers never go in a panel.
The expected files hold the *assertions of the transcribed Rust tests*, not
EKOS's output — they come from the tests' own `assert!` lines.

## The commands

`regen_controls.py` does everything below in one go; the pieces:

```
# the control: EKOS's own functions answer every panel item
#   (each exits non-zero when a transcribed assertion fails; stderr ends
#    with a JSON summary line)
tools/scoreboard/control-dump/target/debug/control-dump scope \
    panels/scope/decision.jsonl --expected controls/scope.decision.expected.jsonl
tools/scoreboard/control-dump/target/debug/control-dump conflicts \
    panels/conflicts/unit.jsonl --expected controls/conflicts.unit.expected.jsonl
tools/scoreboard/control-dump/target/debug/control-dump store \
    panels/scope/store.jsonl --expected controls/scope.store.expected.jsonl

# score a candidate against the control (the law: 0 unexplained, exit 1)
python3 -I tools/scoreboard/score.py --kernel scope \
    --panel panels/scope/decision.jsonl \
    --control controls/scope.decision.control.jsonl \
    --candidate <candidate.jsonl> --classified controls/classified.jsonl

# render the board
python3 -I tools/scoreboard/board.py

# regenerate everything (clean pin check, build if needed with nice -n 10
# logged to var/w9/, each dump twice byte-identically, control comparison,
# all five drift checkers, full MANIFEST)
python3 -I tools/scoreboard/regen_controls.py --ekos /Users/ember/dev/EKOS [--accept]

# drift checks (regen runs them; singly)
python3 -I panels/transcribed/drift_check.py --ekos /Users/ember/dev/EKOS --record panels/transcribed/scope_drift.json
python3 -I panels/transcribed/drift_check.py --ekos /Users/ember/dev/EKOS --record panels/transcribed/scope_store_drift.json
python3 -I panels/transcribed/drift_check.py --ekos /Users/ember/dev/EKOS --record panels/transcribed/conflicts_drift.json
```

Current numbers: scope.decision 59/59, conflicts.unit 16/16, scope.store
8/8 agree; all byte-identical across two runs; a deliberately flipped
expectation is caught (exit 1), and score.py's three recorded runs
(self / planted / classified: 0 / 1 / 0 unexplained) are in
`var/w9/score-selftest/` — the checks are not vacuous.

## What exists

- The control binary calls EKOS's real library code, pinned at
  `/Users/ember/dev/EKOS` @ `8e3c178` (recorded, with hashes, in
  `controls/MANIFEST.json`): `ReadScope::from_json`, `Compiled::visible`,
  `origins`, `is_unrestricted`, `duplicate_definitions`, `merge_losses`,
  `label_mismatches`, `normalize_type`, and — through the `store` dump —
  `Ledger::open`, the `append_*` writes, `ScopedStore::with_scopes`/
  `set_scopes` and every `KnowledgeStore` read the store tests assert on.
- The scope decision panel covers every parsing and decision test in
  `ekos/crates/ledger/src/scope.rs` (the `mod tests` families up to
  `origins_cross_sources_with_paths`).
- The scope store panel covers the ScopedStore tests (`scope.rs:1041` on,
  minus the source-inspection meta-test) as ordered step scenarios over the
  tests' own `world()` fixture: filtered reads, both-ends relationships,
  evidence gating, search, counts, diff, write/event/vacuum refusal,
  multi-scope intersection and replacement.
- The conflicts panel covers the detector tests of
  `ekos/crates/semantic/src/conflicts.rs`: type-alias normalization,
  duplicate definitions (collapse, silent collapse, per-attribute,
  permutation invariance), merge losses (exact vs fuzzy name match), label
  mismatches (different sources conflict; spellings and same-source variants
  do not).
- `score.py` (diff + classification, `controls/classified.jsonl`),
  `board.py` (`docs/parity/BOARD.md`), `regen_controls.py` (the one
  regeneration command; also runs the branch and identity lanes' drift
  checkers for the record).
- Deterministic output: object and conflict ids are UUIDv5 over panel keys
  (exactly EKOS's private `kid()` rule), claims come out sorted, `created_at`
  and evidence ids are never printed, and the store dump prints names,
  counts and booleans only. Two runs are byte-identical.

## What does not exist (yet, or at all in M0.5)

- `run_fixture.py` (fixture→workspace→graph) and with it the leak suite's
  MCP/CLI panel (marker words through every tool of a real `ekos mcp serve`)
  and the Ledger/Impact/Time/EKL fixture panels.
- Every other kernel dump: Ledger, Branch (W6's panel waits for it),
  Identity (W3's panel waits for it), Impact, Time, EKL, Fusion, Redact.
- Kernel binaries and the standing mutant family (`tools/scoreboard/
  standins/`): the planted-defect check so far is a hand-altered control
  copy, recorded in `var/w9/score-selftest/`.
- `content_signature` is `pub(crate)` in EKOS: nothing here needs it, but the
  Ledger and Branch controls will have to recompute it locally and self-check
  against stored signatures (the recorded decision).
- Events: no control exists in M0.5 (by decision).
- The conflicts review workflow (`resolve`, `carry_forward`, `column_links`)
  is not transcribed: it reviews conflicts rather than detecting them.

## Rules kept

The store dump writes only to its own temp directory (a scratch SQLite
ledger it built); the decision and conflicts dumps only read. EKOS is never
edited; anything EKOS does not export is reimplemented here in the smallest
way (so far only `kid()`, the UUIDv5 id rule) and checked against the tests'
own stability assertions. Builds run `nice -n 10`, one at a time. Nothing
under `target/` or `var/` is committed.
