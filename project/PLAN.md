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
| W3 | `panels/identity/`, `notes/W3-identity-panels.md` | Grok, then GLM-flash after Grok died on context | EKOS identity tests as panel items + controls + drift checker |
| W4 | `laws/`, `notes/W4-pred-laws.md` | Grok (drafts), root (checker + memo) | **done**: four laws pass `laws/check.py`; install paths recorded. Originally: L-src/L-obj/L-rev/L-run as client Pred JSON with a checker against the real constructors and slots |
| W5 | `tools/scoreboard/`, `panels/{scope,conflicts}/`, `controls/`, `notes/W5-control-dump.md` | GLM | **done, verified by the root 2026-10-19** (reran both controls: 59/59 and 16/16, byte-identical to the committed control files; both drift checks 0 drifted; a flipped visibility assertion is caught, exit 1, 58/1): `control-dump` workspace (163 crates, 5.4 min cold); scope panel 59 items from 17 tests, 59/59 agree; conflicts panel 16 items from 8 tests, 16/16 agree; drift checkers; partial `controls/MANIFEST.json`. Not built: `score.py`, `board.py`, `regen_controls.py`, the leak-suite family, identity and branch dumps |

Grok lanes run with `CLAUDE_CODE_MAX_CONTEXT_TOKENS=120000` and
`CLAUDE_CODE_AUTO_COMPACT_WINDOW=90000` (set in `~/.local/bin/claude-grok`), because two
earlier Grok lanes died with "Prompt is too long" before Claude Code compacted.

| W6 | `panels/branch/`, `notes/W6-branch-panels.md` | Grok (live test of the corrected wrapper: 250k window, 120k compaction, 16k output) | `merge_branch_*` tests as panel items with fixed ids, controls, drift checker |

**Open decision for ember:** build a fresh `minidregg-host` (heavy; hbox with `swarm-build`, or a local snapshot build) so transclusion can be tested, or take exploration 01 §4's fallback (evidence as a `link` with a `.range` target plus revision in the meta atom) for slice 1.

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
