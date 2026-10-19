# Lane B. `verekos check`: the Lean model answers the panels

Lane B of exploration 05 (`docs/design/explorations/05-next-lanes.md`, "Lane B"),
Opus 5.5, 2026-10-19. Code in `check/`; receipts in `controls/check/`; board
column in `tools/scoreboard/board.py`.

## The numbers

| Panel | Items | Agree | Classified (E / V / N) | Unexplained | Answered by the model |
|---|---|---|---|---|---|
| `scope.decision` | 59 | 59 | 0 / 0 / 0 | 0 | 43 through `World.visible`; 16 by the untrusted parser alone (11 `parse`, 3 `unrestricted`, 2 `origins`) |
| `conflicts.unit` (join view) | 16 | 16 | 0 / 0 / 0 | 0 | all 16 through `World.detectList` (via `Check.detectL`, proved equal) |
| `scope.decision`, planted mutant (deny ignored in the mapping) | 59 | 44 | 0 | 15 | scores worse, as it must |

Nothing differed on either panel, so nothing was added to
`controls/classified.jsonl` (and the self-test manifest under
`tools/scoreboard/selftest/` was not used). Both rows now show
`executable property` on the board, earned by a fresh verdict; `panels/LABELS.json`
still says `design target` and was not edited (the board computes the earned label).

The laws checker, `verekos-check laws <run-root>`:

| Run root | Writes | Pin law (`AdmLog`) | Compiled pins nonempty | Tx increasing | Conflict status over time | Exit |
|---|---|---|---|---|---|---|
| slice 1 run-2 (real, `check/fixtures/slice1-run-2`) | 13 | holds | 12 of 12 | yes | email type: open (tx 8), resolved (tx 10, the review), needsReview (tx 13, the S5 recompile); columns: open | 0 |
| the same log, review re-signed by the compiler (planted) | 13 | holds | yes | yes | email type: open, never decided | 1 (expected) |
| synthetic good | 11 | holds | 9 of 9 | yes | open, confirmed, needsReview; a second conflict stays dismissed | 0 |
| synthetic good, author taken from the payload (planted mutant) | 11 | holds | yes | yes | a `rejected` appears at tx 8 | 1 (expected) |
| synthetic bad | 3 | fails at tx 3 | fails (tx 1) | no | — | 1 (expected) |

Probes outside the panels (inputs I wrote, answered by EKOS's own control
binary, not panels and not on the board; `check/probes/`):

| Probe | Items | Agree | Differ |
|---|---|---|---|
| scope (glob classes, `**` rules, UUID forms, serde edge cases) | 93 | 91 | 2 |
| conflicts (type spellings, flags, merge groups, label rules) | 26 | 22 | 4 |

## Receipts

- Verdicts: `controls/check/scope.decision.verdict.json`,
  `controls/check/conflicts.unit.verdict.json`,
  `controls/check/scope.decision.mutant-deny-ignored.verdict.json`; laws runs:
  `controls/check/laws.*.json`. Each carries `check_build`.
- scope.decision: candidate `sha256:6249610707a4ad76…`, panel `43c3119e3f7a56a2…`,
  control `6249610707a4ad76…`. The candidate is byte-identical to the control
  because both writers print compact JSON with sorted keys; the runner reads only
  the panel on stdin and never opens the control, and the mutant (`de6f37f2…`)
  shows it computes.
- conflicts.unit: candidate `5c879dcaec2fb236…`, panel `b0c268c2161dbac5…`,
  projected control `5c879dcaec2fb236…` (`controls/check/conflicts.unit.keys.control.jsonl`).
- Build: `verekos-check` `sha256:fac1926915b7…`, world pinned at `a8bb023`,
  Lean 4.30.0. A clean rebuild gives the same sha256.
- Reproduce: `cd check && nice -n 10 lake build && cd .. && python3 -I check/run.py`
  (exit 0 means every expected exit was met and the mutant scored worse).

## What was built

