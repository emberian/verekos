# The scoreboard tools (W5, 2026-10-19)

What lives here, in plain words. The design documents are
`docs/design/explorations/03-scoreboard.md` (the spec) and
`docs/design/VEREKOS-DESIGN-2026-10-19.md §6`; the lane memo is
`notes/W5-control-dump.md`.

## Layout

```
tools/scoreboard/
  control-dump/          the control binary, its own Cargo workspace
    Cargo.toml           path deps on /Users/ember/dev/EKOS/ekos/crates/{ledger,kir,semantic,identity,common}
    rust-toolchain.toml  copied from EKOS (1.98.0), so the control builds with EKOS's compiler
    src/main.rs          arg dispatch, panel reader, expected-file checker
    src/scope_dump.rs    the Scope kernel control
    src/conflicts_dump.rs the Conflicts kernel control
panels/
  scope/decision.jsonl      inputs only (59 items from 17 EKOS tests)
  conflicts/unit.jsonl      inputs only (16 items from 8 EKOS tests)
  transcribed/
    scope_tests.py          the transcription data + generator (scope)
    conflicts_tests.py      the transcription data + generator (conflicts)
    drift_check.py          fails when a transcribed EKOS test's source text changes
    scope_drift.json        recorded sha256 of each transcribed scope test function
    conflicts_drift.json    same, for conflicts
controls/
  MANIFEST.json                       what was pinned when the control was built
  scope.decision.expected.jsonl       what the transcribed tests assert (expect_from_test)
  scope.decision.control.jsonl        EKOS's own answers on the panel
  conflicts.unit.expected.jsonl       ditto, conflicts
  conflicts.unit.control.jsonl        ditto, conflicts
```

A panel item is an input and nothing else; EKOS's answers never go in a panel.
The expected files hold the *assertions of the transcribed Rust tests*, not
EKOS's output — they come from the tests' own `assert!` lines.

## The two commands

Build once (`nice -n 10 cargo build`, log to `var/w5/build.log`), then:

```
# the control: EKOS's own functions answer every panel item
tools/scoreboard/control-dump/target/debug/control-dump scope \
    panels/scope/decision.jsonl --expected controls/scope.decision.expected.jsonl \
    > controls/scope.decision.control.jsonl
tools/scoreboard/control-dump/target/debug/control-dump conflicts \
    panels/conflicts/unit.jsonl --expected controls/conflicts.unit.expected.jsonl \
    > controls/conflicts.unit.control.jsonl

# the drift check: have the transcribed EKOS tests changed?
python3 -I panels/transcribed/drift_check.py --ekos /Users/ember/dev/EKOS --record panels/transcribed/scope_drift.json
python3 -I panels/transcribed/drift_check.py --ekos /Users/ember/dev/EKOS --record panels/transcribed/conflicts_drift.json
```

Both dump commands exit non-zero when any assertion fails, and print
`{"panel":..., "items":N, "agree":N, "mismatch":0, "missing":0}` on stderr.
`--expected` can be dropped to produce a bare control file. The control JSONL
on stdout is one line per panel item, same order.

Current numbers: scope.decision 59/59 agree; conflicts.unit 16/16 agree; both
byte-identical across two runs; a deliberately flipped expectation is caught
(exit 1) — the checks are not vacuous.

## What exists

- The control binary calls EKOS's real library code, pinned at
  `/Users/ember/dev/EKOS` @ `8e3c178` (recorded, with hashes, in
  `controls/MANIFEST.json`): `ReadScope::from_json`, `Compiled::visible`,
  `origins`, `is_unrestricted`, `duplicate_definitions`, `merge_losses`,
  `label_mismatches`, `normalize_type`.
- The scope panel covers every parsing and decision test in
  `ekos/crates/ledger/src/scope.rs` (the `mod tests` families up to
  `origins_cross_sources_with_paths`).
- The conflicts panel covers the detector tests of
  `ekos/crates/semantic/src/conflicts.rs`: type-alias normalization,
  duplicate definitions (collapse, silent collapse, per-attribute,
  permutation invariance), merge losses (exact vs fuzzy name match), label
  mismatches (different sources conflict; spellings and same-source variants
  do not).
- Deterministic output: object and conflict ids are UUIDv5 over panel keys
  (exactly EKOS's private `kid()` rule), claims come out sorted, and
  `created_at` and evidence ids are never printed. Two runs are
  byte-identical.

## What does not exist (yet, or at all in M0.5)

- `regen_controls.py`, `score.py`, `classify.py`, `board.py`, the planted
  defect stand-ins, `BOARD.md` — the scoreboard around the control. The
  planted-defect checks so far were ad-hoc (a flipped expectation file).
- Every other kernel: Ledger, Branch, Identity, Impact, Time, EKL, Fusion,
  Redact panels and dumps. In particular the scope **store** family (the
  leak-suite inputs, `scope.rs:1041` on) needs the fixture pipeline
  (`run_fixture.py`) and is not transcribed here.
- `content_signature` is `pub(crate)` in EKOS: nothing here needs it, but the
  Ledger and Branch controls will have to recompute it locally and self-check
  against stored signatures (the recorded decision).
- Events: no control exists in M0.5 (by decision).
- The conflicts review workflow (`resolve`, `carry_forward`, `column_links`)
  is not transcribed: it reviews conflicts rather than detecting them.

## Rules kept

The binary only reads; it opens no store. EKOS is never edited; anything
EKOS does not export is reimplemented here in the smallest way (so far only
`kid()`, the UUIDv5 id rule) and checked against the tests' own stability
assertions. Builds run `nice -n 10`, one at a time. Nothing under `target/`
or `var/` is committed.
