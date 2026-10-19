# The scoreboard

The scoreboard measures EKOS against its own tests and fixtures, so that a
VerEKOS candidate (a Lean definition from `world/`, run on the same inputs)
can later be scored against EKOS item by item. Spec: exploration 03
(`docs/design/explorations/03-scoreboard.md`); design §6. Lane memos: W5
(control binary), W9 (scorer, board, regen), W3/W6/W11/W15/W16 (panels),
W12 (identity, branch, impact dumps), W18 (fixture pipeline), W20 (ledger
versions dump, EKOS#10). The board: `docs/parity/BOARD.md`.

**What it measures today.** EKOS's own functions reproduce what its own tests
assert, on inputs transcribed from those tests (279 items, all reproduced),
and EKOS's real binary reproduces its own stated counts on two fixtures.
Lane B's `check/` scores the Lean model as a candidate on `scope.decision`
and `conflicts.unit` (the board's Candidate column); every other row's Agree
is still the control against itself.

## The pieces

| Piece | What it does |
|---|---|
| `control-dump/` | Rust, its own Cargo workspace, path dependencies on `/Users/ember/dev/EKOS/ekos/crates/*` at the pin. Subcommands `scope`, `store`, `conflicts`, `identity`, `branch`, `impact`, `redact`, `ekl --which ekl.parser|ekl.interpreter` read a panel and print EKOS's answer per item; with `--expected` they also check every transcribed assertion and exit non-zero on a miss. `ledger <workspace>` reads a compiled workspace read-only and prints versions, recomputed content signatures and a diff. Toolchain copied from EKOS (1.98.0). Builds to its own `target/`. |
| `regen_controls.py` | The one regeneration command: refuses a dirty EKOS, rebuilds the dump if its sources moved (`nice -n 10`), runs every dump twice (must be byte-identical), compares with the committed control (`--accept` to overwrite), runs every drift checker, rewrites `controls/MANIFEST.json`. |
| `run_fixture.py` | `run`: one fixture through the real six-stage `ekos` pipeline in a scratch workspace under `var/`, writing `controls/ledger.<name>.*` and a sidecar; `compare`: two runs field by field, volatile versus content. |
| `score.py` | Scores a candidate JSONL against a control JSONL; every difference is looked up in `controls/classified.jsonl` by a sha256 over (panel, item, control, candidate). Exit 1 on anything unexplained or classified `verekos_defect`. |
| `board.py` | Renders `docs/parity/BOARD.md` from `panels/LABELS.json`, the controls, `controls/MANIFEST.json` and the classification manifest. Fails on an empty "measures" or "does not measure" cell. |
| `drift_check.py` | The drift checker: hashes each transcribed EKOS test function at the pin and fails when one moved; `--panel` also fails when a panel cites a test the record does not pin. |

## The panels, file by file

One rule, no exceptions (lane C, `notes/C-controls-layout.md`): panel `a.b`
has its inputs in `panels/a/b.jsonl`, the transcribed test assertions in
`controls/a.b.expected.jsonl` (one shape: `{"item", "expect",
"expect_from_test"}`), EKOS's answers in `controls/a.b.control.jsonl`, and
its drift record in `panels/a/b.drift.json`. `regen_controls.py` derives all
four paths from the name.

| Panel | Items | Control from | Generator | Notes |
|---|---|---|---|---|
| `scope.decision` | 59 | `control-dump scope` | `panels/scope/gen_decision.py` | |
| `scope.store` | 8 | `control-dump store` | `panels/scope/gen_store.py` | |
| `conflicts.unit` | 16 | `control-dump conflicts` | `panels/conflicts/gen_unit.py` | |
| `identity.unit` | 58 | `control-dump identity` | by hand (W3) | |
| `branch.unit` | 3 | `control-dump branch` | by hand (W6) | drift record hashes from `#[test]` (`"span"`) |
| `impact.unit` | 26 | `control-dump impact` | by hand (W11) | |
| `redact.unit` | 26 | `control-dump redact` | by hand (W15) | whole return value compared (stronger than 12 of the tests) |
| `ekl.parser` | 50 | `control-dump ekl --which ekl.parser` | by hand (W16) | parse under `catch_unwind`; an `error` expectation is a prefix of the message (the tests assert only `is_err()`) |
| `ekl.interpreter` | 33 | `control-dump ekl --which ekl.interpreter` | by hand (W16) | three `AS OF` items use the wall clock exactly as the tests do (no fixed clock exists); no timestamp is printed |
| `ledger.ecommerce`, `ledger.northwind` | 1 each | `run_fixture.py` (graph, EKL rows, status, conflicts, sidecar: `controls/ledger.<name>.*`) and `control-dump ledger` (`controls/ledger.<name>.versions.control.jsonl`) | `run_fixture.py --panel-file` | no expected file; the workspace `var/w18/<name>/ws` is rebuilt by regen when missing, and the versions control is compared without its evidence-id fields (`MANIFEST.json`, `ledger_versions_compared_without`) |

## Commands

```
# regenerate every control, check drift, rewrite the manifest
python3 -I tools/scoreboard/regen_controls.py --ekos /Users/ember/dev/EKOS [--accept]

# one dump by hand
tools/scoreboard/control-dump/target/debug/control-dump scope \
    panels/scope/decision.jsonl --expected controls/scope.decision.expected.jsonl

# drift, one record, with coverage
python3 -I tools/scoreboard/drift_check.py --ekos /Users/ember/dev/EKOS \
    --record panels/impact/unit.drift.json --panel panels/impact/unit.jsonl

# score a candidate (law: 0 unexplained)
python3 -I tools/scoreboard/score.py --kernel scope --panel panels/scope/decision.jsonl \
    --control controls/scope.decision.control.jsonl --candidate <file> \
    --classified controls/classified.jsonl [--out var/<lane>/verdict.json]

# render the board
python3 -I tools/scoreboard/board.py

# a fixture through the real binary
python3 -I tools/scoreboard/run_fixture.py run \
    --fixture /Users/ember/dev/EKOS/tests/fixtures/ecommerce.sql --out var/<lane>/ecommerce
```

## What does not exist yet

- **Candidates** beyond `scope.decision` and `conflicts.unit` (lane B).
- Panels for Time and Fusion; the leak suite's MCP/CLI half (marker words
  through a real `ekos mcp serve`); fixtures beyond ecommerce and northwind.
- The standing mutant family (`standins/`, exploration 03 §3.5-2). The
  planted-defect checks so far are hand-altered copies, recorded in lane
  `var/` directories.
- Events: no control in M0.5, by decision.

## Rules kept

EKOS is never edited; anything it does not export is recomputed here in the
smallest way (the UUIDv5 `kid()` rule; `content_signature`, with two
self-checks against stored versions). The store and impact dumps write only
to their own temp ledgers; the ledger dump opens a workspace read-only.
Builds run `nice -n 10`, one at a time. Nothing under `target/` or `var/` is
committed.
