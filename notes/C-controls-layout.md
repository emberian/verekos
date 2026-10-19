# Lane C: the redact and EKL controls, one panel layout, a regen that rebuilds its own workspaces

2026-10-19, night. Opus, taking over from a GLM lane C that died on "Prompt
is too long" before its first commit. Brief: exploration 05 lane C, plus the
coordinator's S3 instruction.

**Summary.**
1. EKOS's own functions now answer the redaction and EKL panels and
   reproduce every transcribed test assertion: `redact.unit` 26/26,
   `ekl.parser` 50/50, `ekl.interpreter` 33/33. With the six earlier panels,
   279 items, all reproduced. No mismatch, so nothing was classified.
2. One layout, no exceptions: panel `a.b` is `panels/a/b.jsonl`,
   `controls/a.b.expected.jsonl`, `controls/a.b.control.jsonl`,
   `panels/a/b.drift.json`. One expected shape (`expect` +
   `expect_from_test`), one drift checker (`tools/scoreboard/drift_check.py`,
   with coverage). `regen_controls.py` derives every path from the panel name.
3. S3 is fixed: with `var/w18` moved aside, regen rebuilt both fixture
   workspaces through `run_fixture.py` and came back green. The ledger
   versions control is compared without the five fields that carry EKOS#10's
   random evidence ids, and the manifest says which.
4. Incident: my staged `git mv`s were swept into lane B's commit `f47a53c` by
   the shared git index, so origin briefly had moved files with readers on
   the old paths (fixed by `e4326af` minutes later). CLAUDE.md now says never
   to leave anything staged.

## Commits

| Commit | What |
|---|---|
| `8f3c18b` | `redact_dump.rs` (GLM lane's, one type fix), `ekl_dump.rs` (new), main.rs dispatch (GLM lane's, plus a guard), `ekos-ekl` dependency, three controls |
| `f47a53c` (lane B's) | carried my staged renames by accident |
| `e4326af` | the rest of the layout move, expected shape, drift records, regen PANELS and S3, LABELS, MANIFEST, board |
| `6c80c46` | `tools/scoreboard/README.md`, `CLAUDE.md` (layout + shared-index rule), exploration 05 lane C marked done |

## The predecessor's work

The GLM lane left `redact_dump.rs` (untracked) and a `main.rs` diff: the
`redact` and `ekl --which` dispatch, an `Item.panel` field with filtering by
envelope panel, and an expected reader that took `expect` before `assert`.
Kept, with two fixes: a type error in the JSON comparison (`Value` against
`Map`), and a guard: when panel filtering leaves zero items, the dump now
errors instead of "agreeing" on nothing. The older `assert` and flat
expected spellings are now gone from the reader, because every expected file
was converted.

## The EKL control, and the clock

- Parser: `ekl_parse` under `catch_unwind` (the fuzz test's only assertion is
  "never panics"; 18 items, none panics). The whole AST is printed in one
  spelling. The tests that reject a query assert only `is_err()`; W16
  recorded the message, and the check requires the actual message to *start
  with* the recorded one (`invalid AS OF timestamp` is a prefix of the real
  message). That is stronger than the tests, and it holds.
- Interpreter: the tests' fixture is rebuilt in a temp SQLite ledger with the
  panel's fixed ids, and `EklInterpreter::execute` runs on it. Rows are printed
  in result order with sorted keys.
- `AS OF`: three tests compute their timestamp from `Utc::now()` after the
  appends. A fixed clock is not possible through the public API:
  `append_object` stamps `written_at` with the wall clock, and only the raw
  `append(&LedgerEntry)` takes a timestamp, but it skips the current-object
  table and search index that `append_object` maintains. So the control fills
  `{before}`, `{now}` and `{mid}` at the same moment the Rust tests do,
  including the two 5 ms sleeps around `{mid}`, and prints no timestamp.
  All three reproduce, and two runs are byte-identical. They depend on the
  clock exactly as the tests do, so I classified nothing as `non_goal`. The
  `{mid}` item also prints the test's second assertion, which is not about
  EKL (`reconstruct_state_at` shows no `row_count`): `false`, as asserted.
- Planted checks: one changed expectation per panel is caught (redact 25/26,
  parser 49/50, interpreter 31/33 with two plants; exit 1).

## The layout

The final rule differs from my own exploration 05 table in one way: inputs are
`panels/a/b.jsonl`, not `panels/a/items.jsonl`. That way lane B's two input
paths (`panels/scope/decision.jsonl`, `panels/conflicts/unit.jsonl`) were
already in place and `check/` needed no edit. The moves:

- Inputs: identity, branch, impact, redact to `<family>/unit.jsonl`. EKL split
  into `parser.jsonl` and `interpreter.jsonl`; ledger split into
  `ecommerce.jsonl` and `northwind.jsonl`. Line bytes are unchanged, so no
  control changed.
- Expected files: all under `controls/<panel>.expected.jsonl`. Identity's
  file came from `panels/identity/controls/`, branch's from
  `panels/branch/controls/`; impact and redact gained `.unit`; EKL was split.
  Scope, store and conflicts changed from `assert` to `expect` +
  `expect_from_test`, written by their generators, which now sit beside their
  panels (`panels/scope/gen_decision.py`, `gen_store.py`,
  `panels/conflicts/gen_unit.py`). Before the move I checked that each
  generator reproduced its committed files byte for byte. Branch changed from
  flat fields to `expect`.
- Controls: `impact.control.jsonl` became `impact.unit.control.jsonl`; new
  `redact.unit`, `ekl.parser`, `ekl.interpreter`.
- Drift: every record is now `panels/<a>/<b>.drift.json`, in one shape.
  Identity's flat record was rewritten with the same hashes. The EKL record
  was split by file (26 + 32 = 58). `panels/transcribed/` is gone; the
  checker moved to `tools/scoreboard/drift_check.py`; `panels/identity/drift.py`
  and `panels/branch/drift.py` are deleted.

## S3: regen on a fresh clone

`ensure_workspace` in `regen_controls.py`: if `var/w18/<fixture>/ws/.ekos` is
missing, it reads the fixture path and sha256 from the panel, refuses on a
hash mismatch, and runs `run_fixture.py run --fixture … --out
var/w18/<fixture>`. It records the binary and fixture sha256 from the sidecar
in the manifest run row.

What a rebuilt workspace changes, measured by diffing a fresh dump against the
committed control: per-object `evidence`, `signature`, `version_evidence`,
`version_signatures`, and the top-level `workspace` path. Nothing else
changed. `ledger_projection` drops exactly those five fields (they are listed
in MANIFEST as `ledger_versions_compared_without`). The no-evidence
signatures, versions, names, kinds, totals and diff stay compared. A changed
no-evidence signature is caught; an evidence-only change is not. Two runs on
one workspace must still be byte-identical. The committed control is left as
it was (W18's run) unless content moves.

Receipt (`var/laneC/regen-1.log`): `var/w18` moved to
`var/laneC/w18-before` (not deleted: W18 made it). Regen rebuilt both
workspaces with the same binary (`03cf977b`). Eleven controls came back
green: nine `identical`, the two ledger controls `identical_modulo_volatile`.
All nine drift records reported 0 drifted, with coverage.

## Left

- `controls/ledger.<name>.{graph.ndjson,objects.jsonl,…}` (run_fixture's
  own controls) are not re-compared by regen; `run_fixture.py compare` does
  that by hand.
- Lane memos W3 to W16 keep the old paths in their command lines; they are
  history.
- `var/laneC/w18-before` holds W18's original workspaces. It is git-ignored,
  and deleting it is the owner's call.
