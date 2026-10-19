# W9: the scoreboard machinery — lane memo (2026-10-19)

1. `score.py` scores any candidate against a control: agree / mismatch /
   missing / extra, every difference classified against
   `controls/classified.jsonl` (sha256-keyed over (panel, item, control,
   candidate)), exit 1 on any unexplained — proven by three recorded runs
   (self 0, planted 1, classified 0).
2. `board.py` renders `docs/parity/BOARD.md` from the controls, the
   classification manifest and `panels/LABELS.json`; numbers come from a
   live control-vs-control run through score.py's own diff code, so
   agree + classified + unexplained = items holds on every row.
3. `regen_controls.py` is the one control-regeneration command: clean-pin
   check, rebuild-if-needed (nice -n 10, logged to var/w9/), every dump run
   twice byte-identically, committed controls compared (identical /
   moved-items report / --accept to overwrite), all five drift checkers,
   full `controls/MANIFEST.json`.
4. The ScopedStore family (scope.rs:1041 on) **cannot** be decision-panel
   items — it drives a store, not `Compiled::visible` — so control-dump grew
   a `store` subcommand (~370 lines) building the tests' world through
   ekos_ledger's public API; `scope.store` is 8 items from 8 tests, 8/8
   reproduce, two runs byte-identical.
5. Not built: `run_fixture.py` and with it the leak suite's MCP/CLI half,
   every kernel binary (nothing to score yet — score.py's three runs are the
   §3.5 self-checks), and the branch/identity controls (other lanes' panels,
   placeholder rows on the board).

Spec: `docs/design/explorations/03-scoreboard.md` §3-6. W5 memo:
`notes/W5-control-dump.md`. Commands: `tools/scoreboard/README.md`.

## The commands

```
# score a candidate (the law: 0 unexplained; exit 1 otherwise)
python3 -I tools/scoreboard/score.py --kernel scope \
    --panel panels/scope/decision.jsonl \
    --control controls/scope.decision.control.jsonl \
    --candidate <candidate.jsonl> [--classified controls/classified.jsonl] \
    [--out var/w9/<verdict>.json]

# render the board (docs/parity/BOARD.md; never hand-edited)
python3 -I tools/scoreboard/board.py

# regenerate everything: pin check, build, dumps ×2, control compare,
# drift checkers, MANIFEST
python3 -I tools/scoreboard/regen_controls.py --ekos /Users/ember/dev/EKOS [--accept]

# regenerate the store panel + expected from the transcription data
python3 -I panels/transcribed/scope_store_tests.py

# the three dump commands (what regen drives)
tools/scoreboard/control-dump/target/debug/control-dump scope     panels/scope/decision.jsonl    --expected controls/scope.decision.expected.jsonl
tools/scoreboard/control-dump/target/debug/control-dump conflicts panels/conflicts/unit.jsonl   --expected controls/conflicts.unit.expected.jsonl
tools/scoreboard/control-dump/target/debug/control-dump store     panels/scope/store.jsonl       --expected controls/scope.store.expected.jsonl
```

## The three score.py runs (var/w9/score-selftest/)

1. **Control vs itself** (§3.5-1 positive control): scope.decision
   `{items:59, agree:59, …, unexplained:0}` exit 0; conflicts.unit
   `{items:16, agree:16, …, unexplained:0}` exit 0.
   (`run1-self.log`, verdicts `scope.self.verdict.json`,
   `conflicts.self.verdict.json`.)
2. **One line altered** (§3.5-2 planted defect): a scratch copy of the scope
   control with `default_deny_hides_everything_without_a_rule#1`'s
   `visible` flipped → `{agree:58, mismatch:1, unexplained:1}` exit 1, the
   UNEXPLAINED list naming the item and its
   `diff_id=fb449a0a76c1fe15…`. (`run2-altered.log`,
   `scope.altered.verdict.json`.)
3. **That difference classified**: the entry added to
   `controls/classified.jsonl` (class `non_goal`, reason naming it as the
   self-test planted defect) → `{agree:58, classified:1, unexplained:0}`
   exit 0. (`run3-classified.log`, `scope.classified.verdict.json`.)

