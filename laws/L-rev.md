# L-rev

On `ekos/review` cells. This is the shell's `note` law (`shell.rs:153-163`) plus a subject gate on mutate. installPolicy is not gated: that is the row in the exploration, and it is the hole the design states.

Placeholder, not a real subject:

| placeholder | stands for |
|---|---|
| `91004` | the human-reviewer set |

## Verb by verb

| verb | code | verdict |
|---|---|---|
| observe | 1 | allowed. |
| mutate | 2 | allowed only when subject is in `[91004]`, `content/atom-edits = 0`, and `content/tombstones = 0`. A review write may create; it may not edit an atom or strike one. |
| delegate | 3 | allowed. |
| installPolicy | 4 | allowed, for any subject. Whoever can exercise this verb can replace the law. The design's human-only guarantee rests on the compiler and residents never holding that capability, not on this file. |
| revoke | 5 | allowed. |

Refused: a mutate by anyone outside `[91004]`; a mutate that edits an atom or writes a tombstone; append 7, place 10, reserve 12.

"Append-only" here means the note shape: decisions arrive as creates inside a mutate, and the counts of edits and tombstones stay zero. It is not verb 7 (`appendObject`).

## What it cannot express

- That the subject is a human. `[91004]` is a list of integers. A compiler principal placed in that list passes.
- That an installPolicy on this cell is refused. It is not.
- The text of a decision. The law sees counts (`content/atom-edits` at `ContentResource.lean:1801`, `content/tombstones` at `:1814`), not bytes.
