# R1: review of the working tree, 2026-10-19 night

Lane R1 (Opus), reviewer and fixer. Read: README, PLAN, the design, all six
explorations' heads and the parts that set paths or claims (01 §5, 03 in full,
04 §3-6), every memo's summary (W1 in outline plus its vacuity and follow-up
sections), every `world/World/*.lean` statement (tactic lines skipped), the
scoreboard tools, every panel, control and drift record, `laws/`, and `slice1/`
as it stood. Ran read-only: `score.py`, `board.py`, `laws/check.py`, all eight
drift records. No lake or cargo builds.

**Summary.**
1. The project's central loop is not closed yet: the Lean model has about 150
   theorems and has never answered a panel item, and the board's "agree"
   numbers are EKOS scored against itself. The board now says so, and a new
   column shows the number that does measure something (EKOS reproducing its
   own tests' assertions, 170 of 170). Closing the loop is lane B of
   `docs/design/explorations/05-next-lanes.md`.
2. Three hazards in the scoreboard: a planted self-test difference sits in the
   real classification manifest and would silently excuse a real candidate
   making the same mistake (S1); the ledger versions control can only be
   regenerated from a git-ignored workspace and embeds random ids (S3); and
   `score.py` let a `verekos_defect` count as explained (fixed).
3. Two model claims rest on names nobody checks: who authored a receipt and
   who verified a replay are data in the Lean model, so "the compiler cannot
   decide" and "the compiler cannot attest its own determinism" hold of the
   labels, not of signers (S4).
4. The documents had fallen a day behind the code: README said nothing was
   built, the design and plan still described Isabelle kernels, the milestone
   table said built things were not started, and the design's "one
   carry-forward definition" was contradicted by W19's own theorem. All
   corrected (design revision 3.1).
5. Layout sprawl is real but bounded: four ways to name a panel's inputs,
   expected files in three places and three shapes, three drift checkers. One
   checker now reads every record; the file moves are planned, not done, so
   no live reader breaks.

Severity: **S** (a number or a guarantee could be wrong), **M** (a document or
tool misleads, or a seam is unguarded), **L** (hygiene).
Status: **done** (commit named), **proposed** (owner named), **live lane**.

---

## 1. Findings

### S1. A planted self-test difference is in the real classification manifest

`controls/classified.jsonl:1` classifies, as `non_goal`, the difference
`{visible:false}` → `{visible:true}` on `default_deny_hides_everything_without_a_rule#1`.
It was W9's planted-defect self-test. Classifications are keyed by
sha256(panel, item, control, candidate), so a real candidate that makes
exactly that mistake (a default-deny scope showing an object) would be
counted as explained and the run would pass. The entry's own `signed` field
says it is not a kernel verdict, but `score.py` does not read `signed`.
**Proposed** (owner: the scoreboard lane; `classified.jsonl` was W20's
file): move the line to a self-test manifest under `var/w9/score-selftest/`
and pass that file explicitly when re-running the self-test. Until then, no
candidate should be scored against `controls/classified.jsonl` on
`scope.decision`.

### S2. No candidate is scored; "agree" was EKOS against itself

`tools/scoreboard/board.py` (before `7263759`, line 112) scored each control
against itself and printed the result in the Agree column, under a header
counting "8 measured rows" (two of which had no item-keyed control). Nothing in
`world/` runs on any panel. **Done** (`7263759`, `56430c7`): the board's header
says no candidate exists, a **Test asserts** column shows the control
reproducing the transcribed test assertions (read from the regen runs in
`controls/MANIFEST.json`), rows are counted by kind. **Proposed**: lane B
(exploration 05).

### S3. The ledger versions control cannot be regenerated from a clean checkout

`tools/scoreboard/regen_controls.py:89-96` (`LEDGER_REGISTRY`) dumps
`var/w18/ecommerce/ws` and `var/w18/northwind/ws`, which are git-ignored
scratch. The committed control (`controls/ledger.ecommerce.versions.control.jsonl`)
includes every version's evidence id list and signatures computed over it,
and those ids are random v4 (EKOS#10), so a fresh pipeline run produces a
different control. Anyone who clears `var/` breaks regen, and a fresh clone
cannot reproduce the control at all. **Proposed** (lane C half 2): keep counts
and the no-evidence signatures in the committed control, drop the v4 ids, and
keep the EKOS#10 demonstration as the classified difference it already is.

### S4. Authority in the model is a label in the receipt

`World/Status.lean:60` admits a review when `mayDecide r.author.1 s`, where
`r.author` is a field of the receipt. `compilerCannotDecide` (Status.lean:138)
assumes every appended receipt is *labelled* compiler; nothing says the label
is the signer. Likewise `replayedDeterministic` (Shapes.lean:500) compares the
attestation's `verifier` name with the run's `compiler` name, both data, so
`not_replayed_by_compiler` (Shapes.lean:508) is the definition unfolded: a
compiler that writes an attestation naming someone else earns the label. Both
are true in minidregg only because a receipt's author is the key that signed
it. **Done** in the design (§10 says these names are data in the model).
**Proposed** (world lane): either a hypothesis `author = signer` stated once
and threaded through, or an `Op` that carries the signer separately from the
payload. Lane B's `check laws` must take the author from the signature, not
the payload.

### S5. The design's "one carry-forward definition" was false as written

Design §2 said status-as-a-fold replaces EKOS's three `carry_forward`s. W19
proved that with the core a digest of the payload, A→B→A brings the old review
back while EKOS stays reopened (`core_sig_diverges`, CarryForward.lean:297);
agreement needs the header *revision* as core (`status_core_rev_agrees`,
:275). A revision is minted by the world, not computed from the payload, so
`World.Status.status` (Status.lean:78, which reads `c.core reg` from the
payload) cannot express it; only `statusAt` with the digest supplied can.
**Done**: design 3.1 §2, §3 and exploration 01's banner. **Proposed** (world
lane): a schema core that may read the claim's pin revisions as well as its
payload, so `status` itself agrees with EKOS.

### S6. `score.py` let a `verekos_defect` explain a difference

`score.py` (before `96da780`, lines 131-140) counted every classified
difference as explained; exploration 03 §3.3 and `docs/parity/README.md` say a
`verekos_defect` stays red. **Done** (`96da780`): counted in its own field,
exit 1. Checked with a planted flip.

### M1. Documents a day behind the code

- `README.md:29` "Nothing is built", `:45-48` Isabelle/HOL kernels exported
  to Standard ML (at `3e78c89`). **Done** (`25e8ea2`).
- Design §4 and §5 described Isabelle kernels, AFP imports, MLton, the "seam
  between two provers"; §3 fed "the Isabelle `Scope` kernel"; §10 "That
  anything here is built". **Done** (`46c5f15`, revision 3.1; §5 now lists
  the three seams no theorem covers).
