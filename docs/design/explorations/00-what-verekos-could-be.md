# 00. What VerEKOS could be

The root's own note, 2026-10-19, written while four design lanes (01 to 04)
explore the detailed angles. This is the picture I would want in my head
before reading them. It makes claims about intent, not about anything built.

## Three things it could be, in rising order of ambition

**A checker.** The modest version: a set of small verified binaries that read
an EKOS ledger dump and say whether EKOS kept its promises on that ledger.
`verekos check scope` takes the leak suite's inputs and a scope and prints the
visible set; `verekos check ledger` replays the fact log and prints every id
whose `object_at` disagrees with EKOS's; `verekos check identity` prints the
merge groups. Each disagreement is an upstream issue with a counterexample, as
eleven already were today without any binary at all. This version needs only
the Isabelle kernels of design §2.2 and the scoreboard of §4. It is useful on
its own and it is how veri7vn started.

**A sibling.** The version the README promises: the same compiler, re-derived
from theorems, with EKOS's fixtures as the scoreboard and EKOS's connectors as
untrusted front ends. Components flow both ways: EKOS adopts a guard test or a
read trait that the model made obvious; VerEKOS adopts a fixture or an eval
dataset as a panel. The compiled ledger is the same shape in both, so a
VerEKOS kernel binary can sit behind an `ekos` subcommand and an EKOS connector
can feed a VerEKOS world.

**A world that knows itself.** The version ember is actually curious about.
minidregg is a shared world of documents, rooms, grains and residents, with
authority, receipts and history proved in Lean. Today that world can say *who*
changed *what* and *whether it was allowed*. It cannot say what anything
*means*: which grain depends on which document, which `.obend` package calls
which, which two documents in a room disagree about a stated fact, what a
resident's note was anchored to and whether that anchor still holds. A
knowledge compiler inside the world supplies exactly that layer, and the
world supplies what EKOS approximates with grep-tests and conventions:
principals instead of a session flag, admission laws instead of three entry
points remembering to redact, a lens instead of a read-only promise, a
`ConflictRecord` instead of a printed merge report, a pinned transclusion
instead of a freshness manifest. Neither system has the other's half.

## The one record

If the third version is the goal, the design question is not "how do we port
EKOS's crates" but "what is the one record the world needs so that compiled
knowledge is just another kind of document". My current answer, which lane 02
is trying to break:

> A **claim**: a typed payload, pinned to zero or more (source, range,
> revision) triples, with a status in a small lattice that only a principal
> holding the right capability may advance, written by a named operation.

An object is a claim about a thing. An edge is a claim about two claims. A
conflict is a claim that two claims about one subject disagree. A session note
is an authored claim at the lowest status. A hypothesis is a claim one rung
up. A review is an operation that advances a status. Evidence is not a claim;
it is the pin. If that holds, the world layer is one schema plus laws, and the
kernels of §2.2 become theorems over one type instead of six.

What I expect to lose: attribute-level versions (EKOS diffs facts, not objects;
a claim per attribute may be the honest grain), events (which have no status
and are probably a second record), and the exact-merge re-key (which in a
world of stable identities becomes an overlay link, reversible, and that is an
improvement EKOS could take back).

## What it would feel like

A friend on the public node opens a room. The room has a few documents, a
grain running a small app, and a resident. They ask the resident what the app
reads. The resident does not grep; it answers from compiled claims with pins,
and each pin either resolves to the same bytes or says "moved since". They
open one of the documents in Studio and see, in the margin, every claim that
rests on the paragraph they are about to edit. They edit it. The pins go
stale, visibly, and a recompile is proposed, admitted, and recorded with a
receipt. Nothing was deleted; the old claims are history. A second friend who
can see only one of the documents asks the same question and gets an answer
that mentions nothing they cannot see, and no hint that anything is missing.

That is EKOS's promise list, kept by the world's own rules, in a place people
actually live.

## What I do not know yet

Whether a whole-corpus compile fits a per-declaration admission model without
a special law. Whether sealed-by-default disclosure can coexist with a broadly
readable compiled layer without making the Runtime a keyholder. Whether the
claim record survives lane 02. Whether the Isabelle kernels are worth two
provers once the world layer exists, or whether they are scaffolding we remove
later, the way veri7vn removed its revision-2 operating system after no lane
needed it.