| Piece | What it does | Trusted? |
|---|---|---|
| `check/lakefile.toml` | A Lake project requiring `world` as a git dependency pinned to `a8bb023` (subDir `world`), cloned under `check/.lake/packages`. Not a path dependency: that would build inside `world/`, which the world lane edits live. Mathlib-family packages are symlinks to the same checkouts `world/` uses; Lake downloaded nothing. | — |
| `Check/Scope.lean` | The ReadScope parser (serde's rules as read), the `glob` 0.3.4 port (`Check/Glob.lean`), and the mapping into `World.Scope` | untrusted |
| `Check/Detect.lean` | `detectL`, `World.detectList` over `List` | proved equal |
| `Check/Conflicts.lean` | panel objects into claims; ports of `normalize_type`, `facts`, `normalize_expr`, `label_words` as the schema's `stated` | untrusted |
| `Check/Adm.lean` | Mathlib-free copies of `rankMap` … `admissible`; `admLogB`, `pinsNonemptyB` | proved equal |
| `Check/Laws.lean` | run root into `World.Receipt`s; the report | untrusted reader |
| `CheckProofs/Detect.lean` | `mem_detectL`: `k ∈ detectL reg l ↔ k ∈ World.detectList reg l`; `detectL_toFinset`; `mem_detectL_congr` | proved |
| `CheckProofs/Adm.lean` | `admissibleL_eq`, `rankMapL_eq`, `admLogB_iff : admLogB d L = true ↔ World.AdmLog d L`, `pinsNonemptyB_iff` | proved |
| `check/run.py` | runs everything, scores, writes receipts with the build hash | — |
| `check/slice1_log.py` | slice 1 run root into `log.jsonl` | untrusted |
| `tools/scoreboard/project_conflict_keys.py` (+ `test_…`, 7 tests) | EKOS's conflicts control as (subject key, attribute) pairs, the join view; subject ids are recovered by UUIDv5 of the panel's keys, fatal when none matches | tested |
| `board.py` | a Candidate column read from `controls/check/<panel>.verdict.json`, checked by sha256 against the candidate, the control and the current panel file; a stale verdict is shown as stale and earns nothing | — |

The bridging theorems depend only on `propext`, `Classical.choice` and
`Quot.sound` (`#print axioms`, `var/check/axioms.txt`). No `sorry`, `admit`,
`axiom` or `native_decide` in `check/`.

**Build cost.** The executable imports no Mathlib module, so nothing from Mathlib
is compiled or linked: a clean build of `verekos-check` takes 4.7 s wall
(27 jobs, including the five World modules it needs). `CheckProofs` imports
Mathlib through `World.Conflicts` and `World.Admission` and loads its existing
`.olean` files only: 8.1 s wall. The binary is 90 MB (the Lean runtime and
`Lean.Data.Json`, statically linked). Lake cloned minidregg into
`check/.lake/packages/minidregg` (566 MB on disk), because `world` requires it;
no module of it is built. A symlink to `world/.lake/packages/minidregg` would
save the space but would let a stray build write into `world/`'s tree.

## The model questions the brief asked about

1. **An explicitly allowed id is visible even when none of its pins is allowed**
   (`World/Visible.lean:55`). Kept, as the root decided. It is EKOS's rule:
   `Compiled::visible` returns true on `allow().any(named)` before looking at
   origins (`ekos/crates/ledger/src/scope.rs:256`), after the deny check. Two
   panel items exercise it, and the model agrees on both:
   `object_rules_name_one_object#1` (default deny, the id allowed, an origin with
   no source and no path: visible) and
   `a_deny_on_a_source_beats_an_allow_on_the_object#2` (the id allowed, its only
   origin `web` not allowed: visible).
2. **"Unknown source counts as denied."** I read `denies`, `allows`,
   `Compiled::visible` and `origins` (scope.rs:195-300) and gave World's four
   predicates exactly those rules. `deniesOrigin` is `denies`: a deny rule
   with a source matches an origin with no source, and one with a path matches
   an origin with no path. `allowsOrigin` is `allows`: an allow rule with a
   source or a path does not match a missing one. The default is folded in:
   a default-allow scope allows every origin. With that, World's "not
   allowed" and EKOS's "not allowed" are the same function. No panel item
   differs. One probe differs. An empty origin list under default allow is
   visible in EKOS (`visible` with `origins = []`) but hidden by the model
   (`unpinned_hidden`, Visible.lean:118). EKOS's own docstring says origins
   are never empty (scope.rs:237), and its `origins()` never returns an empty
   list, so the pipeline cannot produce that input. Proposed class:
   `non_goal`, because the input lies outside EKOS's stated precondition. The
   model's "nothing is unattributed" is stricter than EKOS here and should
   stay.
3. **The author of a receipt is the signer.** `verekos-check laws` takes each
   receipt's author from `principals.json` by the signer's role, never from the
   payload. On slice 1's run the signer of each compile write is the
   `createdBy.subject` the host recorded on the entries that write created.
   The signer of the review is the `subject` of the reviewer's signed command
   (`receipts/world/reviewer-workspace/attempts/review-resolve/intent.json`).
   Two planted checks show the rule matters. On the synthetic log, believing a
   payload that says "human" admits a compiler's `rejected`. On the real log, a
   review re-signed by the compiler is not admitted, and the conflict never
   leaves `open`.

## Findings

**F1. The model cannot state EKOS's label-mismatch rule (a model gap).**
`World.disagreeOn` (`World/Conflicts.lean:45`) flags two claims when they
state *different* values for an attribute. EKOS's `label_mismatches` flags two
labels when their source sets are disjoint *and* their word sets share no word
(`ekos/crates/semantic/src/conflicts.rs:414-416`). That relation is not
"different after normalization": it is not transitive. The two panel items
agree only because their word sets are equal or disjoint. Three probes
disagree:
- `asset account` and `asset` from two sources. EKOS: no conflict (a shared
  word). Model: a conflict.
- A label shared by two sources plus a second label from one of them. EKOS:
  no conflict (the source sets meet). Model: a conflict.
- Two labels with no source at all. EKOS: a conflict (two empty source sets
  are disjoint). The mapper puts both under one source, so the model finds none.

The model-side fix lets a schema say what counts as a clash. Exact proposed
statement, for the world lane:

```lean
-- World.Schema gains
  clash : C.Digest → C.Digest → Bool   -- default: fun a b => decide (a ≠ b)

def disagreeOn (c₁ c₂ : Claim C P) : List C.Digest :=
  (c₁.stated reg).filterMap fun av =>
    if (c₂.stated reg).any (fun bw => decide (bw.1 = av.1) && (reg c₁.key.schema).clash bw.2 av.2)
    then some av.1 else none

theorem mem_detect … ↔ ∃ c₁ ∈ cs, ∃ c₂ ∈ cs, c₁ ≠ c₂ ∧ sameSubject c₁ c₂ ∧
    ∃ a v₁ v₂, (a, v₁) ∈ c₁.stated reg ∧ (a, v₂) ∈ c₂.stated reg ∧
      (reg c₁.key.schema).clash v₂ v₁ = true ∧ k = (c₁.key.schema, c₁.key.subject, a)
```

With one claim per distinct label whose value encodes (word set, source set),
and `clash (w₁, s₁) (w₂, s₂) := disjoint w₁ w₂ && disjoint s₁ s₂`, EKOS's
rule is expressible exactly. `coverage`, `soundness` and `detectList_congr`
carry over with `clash` in place of `≠`. For order independence `clash` must
be symmetric, a premise to state once. The other three detectors keep the
default.

**F2. The real run barely exercises the pin law.** In slice 1 every compiled
claim pins source statements, not other claims. The only claim pin in the
13-write log is the review's pin on the conflict. So `AdmLog` holding on run-2
says little about acyclicity: no chain of claims pinning claims exists to rank.
The manifest's links name objects by logical key, not as revision pins, and are
not modelled as pins. The pin law will mean more once a claim pins a claim
(a conflict pinning its alternatives, as `World/Visible.lean`'s
`conflict_hidden_of_alternative_denied` assumes).

**F3. Status agrees with slice 1 when the core is the header revision.** On the
real log, `World.statusAt` with the conflict header's revision as core gives
`resolved` after the review and `needsReview` after the S5 recompile moved
the header from `7776436338…` to `2042089842…`. That is what slice 1 observed
(`receipts.tsv`: R5 after-review-pin `moved`). The columns conflict, whose
header the recompile left alone (`3794410500…` both times), stays `open`. This
is the 3.1 correction (R1 S5) holding on real receipts. `World.Status.status`,
which takes the core from the payload, could not have been used. The
proposal to let a schema core read pin revisions still stands.

**F4. Mapper and parser gaps found by probes (not on any panel).** The
serde reader refuses a duplicate JSON key (`{"default":"deny","default":"allow"}`).
Lean's `Json.parse` keeps the last one, so the runner says `parsed`. This is a
VerEKOS defect of the untrusted parser. A fix would need a custom JSON reader.
All 31 glob patterns agree (62 items: visibility and parse for each), including `[!…]`, `**` placement errors, `[]]` and a
leading `./`.

**Re-pinned to world `79b0445` (carriers as classes), 2026-10-19.** The
runner's three carrier sets (`Check.Scope.SC`, `Check.Conflicts.CC`,
`Check.Laws.LC`) and its two id derivations (`Check.Scope.derive`,
`Check.Laws.derive`) are now `scoped instance`s, each in its own namespace.
That keeps exactly one `World.Carriers` instance in scope wherever a model
term is built, though `Main` imports all three modules. Types lost their
carriers argument, and calls to `visible`, `latest`, `statusAt`,
`admissible`, `AdmLog` and `Claim.id` lost the derivation argument. No
meaning changed.
- **Build:** green, 41 jobs. The link takes 19 objects: 5 from `check`, 14
  from WorldCore, none from Mathlib (`var/check/link-classes.log`).