- `project/PLAN.md:23,25,26` said M0.5, M1b and M2 were not started; `:27-29`
  pointed M3-M5 at `src/isabelle/`; `:100-103` named an Isabelle install and a
  build lock that does not exist here; the W6 row (`:58`) sat after a
  paragraph, outside any table. **Done** (`04fe930`).
- Explorations 00, 01, 03 and memo C read as specs with stale paths and
  Isabelle steps. **Done** (`cae7bd4`, banners; the texts stay as records).
- `docs/parity/BOARD.md` showed `redact.unit` and `ekl.grid` as "no panel"
  though W15 and W16 had committed 26 and 83 items. **Done** (`7263759`).
- The assurance labels named HOL, QuickCheck and the Lean/Isabelle seam, and
  were written twice. **Done** (`7263759`, `56430c7`, one copy in
  `panels/LABELS.json`, printed by the board).

### M2. Two different laws are both called "the admission law"

`world/World/Admission.lean` is pin acyclicity (pins present, no self-pin,
rank never rises). `laws/L-*.json` are authorship and a transclusion count at
birth. Neither is derived from the other, and PLAN's W14 row calls the first
"the admission law". **Done** (design §5 names it as a seam). **Proposed**:
call the Lean one the pin law in prose; lane B's `check laws` is the first
place both meet real receipts.

