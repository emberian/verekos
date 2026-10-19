# W4. The four document laws as client Pred JSON

2026-10-19. The Grok lane drafted `laws/L-{src,obj,rev,run}.json` and their `.md` notes, then
died with "Prompt is too long" before the checker and this memo; the root wrote `laws/check.py`
and this memo from the same ground truth.

**Summary.**
1. Four laws exist as the client's own JSON spelling and pass `check.py`: every constructor
   name and field is one the client serializer emits, every slot is one the kernel projects,
   every verb code is 1-5, values are strings.
2. The `not` spelling is `{"type":"not","predicate":…}` and `le` is `{"type":"le","slot":…,"value":"0"}`
   (`/Users/ember/dev/minidregg/native/resource-client/src/shell/law.rs:243-248`, `:392`, `:439`).
3. L-obj's birth obligation is a count: `document-creates = 0 ∨ ¬(transclusions ≤ 0)`
   (`Kernel/ContentResource.lean:1805`, `:1811`). `Pred` cannot see which range a transclusion
   points at; that stays for replay attestation.
4. Principal sets are integer placeholders (91001-91004 families); real subject ids come from
   the scratch world at slice-1 time.
5. Not verified: whether any client command installs a custom law from a file (lane W2 is
   answering); `request/verb` is projected for object cells (`Kernel/AgentGrain.lean:158-161`
   uses it) and the shell templates test it on documents, but I did not read the content
   route's request projection to confirm the slot name there.

## Ground truth used

| What | Where |
|---|---|
| Constructor and field names | `native/resource-client/src/shell/law.rs:211-430` (`all`/`any` with `predicates`, `not` with `predicate`, `eq`/`le` with `slot`,`value`, `memberOf` with `slot`,`values`, `monotone`/`writeOnce` with `slot`, `eqSlots`/`leSlots` with `left`,`right`, `leSlotsOff` adds `offset`, `hashEq`, `ran`) |
| Content slots | `Kernel/ContentResource.lean:1788-1819` (`content/document-creates`, `content/transclusions`, `content/annotations`, `content/marks`, `content/atom-edits`, `content/tombstones`, …) |
| Request slots | `Kernel/ObjectRecord.lean:449-455` (`request/subject`, `request/height`, `request/target`, `request/turn`, `request/caller`); `request/verb` per the shell templates (`shell.rs:142-162`) and `Kernel/AgentGrain.lean:158-161` |
| Verb codes | observe 1, mutate 2, delegate 3, installPolicy 4, revoke 5 (shell templates) |

## `check.py` output (2026-10-19)

```
law      nodes errors  constructors
L-obj       14      0  all:2, any:2, eq:5, le:1, memberOf:3, not:1
L-rev        7      0  all:1, any:1, eq:3, memberOf:2
L-run        7      0  all:1, any:1, eq:3, memberOf:2
L-src        8      0  all:2, any:1, eq:2, memberOf:3
```

Run it with `python3 -I laws/check.py`. It exits non-zero on any error and names the node.

## Follow-ups
- Replace the placeholder subject ids when the slice-1 world mints its principals.
- Once W2 reports how a law is installed, add the install command to each `L-*.md`.
- `installPolicy` (verb 4) is owner-only in every law; the human-only guarantee rests on the
  compiler and residents never holding that capability (design §3).