The store panel's self-score (after task 4): `{items:8, agree:8,
unexplained:0}` exit 0 (`scope.store.self.verdict.json`).

## The board as rendered (2026-10-19, final)

| Kernel | Panel | Items | Agree | Classified (E/V/N) | Unexplained | Assurance |
|---|---|---|---|---|---|---|
| Scope | scope.decision | 59 | 59 | 0/0/0 | 0 (law: 0) | design target |
| Conflicts | conflicts.unit | 16 | 16 | 0/0/0 | 0 (law: 0) | design target |
| Scope | scope.store | 8 | 8 | 0/0/0 | 0 (law: 0) | design target |
| Branch | branch.unit (W6 panel, no control) | 3 | — | — | — | design target |
| Identity | identity.unit (W3 panel, no control) | 58 | — | — | — | design target |

…plus placeholder rows for Ledger / Impact / Time / EKL / Fusion / Redact,
per-panel detail sections (self-score numbers; the one classification
manifest entry, labelled as belonging to the self-test run, not the board's
self-score), and the Not-measured list (search relevance, model-pass
quality, parser coverage, Events). Header carries the EKOS pin
`8e3c178fc45…` (tree `8719103d47…`), the MANIFEST sha256 and the standing
sentence. Both prose cells are mandatory — board.py exits if either is
empty. Full text: `docs/parity/BOARD.md`.

An earlier render put the self-test entry in scope.decision's Classified
column (1) while its self-score had no differences — breaking §3.1's
agree+classified+unexplained=items. Fixed: the column counts only
differences of the rendered run; unmatched manifest entries stay listed in
the detail section.

## MANIFEST contents (controls/MANIFEST.json, rewritten by regen)

- `ekos`: repo, commit `8e3c178fc45741c7e2b1576e936646e0c461e75c`, tree
  `8719103d4703b3b43f8294497fa446f7320d7362`, `dirty:false` (regen refuses
  a dirty tree).
- `dump_binary`: path, sha256 `f70e7c7eea16…` (after the store dump was
  added), `source_tree_sha256` (sha256 over the four source files' own
  sha256s, sorted by name), source file list, build log pointer.
- `panels`: sha256 per panel file (decision, conflicts, store).
- `controls`: sha256 per expected + control file (six files).
- `runs`: per panel — items, agree, `reproducible:true` (both runs
  byte-identical), `committed_control:"identical"`, empty moved-items.
- `drift_checks`: all five checkers with exit 0 — scope 17, conflicts 8,
  scope.store 12 (8 tests + the object/world/scoped/names helpers), branch
  3 (W6's), identity 45 (W3's).
- `volatile_fields_stripped:["created_at"]`, UTC `recorded` timestamp.

Two regen runs are recorded: `var/w9/regen-run2.log` (after the stderr-JSON
fix, two panels) and `var/w9/regen-run3-store.log` (three panels, final).

## Task 4: the decision, documented

`read_scope.rs` (all 726 lines, read in ≤150-line slices) is a **black-box
suite over the real binary**: `project()` builds a two-source workspace
through the `ekos` CLI (api + handbook, `secrets/**` and `hr/**` hidden by
the scopes), then one `ekos mcp serve` over stdio answers every
tool×argument-shape grid, and the assertions are about *marker words in
response lines* (and, for hidden-but-asked ids, byte-length equality with an
unknown id's error). None of that is replayable against a library call: it
measures the pipeline + MCP layer + result cache, i.e. exactly what
`run_fixture.py` (not built) is for.

The scoped-store tests (scope.rs:1041-1343) are different: they need a
store, but everything they touch is public API (`Ledger::open`,
`KirObject::new` + `append_*`, `ScopedStore::with_scopes/set_scopes`, the
`KnowledgeStore` trait). So: **second dump, built** —
`control-dump/src/scope_store_dump.rs`. Design points:

- The world is the tests' own `world()` fixture; the dump reproduces the
  `object()` helper exactly (source+sources properties, one evidence record
  per placed object, `text of <name>` fragments), builds with one Ledger
  handle, wraps a second in the ScopedStore — the tests' own `scoped()`.
- Items are ordered step scenarios; results print names (`from->to` for
  edges), counts, booleans; `diff.touched` ids map back to names; the
  fingerprint is asserted only by its equality relations
  (`fingerprint_empty` / `fingerprint_nonempty` /
  `fingerprint_differs_from_last`), never its raw value, so the control does
  not pin serde field order.
- Two transcription errors were caught by the `--expected` run itself (the
  §5.4 mechanism working): my expected had `false` for `get_event` (the test
  asserts `.is_none()`, i.e. true), and my first `differs_from_last`
  implementation updated "last" inside `set_scopes` (the test captures the
  fingerprint *before* the change). Both fixed; 8/8 after.
- Predictions now confirmed by the run: unrestricted `entry_count` 9
  (4 objects + 2 relationships + 3 evidence) and the relationship pair list;
  restricted `entry_count` 2 was the test's own number.
- Not transcribed: `every_store_method_has_a_decision_here` (reads the
  trait's source text; nothing to replay).

## What I could not build

- **`run_fixture.py`** and the leak-suite MCP/CLI panel: the store half of
  RFC 0181 is now measured (scope.store), but the marker-through-every-tool
  half needs the fixture pipeline and a running `ekos mcp serve`. This is
  the highest-value next lane (W5's list said the same).
- **A kernel binary to score**: none exists; score.py's recorded runs are
  the §3.5 self-checks (positive control, planted defect, classification).
  The standing mutant family (`tools/scoreboard/standins/`) is still not
  built — the planted defect so far is one hand-altered line, not a
  stand-in kernel.
- **`classify.py` as a separate tool**: folded into score.py per this
  brief's single-manifest design (`controls/classified.jsonl`, not per-
  kernel manifests; no signed-field enforcement yet — spec §3.4 wants a
  human `signed` field the scorer rejects when empty).
- **The hyperdreggmedia audit's label wording**: not in the repo;
  docs/parity/README.md defines the five labels from §3.6's assignment
  rules and says so.
- **Branch / Identity controls**: W6/W3's panels exist in their own layout
  under panels/{branch,identity}; wiring their dumps is their lanes' work.
  The board carries them as placeholders with real item counts.
- **Verdict files for kernel runs** (spec §5.3's `binary_sha256`/
  `sml_sha1`): score.py writes a reduced verdict json (panel/control/
  candidate/classified sha256s, counts, timestamp) — the kernel-identity
  fields have nothing to point at yet.