### M3. L-rev's "append-only" does not forbid detaching an earlier decision

`laws/L-rev.md:16`: a review mutate needs `content/atom-edits = 0` and
`content/tombstones = 0`, but `content/element-edits`, `content/unlinks` and
`content/unmarks` are unconstrained, so a reviewer could plausibly re-place or
unlink an earlier decision container without editing an atom.
`World.Shapes.append_prefix` assumes append-only. **Proposed** (laws are
ours, but W17 is installing them live): once W17 records the slot counts of
a legitimate review write, add `content/element-edits = 0` and
`content/unlinks = 0` if that write has zeros there, and add a refusal
receipt for a detach. Not changed now, so slice 1's installed laws and the
files agree.

### M4. Slice 1's evidence pins and ids are the mapper's, not EKOS's or minidregg's

`slice1/mapper.py:344` (GUESS: EKOS table evidence names the file, so the
mapper locates the statement by structural key), `:358` (room by first
defining source), `:487` (edges cite the referencing statement), and `num`
(`:43`) derives ids as truncated SHA-256, not minidregg's `deriveIdentifier`,
which `World.Minidregg` instantiates. So receipt R1 ("a birth with a pinned
transclusion") measures the mapper's choice, and `claimId_injective` does not
describe slice-1 ids. **Done** (design §8 M2 row says so). **Live lane** (W17:
say it in the memo; each GUESS is an EKOS evidence-location issue or a schema
gap, as exploration 01 §5 asks).

### M5. Slice 1's driver lagged its runs

Nine `slice1/` files (`mapper.py` alone is 718 lines) were untracked for most
of this review while the lane ran on hbox; W17 committed them as `fc8c7e1`
near the end, and the later steps' scripts (`s3-refusals.sh` through
`s6-reader.sh`, `replay.sh`) were still untracked when this memo was written.
A crash loses them; "push often" is a rule. **Live lane** (W17).

### M6. The EKOS release binary was built inside EKOS's tree

`var/ekos-build/build.log` shows `cargo build -p ekos --release` compiling in
`/Users/ember/dev/EKOS/ekos`, and `run_fixture.py:424` and
`slice1/ekos-compile.sh:7` default to `/Users/ember/dev/EKOS/ekos/target/release/ekos`.
The target dir is git-ignored, so EKOS's tree is clean, but anyone building
EKOS at another commit silently replaces the binary every control depends on
(the sidecars record its sha256, so a compare would catch it; nothing
prevents it). **Done** (CLAUDE.md: the next build sets
`CARGO_TARGET_DIR=…/verekos/var/ekos-build/target`). **Proposed**: copy the
current binary there and point the two defaults at it.

### M7. Panel layout: one idea, four spellings

Inputs: `panels/scope/decision.jsonl`, `panels/conflicts/unit.jsonl`,
`panels/identity/identity.unit.jsonl`, `panels/<family>/items.jsonl`.
Expected: `controls/<panel>.expected.jsonl` (scope, conflicts),
`controls/impact.expected.jsonl` and `controls/redact.expected.jsonl`
(family, not panel, names), `controls/ekl.expected.jsonl` (two panels),
`panels/identity/controls/identity.unit.controls.jsonl` (an expected file
named "controls"), `panels/branch/controls/expected.jsonl`. Three expected
shapes (`assert`; `expect` + `expect_from_test`; flat fields). Drift records
under `panels/transcribed/` for three panels, beside the panel for the rest.
Exploration 03 §5.1's planned flat layout was never followed. **Done**:
`tools/scoreboard/README.md` (`ef8c794`) has one table naming every file and
marking the exceptions; CLAUDE.md states the target shape for new panels.
**Proposed** (lane C half 2, with the full move list): not moved now, because
`regen_controls.py`, `controls/MANIFEST.json` and the generators all read
these paths and the regen file belonged to a live lane.

