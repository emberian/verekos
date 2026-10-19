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

## Honest state

Nothing is built. This repository holds a design and the scout memos it was
written from (`notes/`). No theory has been checked, no binary exported, no
fixture run. A claim about behaviour will come with a number or will not be made.

## The shape, in one paragraph

Two layers, two different kinds of guarantee. **The ledger is a world**: objects,
relationships and evidence are documents, links and pinned transclusions of source
ranges; a commit is a proposed change that a kernel admits or refuses against
laws (evidence required, redaction, determinism by re-execution, review by a
human-held capability); a reader sees an authorized view and nothing else. This is
exactly the contract [minidregg](../minidregg/README.md) already provides for
documents and hosted applications, so the first question the design answers is
whether EKOS is a natural minidregg world rather than a new kernel. **The
compiler's decisions are kernels**: identity merging, conflict detection, the
read-scope decision, impact closure, point-in-time reconstruction and the query
language are small pure functions with theorems, written in Isabelle/HOL where
the Archive of Formal Proofs already has the pieces (information-flow security,
stratified Datalog, transitive closure, interval calculus, canonical JSON), and
exported to Standard ML binaries that run beside EKOS on the same inputs. What
turns text into typed input (SQL parsing, document extraction, any model call) is
untrusted and says so, as in veri7vn.
