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
- Plain words, for a reader who is not a software engineer: what it does, what
  it proves, what it cannot do yet.