### M8. Three drift checkers, three interfaces, and one false docstring

`panels/transcribed/drift_check.py --ekos --record` (six records),
`panels/identity/drift.py` (no arguments, hard-coded EKOS path, flat record,
auto-records on first run so its first check cannot fail),
`panels/branch/drift.py --ekos [--populate]` (hashes from `#[test]`).
Identity's docstring says it hashes from `#[test]`; its match
(`panels/identity/drift.py:60`) compares the attribute without indentation, so
it never fires and the hashes start at `fn`. **Done** (`6aec0eb`, `542dd58`):
`drift_check.py` reads all three record shapes, reproduces all eight records
(17, 12, 8, 15, 16, 58, 45, 3 functions), and with `--panel` also fails when a
panel cites a test the record does not pin; three planted defects caught;
identity's docstring corrected. **Proposed** (scoreboard lane): point the
`identity` and `branch` REGISTRY entries at `drift_check.py --panel` and
delete the two per-lane checkers.

### M9. Lean statements that need a second look (read adversarially)

All build on standard axioms (root-verified); these are about what the
statements say.
- `World/Log.lean:44`: `state L t` replays receipts with `tx ≤ t` in *list*
  order, and `write` neither assigns nor checks `tx`. Design P2's "a fold of
  the log prefix" is that only when `tx` increases along the list; no
  theorem or `write` rule says so. The log theorems are true as stated.
  **Proposed** (world lane): a `write` that assigns `tx = last + 1`, or the
  monotone hypothesis stated once.
- `World/Visible.lean:57`: an explicitly allowed id is visible when none of its
  pins is allowed (only a denial hides it), even with zero pins
  (`unpinned_hidden` needs the id not allowed). Whether EKOS's object-id
  allow rule behaves the same is unchecked; lane B's `scope.decision` run will
  answer it.
- `World/Conflicts.lean:110-121`: `coverage` and `soundness` are the two
  directions of `mem_detect`, which restates `detect`'s definition. That is a
  fine specification; it says nothing about EKOS until `detect` is scored on
  `conflicts.unit`. `detect` takes a `Finset` of claims, not the log's state or
  the manifest's current set; no theorem connects them.
- `World/Admission.lean:94`: a retract is always admissible, so a premise can
  be retracted under claims that pin it. Visibility fails closed (an absent
  premise is not allowed), but `Ranked` and `status` say nothing about the
  dangling pin.
- Nothing in `world/` imports `ObserverLens`, `locality` or
  `transclusion_pinned`; `scope_noninterference` and the one-line session
  isolation theorem of design §3 do not exist. The carry-forward agreement is
  over a model of the header (`compileHeader`), whose "rewrite only when the
  signature changed" is the compiler's obligation, not the host's. **Done**
  (design 3.1 says all of this).
- Theorem counts in prose disagree: the W1 memo's "31 load-bearing", the
  root's "94", tonight's 159 `theorem` declarations (`grep -c '^theorem'`).
  **Proposed**: counts come from a one-line script in the memo, never from
  prose.

### M10. Commit trailers do not record which model wrote the work

The model-mix rule needs provenance, but lanes on GLM and Grok commit with the
root's trailer (for example W20's `61ee1a1`, written by GLM, ends
"Claude Fable 5.1"). PLAN records the model per lane, which is enough for
now. **Proposed**: lane briefs give each lane its own trailer. (This lane's
commits carry Opus 5.5, the model that wrote them.)

### L1. Hygiene

- `__pycache__/` untracked in two places, not ignored. **Done** (`eff9e95`;
  both removed as generated).