- **Receipts:** `run.py` exits 0. Every candidate is byte-identical: 59/59,
  16/16, 7/7, 16/16 under `--clash`, 26/26 for the probes, and the mutant at
  44/59. The five laws runs keep their exits and reports. Only `exe_sha256`
  (now `c2f1cb3bc851…`), `check_tree` and `world_rev` moved. The board is
  re-rendered.

**Twins deleted, 2026-10-19 (world `833eae5`, `WorldCore`).** The world
lane split out `WorldCore`, a Mathlib-free library. `check/` now imports it
and keeps no copy of any model definition. Deleted:

| File | Definitions | Lines |
|---|---|---|
| `check/Check/Adm.lean` | `pinRankL`, `maxPinRankL`, `newRankL`, `rstepL`, `rankMapL`, `admissibleL`, `admLogB`, `pinsNonemptyB` | 60 |
| `check/Check/Detect.lean` | `statedL`, `disagreeOnL`, `detectL` | 45 |
| `check/Check/DetectBy.lean` | `ClashL`, `disagreeOnByL`, `detectLBy`, `disjointBL`, `labelClashL` | 52 |
| `check/CheckProofs/Adm.lean` | `pinRankL_eq`, `maxPinRankL_eq`, `newRankL_eq`, `rstepL_eq`, `rankMapL_eq`, `admissibleL_eq`, `admLogB_iff`, `pinsNonemptyB_iff` | 63 |
| `check/CheckProofs/Detect.lean` | `statedL_eq`, `disagreeOnL_eq`, `mem_detectL`, `detectL_toFinset`, `mem_detectL_congr` | 58 |
| `check/CheckProofs/DetectBy.lean` | `disagreeOnByL_eq`, `disjointBL_eq`, `labelClashL_eq`, `mem_detectLBy`, `detectLBy_toFinset`, `mem_detectLBy_label` | 62 |
| `check/CheckProofs.lean` and the `CheckProofs` library in `check/lakefile.toml` | — | 3 |

