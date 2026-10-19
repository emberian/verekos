# L-run

Append-only audit. `L-run.json` is the law for `ekos/compile-run`: the shell's `note` law, and mutate only by the compiler placeholder.

The exploration's "respectively" is two installs, not one `memberOf`. The same JSON with `[91003]` replaced by `[91005]` is the law for `ekos/replay-attestation`. Putting both integers in one list would let a verifier append a compile-run.

Placeholders, not real subjects:

| placeholder | stands for | install on |
|---|---|---|
| `91003` | the compiler | `ekos/compile-run` (this file) |
| `91005` | the verifier set | `ekos/replay-attestation` (substitute into the mutate clause; do not add it beside `91003`) |

## Verb by verb

| verb | code | verdict |
|---|---|---|
| observe | 1 | allowed. |
| mutate | 2 | allowed only when subject is in `[91003]` (or `[91005]` on a replay-attestation cell), `content/atom-edits = 0`, and `content/tombstones = 0`. |
| delegate | 3 | allowed. |
| installPolicy | 4 | allowed, for any subject. Same residual as L-rev: the note template lets 4 pass, and the row does not add an owner clause. |
| revoke | 5 | allowed. |

Refused: a mutate by a subject outside the one list installed on that cell; a mutate that edits or tombstones; append 7, place 10, reserve 12.

## What it cannot express

- That the compile-run's pins match the output, or that a replay agrees. Those are attestation contents. This law only constrains who may append and that the append does not rewrite.
- That the verifier is a different principal from the compiler. That is true only if the two substituted lists are disjoint. The JSON cannot say "different from".
- Bytes, command-hash equality, or "a principal other than the compiler". No slot here is a principal-inequality against another cell.