- No CLAUDE.md or AGENTS.md for lanes. **Done** (`32706f1`).
- `board.py --out` outside the repo crashed after writing. **Done**.
- `score.py`'s verdict reported the file stem ("items") as the panel. **Done**.
- `drift_check.py` documents "inside `mod tests`" but matches the first
  `    fn name(` anywhere in the file. Harmless today (all pass); noted.
- Memo A's summary says 42 invariants; its tables have about 56 rows; the
  design says 60. Low; the design's citation is close enough.
- `World/Shapes.lean`'s header notes `notes/W17-slice1.md` did not exist, so
  the shapes follow exploration 01, not what the client was shown to express.
  Recheck when W17's memo lands.

## 2. Parsimony

**If every day accreted like today**, in a month this repo holds about 600
memos, thirty design revisions with banners on banners, a PLAN of wave tables
thousands of lines long, a drift checker and a file-naming scheme per lane,
and a board with forty rows of EKOS scored against itself beside 1,500
theorems that never ran on an input. Each piece would be individually
defensible, and the project's one claim (the model and EKOS agree, item by
item, and every difference is explained) would still be unmeasured.

**The attractor** is one loop, and everything else is history:

    panel item ──► EKOS control ──► Lean definition (the one the theorem is about),
                                    run on the same item ──► score ──► board row
                                    whose label is earned by that run

A theorem counts when its definition answers a panel; a memo counts when it
moved a board row or a receipt; PLAN is the current lanes and a link to the
board. Exploration documents are dated records that never need updating,
because nothing reads them as specs.

**Three deletions or merges toward it**, the ones in this lane's reach done:
1. **One drift checker.** Done for capability (`drift_check.py` reads every
   record and checks coverage); the two per-lane checkers can be deleted the
   moment the REGISTRY points at it (one line each, scoreboard lane).
2. **One copy of each definition.** Done for the assurance labels (were in
   two files, had drifted once). Next: memos should cite theorem names and
   lines, not paste statements; the W1 memo quotes every statement (1,146
   lines) and those quotes rot as the Lean moves.
3. **PLAN as a dashboard, not a diary.** Proposed (the root edits PLAN live):
   move the wave tables to `project/LOG.md` once a wave is fully verified,
   leaving PLAN with the milestone table, the live lanes and the rules
   pointer.

## 3. What changed, by commit

| Commit | Change |
|---|---|
| `eff9e95` | `.gitignore`: bytecode, `.lake`, editor litter; removed two `__pycache__` dirs |
| `32706f1` | `CLAUDE.md` for lanes, `AGENTS.md` → it |
| `25e8ea2` | README: honest state, no Isabelle |
| `96da780` | `score.py`: `verekos_defect` stays red; envelope panel name |
| `7263759` | board: no-candidate header, Test asserts column, redact and EKL rows, Lean labels |
| `6aec0eb` | `drift_check.py`: every record shape, `--panel` coverage |
| `542dd58` | identity `drift.py` docstring |
| `ef8c794` | `tools/scoreboard/README.md` consolidated |
| `46c5f15` | design revision 3.1 |
| `04fe930` | PLAN: statuses, no Isabelle, W6 row, R1 lane |
| `cae7bd4` | banners on explorations 00, 01, 03 and memo C |
| `56430c7`, `6a9ae94` | one copy of the assurance labels; design-target wording |
| `ac189b6` | `docs/design/explorations/05-next-lanes.md` |

## 4. Left for others

- **Live lanes:** W17 (commit `slice1/`; report the mapper's guesses; record a
  legitimate review write's slot counts for M3). The world lane (S4 author =
  signer; S5 a core that can read revisions; M9 tx monotonicity). Nothing in
  `world/`, `slice1/` or W20's files was edited.
- **Scoreboard lane:** S1 (move the self-test classification), S3 (a
  reproducible ledger control), M8 (switch the REGISTRY to `drift_check.py`,
  delete two checkers), lane C of exploration 05.
- **Root:** pick lane B next; it is the one that makes the board measure
  VerEKOS. Decide whether `check/` may link Mathlib.