The runner now calls `World.detectL`, `World.detectLBy`, `World.Clash`,
`World.labelClash`, `World.admissible`, the `Decidable` instance of
`World.AdmLog` and `World.Claim.PinsNonempty` (as `c.pins ≠ []`) directly. The
model's own `detectL_toFinset` and `detectLBy_toFinset` replace the deleted
equalities.
- **Lines:** Lean in `check/` went from 1650 to 1303. What remains is
  `Glob`, `Scope`, `Conflicts`, `Laws` and `Main`: parsers, mappers, the
  report and the runner. No `def` in `check/Check/` shares a name with a
  WorldCore definition, except `Check.Glob.compile`, the `glob` crate's
  `Pattern::new`, which is unrelated.
- **Build:** a clean build is 41 jobs, 7.2 s wall
  (`var/check/build-worldcore.log`). The link step (`lake build -v`,
  `var/check/link-worldcore.log`) takes 19 objects: 5 from `check`, 14 from
  `world`, all WorldCore. None is from Mathlib.
- **Verdicts:** every candidate is byte-identical to before: 59/59, 16/16,
  7/7, 16/16 under `--clash`, and 26/26 for the probes. The five laws runs
  keep their exits and reports. Only `exe_sha256`, `check_tree` and
  `world_rev` moved; the binary is now `sha256:30167dcb02b8…`.

**F1 closed by the world lane; runner path added, 2026-10-19.** World
`12e5543` adds `World/Clash.lean`: `detectBy`/`detectListBy` under a per-schema
clash table, with `detectBy_differ` proving the default is `detect`, and
`labelClash`, EKOS's label rule (`mem_detectBy_label`). `check/` is re-pinned
to `12e5543`. `verekos-check conflicts --clash` runs `Check.detectLBy` (a
Mathlib-free copy) with `labelClashL "EnumMeaning"`. On this path the label
claims are one per distinct label, with that label's source set as the key's
sources. Every other schema keeps "values differ". `CheckProofs/DetectBy.lean`
proves `mem_detectLBy` (`k ∈ detectLBy reg κ l ↔ k ∈ World.detectListBy reg κ l`),
`detectLBy_toFinset` and `mem_detectLBy_label`, on the standard axioms only.
Numbers:
- `conflicts.unit` through `--clash`: 16/16. The candidate is byte-identical
  to the default path's, including both `label_mismatches` items.
