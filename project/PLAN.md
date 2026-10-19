# VerEKOS plan (revision 1, 2026-10-19)

Read `../docs/design/VEREKOS-DESIGN-2026-10-19.md` first. This file names the
lanes, what each owns, and the rules.

## Scoreboard

EKOS's own fixtures, demos and eval datasets (design §4), with EKOS's own output
as the control. Zero unexplained differences. A lane's report states its panel
numbers or states that it has none yet; a green theory is not a number.

## Lanes

| Lane | Deliverable | Owns | Status |
|---|---|---|---|
| A. Invariant census | `notes/A-invariants.md`: every stated invariant as a candidate theorem, with how it is enforced today | notes only | scout running (claude-glm, glm-5.3) |
| B. minidregg mapping | `notes/B-minidregg-map.md`: primitive-to-primitive map, three biggest mismatches, where the world layer should live | notes only | scout running (claude-glm, glm-5.3) |
| C. AFP survey | `notes/C-afp.md`: entries that fit, a recommended session structure, RC1 compatibility notes | notes only | scout running (claude-grok, grok-4.7) |
| D. Upstream review | `notes/D-upstream-review.md`: ranked findings where EKOS's code falls short of its stated invariants, each with a proposed upstream change | notes only | scout running (claude-grok, grok-4.7) |
| E. veri7vn lessons | `notes/E-veri7vn-lessons.md`: the sibling pattern distilled as rules | notes only | scout running (claude-glm, glm-5.3-flash) |
| M1. Ledger kernel | `src/isabelle/ledger/`: `Ledger.thy`, `Ledger_Export.thy`, `ROOT`; a binary reading an EKOS ledger dump. Control dump: `ekos graph export --format ndjson [--as-of <rfc3339>]` (`~/dev/EKOS/ekos/crates/cli/src/commands/graph.rs`), objects and relationships only; evidence records need `ekos ledger audit`/a second path. No `ekos` binary is built in `~/dev/EKOS` yet (`cargo build -p ekos --release` first) | not started | after A, C |
| M2. Scope kernel | `src/isabelle/scope/` | not started | after A, C |
| M5. The EKOS world | a law package and schema against minidregg's `Theory/Hyperdocument*.lean`; location decided by B | not started | after B |

Scouts run as detached `claude-glm` / `claude-grok` print-mode subprocesses
(claude-fleet was unavailable on 2026-10-19). Briefs and PID files are in the
session scratchpad; outputs are harvested verbatim into `notes/`.

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
