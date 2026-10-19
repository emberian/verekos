# VerEKOS plan (revision 2, 2026-10-19)

Read `../docs/design/VEREKOS-DESIGN-2026-10-19.md` (revision 3) first, then `../docs/design/explorations/00` to `04`. This file names the
lanes, what each owns, and the rules.

## Scoreboard

EKOS's own fixtures, demos and eval datasets (design §4), with EKOS's own output
as the control. Zero unexplained differences. A lane's report states its panel
numbers or states that it has none yet; a green theory is not a number.

## Lanes

| Lane | Deliverable | Owns | Status |
|---|---|---|---|
| A. Invariant census | `notes/A-invariants.md`: every stated invariant as a candidate theorem, with how it is enforced today | notes only | harvested (claude-glm, glm-5.3) |
| B. minidregg mapping | `notes/B-minidregg-map.md`: primitive-to-primitive map, three biggest mismatches, where the world layer should live | notes only | harvested (claude-glm, glm-5.3; its EKOS reads were permission-blocked) |
| C. AFP survey | `notes/C-afp.md`: entries that fit, a recommended session structure, RC1 compatibility notes | notes only | harvested on the second run (claude-grok, grok-4.7; first run permission-blocked) |
| D. Upstream review | `notes/D1-upstream-review.md` (items 1-4, harvested) and `notes/D2-upstream-review.md` (items 5-8, harvested on GLM after two Grok runs hit a context limit); verified drafts in `notes/upstream-issues.md` | notes only | both halves harvested; eleven issues filed upstream (alexeyban/EKOS#10-#20) |
| E. veri7vn lessons | `notes/E-veri7vn-lessons.md`: the sibling pattern distilled as rules | notes only | harvested (claude-glm, glm-5.3-flash) |
| F. Revision system | `notes/F-revision-system.md`: what breadstuffs built, what minidregg kept, what it means here | notes only | harvested (Opus scout) |
| Explorations | `docs/design/explorations/00-04`: the root's vision note; EKOS inside the docworld (Opus); the claim primitive (Opus); the scoreboard design (Sonnet); the amplification catalogue (Sonnet) | design notes only | all five harvested and folded into design revision 3 |
| M0.5. Scoreboard | per `docs/design/explorations/03-scoreboard.md`: panels under `panels/`, a `scoreboard-dump` binary (new, its own Cargo workspace with path deps on a pinned EKOS checkout), the diff classifier with a signed manifest, `docs/parity/BOARD.md`. Root's answers to its §7: the dump binary lives here, not upstream; recompute `content_signature` and self-check against stored signatures rather than ask upstream to export it; events are "no control" for M0.5; the Branch control also runs on SQLite. The scoreboard compares EKOS objects with the claim model's **join view**, not with claims (02 §3 row L) | `tools/scoreboard/`, `panels/` | designed; not started |
| M1a. Reader-local compile | exploration 04 §3-4: a client that reads a friend's own documents with their signed reads, runs EKOS over the copies, answers find / two-hop impact / disagreements with pins that re-check as `same bytes` or `moved`. No node or kernel change | `~/dev/verekos/reader/` (new) | not started; after M0.5 |
| M1b. Slice 1 step 0 | does `transclude` work on a current minidregg Host build (exploration 01 §4, §5 step 0) | one recorded run | not started; can run beside M0.5 |
| M2. Slice 1 | exploration 01 §5: two fixtures, five principals, two rooms, four laws, seven receipts, on a scratch world; lives in `~/dev/verekos/world/` (new Lean project, minidregg as a pinned Lake dependency) | `world/` | not started; after M1b |
| M3. Ledger + Branch kernels | `src/isabelle/ledger/`: `Ledger.thy`, `Branch.thy`, `Ledger_Export.thy`, `ROOT`; a binary reading an EKOS ledger dump. Control dump: `ekos graph export --format ndjson [--as-of <rfc3339>]` (`~/dev/EKOS/ekos/crates/cli/src/commands/graph.rs`), objects and relationships only; evidence records need `ekos ledger audit`/a second path. No `ekos` binary is built in `~/dev/EKOS` yet (`cargo build -p ekos --release` first) | not started | after A, C |
| M4. Scope kernel | `src/isabelle/scope/` plus `scope_noninterference` in `world/` | not started | after M3 |
| M5. Review, Identity, Conflicts kernels | the `Review` kernel is new in revision 3 (status as a fold over authorized reviews) | not started | after M4 |

Scouts (A-F) ran as detached `claude-glm` / `claude-grok` print-mode subprocesses
(claude-fleet was unavailable on 2026-10-19) plus one Opus agent; outputs are
harvested verbatim into `notes/`. Explorations (01-04) ran as Opus and Sonnet
agents writing their own files. Model mix rule from ember: GLM lanes are fine for
breadth; intersperse Sonnet and Opus (and the root's own reading) so the project
does not drift into a lower-intelligence basin. Upstream is quiet for now; the
focus is our own creation, inspired by and integrated with EKOS and minidregg.

## Build wave 1 (launched 2026-10-19 evening)

The Isabelle layer is dropped (ember, 2026-10-19: not a good idea for this project; the
root agreed: the world already has a Lean spine, and the one AFP entry that mattered
turned out to be a one-liner from `ObserverLens.locality`). All kernels are Lean
definitions and theorems in `world/`.

| Lane | Owns | Model | Deliverable |
|---|---|---|---|
| W1 | `world/` | Opus | **done, verified by the root 2026-10-19**: `nice -n 10 lake build` green (2,970 jobs; 77 s first time for minidregg's 18 modules, then seconds); every theorem statement read (`notes/W1-world-build.md` quotes them); no sorry/admit/axiom/native_decide. Deviation accepted: minidregg's own build was stale for `Theory.Hyperdocument`, so the lane cloned minidregg at `dcab86da` under `world/.lake/packages` and symlinked the Mathlib family, writing nothing into minidregg. Honest narrowings: `compilerCannotDecide` holds for schemas that never admit the compiler (an exact identity merge is a compiler-confirmed SameAs in EKOS's own model); `reviewSurvives_put` needs "the new claim is not a review of itself" until a no-cycles rule on pins exists; `diffIsFootprint` is one-directional (diff may over-list). Not yet in the types: pins nonempty, no pin cycles, sorted deduplicated sources. Originally: `World/{Claim,Log,Status,Conflicts,Visible,Minidregg}.lean` with real theorems (append-only, state-is-fold, idempotent put, diff-is-footprint, CompilerCannotDecide, ReviewSurvives, NeedsReviewOnCoreChange, coverage, deny-wins); `notes/W1-world-build.md` |
| W2 | `var/w2/`, `notes/W2-transclusion-and-laws.md` | GLM | **done**: the host binary on disk is from 2026-09-19 (`66d74dd0`), before the `transclude` action (2026-10-01) and the Sep-30 genesis vocabulary, so every journey fails at J0 and transclusion is **untestable until a fresh host is built** (`scripts/build-native-host.sh` in a snapshot; a heavy Lean-native build, not run). Laws: arbitrary Pred JSON installs via `law ID REF @FILE` or `doc new NAME @FILE` (shell.rs:79, :1360-1372); slice-1 step 1 is unblocked. Rebuilt `minidregg-resource-client` (1m29s) under `native/target` |
| W3 | `panels/identity/`, `notes/W3-identity-panels.md` | Grok, then GLM-flash after Grok died on context | **done**: 58 items from 45 identity tests, controls, drift checker (root reran it) | EKOS identity tests as panel items + controls + drift checker |
| W4 | `laws/`, `notes/W4-pred-laws.md` | Grok (drafts), root (checker + memo) | **done**: four laws pass `laws/check.py`; install paths recorded. Originally: L-src/L-obj/L-rev/L-run as client Pred JSON with a checker against the real constructors and slots |
| W5 | `tools/scoreboard/`, `panels/{scope,conflicts}/`, `controls/`, `notes/W5-control-dump.md` | GLM | **done, verified by the root 2026-10-19** (reran both controls: 59/59 and 16/16, byte-identical to the committed control files; both drift checks 0 drifted; a flipped visibility assertion is caught, exit 1, 58/1): `control-dump` workspace (163 crates, 5.4 min cold); scope panel 59 items from 17 tests, 59/59 agree; conflicts panel 16 items from 8 tests, 16/16 agree; drift checkers; partial `controls/MANIFEST.json`. Not built: `score.py`, `board.py`, `regen_controls.py`, the leak-suite family, identity and branch dumps |

Grok lanes run with `CLAUDE_CODE_MAX_CONTEXT_TOKENS=120000` and
`CLAUDE_CODE_AUTO_COMPACT_WINDOW=90000` (set in `~/.local/bin/claude-grok`), because two
earlier Grok lanes died with "Prompt is too long" before Claude Code compacted.

| W6 | `panels/branch/`, `notes/W6-branch-panels.md` | Grok (live test of the corrected wrapper: 250k window, 120k compaction, 16k output) | **done, and the wrapper fix held**: 3 items from the three `merge_branch_*` tests with fixed v5 ids, controls, drift checker (root reran it). Not measured: the relationship loop (no test appends one) |

**Resolved 2026-10-19 evening (ember: "hbox is available, find the latest lane and reuse it"):** no build needed. On hbox, `~/kn-gate/fix/tipbin/` holds a checksummed binary set (host 162 MB, `mini`, verifier, link store, client consent) built from `d94a8817` (2026-10-05), which contains the `transclude` action (strings: transclude=76, authorityCellId=3, authorityCatalogueId=0). hbox root disk is at 94% with 30 GB free, so lanes write only small run roots there and never build or copy trees. `~/dev/minidregg` on hbox is stale (e1bb78d, 2026-08-07, 117 dirty files): not used.

## Build wave 2 (launched 2026-10-19 evening)

| Lane | Owns | Model | Deliverable |
|---|---|---|---|
| W7 | hbox `~/verekos-runs/w7/`, local `var/w7/`, `notes/W7-hbox-transclusion.md` | GLM | **done, verified by the root**: K12T PASS (24/24 transclusion rows; refusals `sourceNotCovered`, `staleOpening`, no-grant placeholders, `moved` for a late joiner), JDV PASS (143/143), J12W FAIL at setup (tipbin `mini` is newer than kn-gate's journey.d: `enroll plan` wants pre-rotation args; unrelated to transclusion). Checksums verified first; run roots 14+29 MB; hbox disk 30 GB free before and after; every W7 PID file dead afterwards. **Slice-1 step 0 is green; the §4 fallback is not needed** |
| W8 | `world/` | the W1 Opus veteran, resumed | **done, verified by the root 2026-10-19**: `lake build` green (2,973 jobs), statements read, axioms standard. `World/WellFormed.lean` (canonical keys: equal iff same schema, subject and source *set*; well-formed log gives well-formed state; acyclicity as a rank, `visible` stabilizes above the rank and `visibleR` is rank-independent; `reviewSurvives_put_acyclic` drops the ad hoc hypothesis), `World/Traverse.lean` (a pending edge is never crossed; an unreviewed hypothesis-initial edge or node is not crossed, which EKOS's missing-status default violates; hop bound monotone; a confirming review only adds under fresh id + pinned at current core + fact-valued decision), `World/Identity.lean` (`Same` is an equivalence; canonical = least of the class, order-free; fuzzy candidates make no link; a compiler-confirmed exact merge takes effect and retracting it restores the old classes, under stated freshness hypotheses). Still open: the rules are hypotheses, not types; no theorem keeps the pin graph acyclic across a write (needs an admission law); rank is a witness, not computed |
| W9 | `tools/scoreboard/`, `controls/`, `docs/parity/`, `notes/W9-scoreboard-machinery.md` | GLM | **done, verified by the root** (`regen_controls.py --ekos` all green: three controls reproducible and identical to committed, five drift checkers 0 drifted, manifest written; `score.py` self-scores 59/16/8 with 0 unexplained and an altered line reported as unexplained; `board.py` renders `docs/parity/BOARD.md`): `score.py` + `controls/classified.jsonl`, `board.py` + `panels/LABELS.json`, `regen_controls.py`, and the `scope.store` dump (ScopedStore over a real temp SQLite ledger, 8 items) built after deciding the leak suite itself is a black box over the binary |
| W11 | `panels/impact/`, `notes/W11-impact-panels.md` | Grok (bounded) | **done, verified by the root** (drift 15 functions, 0 drifted): 26 items from the Runtime traversal tests with fixed ids and `expect_from_test` |
| (W3, W6) | `panels/identity/`, `panels/branch/` | GLM-flash, Grok | done (see wave 1) |

## Build wave 3 (launched 2026-10-19 night)

| Lane | Owns | Model | Deliverable |
|---|---|---|---|
| root | `var/ekos-build/` | — | one `cargo build -p ekos --release` of EKOS at 8e3c178 (the slice-1 and fixture lanes both need the binary; one build, not two) |
| W12 | `tools/scoreboard/control-dump/src/{identity,branch,impact}_dump.rs`, `controls/*.control.jsonl`, `notes/W12-dumps.md` | GLM | **done, verified by the root** (regen: 58/58, 3/3, 26/26 reproducible and identical; six drift checkers clean). The lane died with "Prompt is too long" (GLM can hit it too) after committing the dumps; the root committed its last edits and wrote the memo |
| W14 | `world/` | the Opus veteran, resumed again | **done, verified by the root** (`lake build` green, 2,975 jobs; statements read; axioms standard on every theorem of `Admission.lean` and `Document.lean`). The root's law was wrong: retract-then-re-put could close a cycle; the lane added "re-putting an id never raises its recorded rank". Proved: an admissible log yields a ranked state with the computed rank (`ranked_of_admLog`, `rankOf_some_of_admLog`), admissibility decidable, self-pins and absent pins refused. `Document.lean`: the `ekos/object/v1` cell (header, properties, window, evidence containers with snapshot pins, premise links, per-edge containers), claim→cell→claim up to pin order and cell→claim→cell exact, atom pins preserved both ways; K12T's real names (`sourceNotCovered`, `staleOpening`, placeholder, `moved`, same bytes); `visibleR_iff_readable` and `visibleR_iff_room` under nonempty source-only pins. Open: only the object cell is modelled; grants and revisions are plain functions (no heights, no audience rosters); re-ranking dependents on re-put |
| W15 | `panels/redact/`, `notes/W15-redact-panels.md` | Grok (bounded) | **done, drift rerun by the root** (16 fns): 26 items from 16 redaction tests |
| W16 | `panels/ekl/`, `notes/W16-ekl-panels.md` | Grok (bounded) | **done, drift rerun by the root** (58 fns): 50 parser + 33 interpreter items |
| W17 (after the binary) | `slice1/`, hbox `~/verekos-runs/slice1/` | Opus | **slice 1** (exploration 01 §5): import the two fixtures, compile with the real `ekos`, map the ndjson to `mini` commands, install the four laws, collect the seven receipts |
| W18 | `tools/scoreboard/run_fixture.py`, `panels/ledger/`, `controls/ledger.*`, `notes/W18-fixture-pipeline.md` | GLM | **done**: six-stage pipeline with the release binary; ecommerce 6 tables / 6 FKs, northwind 13 / 13, EKOS's own counts reproduced; a second fresh-workspace ecommerce run is content-identical (EKOS#10 is invisible to the export; `ledger audit` shows the differing run_id/source_artifact_id). Not registered in regen (needs a control-dump subcommand or a new runner kind) |

## Build wave 4 (launched 2026-10-19 night)

| Lane | Owns | Model | Deliverable |
|---|---|---|---|
| W19 | `world/` | the Opus veteran | **done, verified by the root** (`lake build` green, 2,977 jobs; 31 theorems in `Shapes.lean` and `CarryForward.lean` on standard axioms). All six remaining document shapes with round-trip and pin-preservation theorems; a re-import of an unchanged file changes nothing; review documents append-only; the compiler cannot attest its own determinism; `not_current_after_unemit` and `history_kept` for the manifest. **Design correction, proved:** the review's core must be the conflict header's *revision*, not the signature: with the signature as core, A→B→A makes `World.Status` report the old decision while the pin says `moved` and EKOS stays open (`core_sig_diverges`); with the revision as core they agree exactly (`status_core_rev_agrees`, `pin_agrees_with_ekos`, EKOS's `carry_forward` modelled line by line). Design §3 wording to be amended after the reviewer's pass |
| W20 | `tools/scoreboard/control-dump/src/ledger_dump.rs`, `controls/ledger.*.versions.control.jsonl`, regen `LEDGER_REGISTRY`, `notes/W20-ledger-dump.md` | GLM (compaction env set; it finished) | **done, regen rerun by the root**: a read-only ledger dump (per object: versions, a locally recomputed content signature per version, evidence id lists; totals; diff), both fixtures byte-identical across runs. **EKOS#10 reproduced**: `ekos clean` + recompile on a byte-identical copy of the ecommerce workspace took all 6 Tables from 1 to 2 versions (entries 28→52, evidence 14→26) while a signature computed without the evidence list stayed byte-equal, so fresh v4 evidence ids are the only payload change; classified `ekos_defect` in `controls/classified.jsonl` and score.py shows 1 unexplained → 0 after classification. Incident, self-cleaned: an early driver without `cd` wrote a scratch `.ekos` at the repo root, removed by the lane as its own creation |
| (W17) | `slice1/` | Opus | still running |

Then M1a, the reader-local compile, against the world W17 leaves on hbox.

## Rules

- No `sorry`, `oops`, `skip_proof`, new axioms. Read theorem statements; a
  tautology is not progress.
- A recognizer, parser, fetch or model call is untrusted by construction and
  says so.
- One Isabelle: `/Applications/Isabelle2026-RC1.app`. The AFP snapshot is
  `~/isabelle/afp-2026-05-29` and is not yet registered or checked against RC1.
- Builds go through one lock, as in veri7vn (`tools/dev/check-native` there; copy
  the pattern). On hbox, `swarm-build`.
- Never kill by pattern; PID file or nothing. Never `git stash`, `git reset`,
  `git add -A`. Named files. Unsigned commits are fine.
- Disk pressure: stop writing, report, wait.
- Commit named files often; torn commits are fine. **Push often** (`origin` is `emberian/verekos`, branch `dev`): after every harvest or verification, not once per session.
- Plain words, for a reader who is not a software engineer: what it does, what
  it proves, what it cannot do yet.
