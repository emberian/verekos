# VerEKOS

**EKOS's sibling, with a proof spine.**

[EKOS](https://github.com/alexeyban/EKOS) compiles what an organisation already has
(schemas, code, pipelines, documents, commit history) into a ledger of objects,
relationships and events, each carrying the evidence it was derived from, and
lets people and AI agents read that ledger without touching the original systems.
It promises a short list of things about that ledger: it only grows; every
conclusion points at evidence; the reader is read-only; a reader allowed to see
part of a project cannot learn about the rest; sources that disagree are kept and
flagged; the compiler is deterministic; secrets never enter. Today those promises
are kept by tests, by guard tests that read the source code of other tests, and
by review.

VerEKOS states those promises as theorems about a model, proves them, and runs
the proved model against EKOS's own fixtures so that every difference between the
two is explained. The aim, as with
[veri7vn](../o7vn/README.md) for Oracle7, is a true sibling: proofs and
counterexamples flow back to EKOS as guard tests, RFC amendments and bug
reports; EKOS's fixtures, evaluation datasets and connectors flow to VerEKOS as
its scoreboard and its untrusted front ends.

Design, dated 2026-10-19: [`docs/design/VEREKOS-DESIGN-2026-10-19.md`](docs/design/VEREKOS-DESIGN-2026-10-19.md).
Plan and lanes: [`project/PLAN.md`](project/PLAN.md).

## Honest state (2026-10-19, night)

Built, with numbers:

- **A Lean model** in `world/`: claims, receipts, status computed from reviews,
  visibility with deny-wins, conflicts with coverage, identity as an overlay,
  traversal that crosses only facts, an admission law that keeps the pin graph
  acyclic, and the seven document shapes of exploration 01. It builds; no
  `sorry` or new axiom. It is a model of VerEKOS's own design: nothing yet
  connects it to minidregg's kernel theorems beyond shared carrier types, and
  nothing yet runs it on a panel. `world/README.md` says what each file proves
  and what it does not.
- **A scoreboard** (`tools/scoreboard/`, `panels/`, `controls/`,
  `docs/parity/BOARD.md`): EKOS's own library functions answer 170 items
  transcribed from its own tests (scope, conflicts, identity, branch, impact),
  each reproducing the test's assertions; two fixtures go through the real
  `ekos` binary with EKOS's stated counts reproduced; EKOS#10 is reproduced and
  classified. 109 more items (redaction, EKL) have expected outcomes but no
  control yet. **No VerEKOS candidate is scored yet**: every "agree" on the
  board is EKOS against itself.
- **Slice 1** (in progress, `slice1/`): EKOS output landed as minidregg cells on
  hbox under four laws (`laws/`); transclusion itself was shown working on a
  current host (24/24 and 143/143 journey rows, `notes/W7-hbox-transclusion.md`).

A claim about behaviour comes with a number or is not made.

## The shape, in one paragraph

Two layers. **The ledger is a world**: objects, relationships and evidence are
documents, links and pinned transclusions of source ranges; a commit is a
proposed change that minidregg admits or refuses against laws (evidence
required, only the compiler writes compiled cells, only named reviewers write
reviews); a reader sees an authorized view and nothing else. This is the
contract [minidregg](../minidregg/README.md) already provides for documents,
so the design's first question was whether EKOS is a natural minidregg world
rather than a new kernel (so far: yes, with no kernel change). **The
compiler's decisions are small pure functions with theorems**: status, read
scope, identity, conflicts, impact, written in Lean in `world/` (an Isabelle
layer was planned and dropped on 2026-10-19). What turns text into typed input
(SQL parsing, document extraction, any model call, the slice-1 mapper) is
untrusted and says so, as in veri7vn.

Lanes and rules for agents: [`CLAUDE.md`](CLAUDE.md).