- The 26 conflicts probes: 26/26 under `--clash`, against 22/26 on the
  default path. All four label probes flip to agree: the three F1 cases
  (overlapping words, a label shared by two sources, a shared source with
  a second label) and the two source-less labels, which were a mapper
  artefact of keying claims by source.

Both runs are regressions in `run.py` (`controls/check/conflicts.unit.clash.verdict.json`,
`controls/check/conflicts.probe.clash.verdict.json`; the probe control is
`check/probes/conflicts.probe.keys.control.jsonl`, made by `control-dump conflicts`
then `project_conflict_keys.py`). The `conflicts.unit` panel verdict still
comes from the default path and is unchanged (16/16, same candidate sha256).
F1's proposed `verekos_defect` classifications in follow-up 3 are void.

**F4 fixed, 2026-10-19 (root's follow-up).** The parser now scans the raw
text for a key repeated in any JSON object (compared after unescaping) and
refuses it as `parse`, before `Json.parse` runs (`check/Check/Scope.lean`,
`hasDuplicateKey`). Seven regression inputs, `check/probes/scope.regression.jsonl`,
have EKOS's answers committed beside them (from `control-dump scope`: 5
refused, 2 parsed), and `check/run.py` scores them; the result is 7/7, 0
unexplained (`controls/check/scope.regression.verdict.json`). The 93-item
scope probe now differs on 1 item (empty origins), down from 2. One more thing
read on the way: EKOS refuses duplicates only through `ReadScope::from_json`
(serde's derived deserializer, scope.rs:94). `from_value` (scope.rs:101),
which MCP's per-call scope uses, receives an already-parsed
`serde_json::Value` whose map has kept the last value, so on that path EKOS
accepts the same text. That is two behaviours for one scope, depending on
the entry point; the panel tests only `from_json`.

**Exit codes documented, 2026-10-19 (root's follow-up).** `check/README.md`
gives, for each `verekos-check` subcommand and for `run.py`, what exits 0, 1
and 2, and which exit `run.py` expects of each laws run. The committed runs'
exits were already right. While writing it, one gap was closed:
`verekos-check laws` could exit 0 with a failed law if the run's
`expect.json` said that law should fail. Now a failed law always exits 1, the
report carries `laws_hold`, and `expect.json` can only add requirements. No
committed run changed its exit.

## What could not be verified

- **The mapper and the converter have no theorem.** The board label is
  `executable property`, not `proved` or `conditional`, for that reason. The
  theorems are about `World.visible` and `World.detectList`, and the panel is
  scored by running exactly those. But that the mapping means what EKOS means
  is shown only by agreement on 59 + 16 items and 119 probes.
- **The ports are ASCII-only.** Lean's `Char.toLower`, `isUpper` and
  `isAlphanum` are ASCII; Rust's are Unicode. They agree on every panel input.
- **On slice 1, the compile writes' signers come from the host's `createdBy`
  in cell reads, not from each command's signed intent.** W17 copied only 8
  attempt directories locally. Only the review's signer is read from a signed
  intent.
- **The converter's other choices** (`check/slice1_log.py`). Compile-1 claim
  values for the three cells that changed come from `r5-before/` (read after the
  review, before compile 2). Imports, compile-run records and the attestation
  are skipped as non-claims (6 rows). Pins are source pins named
  `src-<key>` with the statement key as range. `expect.json` is written from
  slice 1's own R5 observations, not derived independently.
- **The 16 scope items answered by the parser alone** do not go through the
  model at all.

## Follow-ups

1. World lane: `Schema.clash` as stated in F1, and then the label rule as a
   real schema.
2. When W17 copies every attempt's `intent.json`, take every signer from the
   signed command (`check/slice1_log.py`, `signer_of`).
3. If the probes are worth keeping as panels, `check/probes/*.jsonl` plus
   `control-dump scope|conflicts` give the control. The 6 differences then
   need classification: F1's three as `verekos_defect` (a model gap), the
   source-less label case as `verekos_defect` of the mapper, the duplicate-key
   case as `verekos_defect` of the parser, the empty-origins case as
   `non_goal`.
4. A board row for the laws on slice 1 (today the result is in
   `controls/check/laws.slice1-run-2.json` and this memo only).
5. Ownership note: lane C committed its layout move while this lane ran. The
   board could not render on the half-moved tree, and `check/run.py` now takes
   its panel paths from `panels/LABELS.json`.
