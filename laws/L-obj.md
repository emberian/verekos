# L-obj

On `ekos/object`, `ekos/conflict`, and `ekos/manifest` cells. One law, three families: install substitutes the compiler list and the owner list for that family.

Placeholders, not real subjects:

| placeholder | stands for |
|---|---|
| `91003` | the compiler |
| `91002` | the owner set (same placeholder name as L-src; not a claim that one principal owns both) |

## Verb by verb

| verb | code | verdict |
|---|---|---|
| observe | 1 | allowed. Subject unchecked. |
| mutate | 2 | allowed only when all of these hold: subject in `[91003]`; `content/annotations = 0`; `content/marks = 0`; and either `content/document-creates = 0` or it is not the case that `content/transclusions ≤ 0`. |
| delegate | 3 | allowed. A later mutate is still judged against the compiler list. |
| installPolicy | 4 | allowed only when subject is in `[91002]`. |
| revoke | 5 | allowed. The row does not constrain it. |

Refused, by name:

- a mutate whose subject is not the compiler
- a mutate that counts any annotation (`content/annotations`, action tag 5, `ContentResource.lean:1804`)
- a mutate that counts any mark (`content/marks`, action tag 10, `ContentResource.lean:1809`)
- a birth: `content/document-creates` is not 0, and `content/transclusions ≤ 0`. The `not`/`le` spelling is the client's (`shell/law.rs:248`). On a content command the slot is always projected (`ContentResource.lean:1805`), so `≤ 0` means a zero count, and the negation means at least one.
- append 7, place 10, reserve 12, same as the shell templates

A later write that creates no document (`content/document-creates = 0`) may carry zero new transclusions. The birth obligation is the disjunction, not a blanket "every mutate transcludes".

## What it cannot express

- "At least one transclusion" is a count. A compiler can transclude an irrelevant range. `Pred` cannot see a link's relation or an atom's bytes. Full P3 and P4 are re-execution, not this file.
- `not` flips a failed atom to true (`Pred/Core.lean:312-313` and `:341`). If this law is ever judged on a view that lacks `content/transclusions`, a birth with no transclusion slot passes the count clause. The content projection does not lack it.
- The same installPolicy-is-a-program-verb caveat as L-src.

## Installing it

Lane W2 (`notes/W2-transclusion-and-laws.md`) found two client paths that take arbitrary Pred JSON, no client change needed: `law ID REF @laws/L-obj.json` (`native/resource-client/src/shell.rs:79`, handler near `:2293`, builds `action:"install-policy"` and runs the op-150 satisfiability gate) and `doc new NAME @laws/L-obj.json` (the fourth word is the law; `shell.rs:1360-1372`, `law_argument` at `:1059`). Subject ids in this file are placeholders until the scratch world mints its principals.
