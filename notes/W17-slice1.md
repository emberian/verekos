# W17 — slice 1: an EKOS compile as admitted cells on hbox

**Summary (5 lines).**
1. **Slice 1 runs end to end on a fresh hbox Store (`run-2`), and all seven receipts came out as expected.** EKOS 1.1.0 compiled the two fixtures, read back from the world's own source cells. The mapper turned the export into 9 births, and `compiler` landed all of them. Each object's evidence is a snapshot transclusion pinned to its `create-table:*` statement atom (R1).
2. **The laws and the kernel refused all three wrong writes by name.** A birth with no transclusion was refused `law-denied` by L-obj (R2). `compiler` writing the review cell was refused `law-denied` by L-rev (R3), although it holds a mutate grant there. A transclusion without a read of its source was refused `Minidregg.Kernel.ContentResource.Reject.sourceNotCovered` (R4).
3. **The `CITEXT` edit behaved as designed.** The re-import was one `editAtom`, and the Host rendered the old legacy pin `moved`. The recompile edited the email-type conflict header (signature `bfc2f80c…` → `2a144141…`), the column-set conflict header stayed as it was (the control), and the reviewer's pin on the header now renders `moved` (R5).
4. **`reader-shop` sees what the room grants and nothing else.** It reads the `customers` properties, gets `[transclusion: 1 atoms of src-legacy, not readable by you]` where the legacy evidence would be, holds no legacy bytes, and is refused `no-grant` on the conflict cell (R6).
5. **The replay matched byte for byte, and an unchanged re-import sends nothing.** The verifier's own reads, its own fresh EKOS run and the mapper reproduced the compile's request bytes (SHA-256 `bcd84c64…`; all 9 request files are byte-identical), and the verifier appended an attestation. An unchanged re-import submits nothing, and an empty command is refused by the client before signing (R7). hbox disk: 30 GB free before and after; run roots are 50 M (`run-1`, debugging) and 41 M (`run-2`).

## Receipts (run-2, `~/verekos-runs/slice1/run-2/receipts.tsv`; copy in `var/w17/run-2/`)

Principals (run-2): owner = sponsor `7`; importer `12811640889601477773`; compiler `17155919447801168794`; reviewer `17742909249709527374`; verifier `18428175073871354045`; reader-shop `11209456927570751213`.

| # | Expected | Got | Refusal name / evidence | Seconds |
|---|---|---|---|---|
| R1 | `obj-customers` birth accepted; its pin names the `create-table:customers` atom at its revision | **accepted** (outcome `confirmed`, tx `81432878…`). 2 transclusion records: shop pin `atom 357861120254461623750417364445892670 @ 22213746487809…` equals the source atom's revision; legacy pin `654521657521855419949430137509036340` | — | 22.3 (birth) + 8.9 (check) |
| R2 | birth with zero transclusions refused by L-obj | **refused** | `refused: law-denied: any [ not (all [ open, open, open ]), any [ verb in {read,delegate,revoke}, all [ verb == install, subject in {7} ], all [ verb == write, subject in {17155919447801168794}, slot "content/annotations" == 0, slot "content/marks" == 0, any [ slot "content/document-creates" == 0, not (slot "content/transclusions" <= 0) ] ] ] ]` (phase prepare) | 7.9 |
| R3 | `compiler` appending a decision to `review` refused by L-rev | **refused** (compiler holds observe+mutate on `review`, so this is the law, not a missing grant) | `refused: law-denied: any [ not (all [ open, open, open ]), any [ verb in {read,delegate,install,revoke}, all [ verb == write, subject in {17742909249709527374}, slot "content/atom-edits" == 0, slot "content/tombstones" == 0 ] ] ]` | 7.7 |
| R4 | transclusion of a source not read in the same command: `sourceNotCovered` | **refused** | `Minidregg.Kernel.DeclaredResourceController.Reject.content (Minidregg.Kernel.ContentResource.Reject.sourceNotCovered)` (phase prepare) | 7.6 |
| R5 | legacy pin `moved`; conflict header edited; review pin `moved` | **before recompile:** old legacy pin = `moved` (Host render). **After recompile:** old pin `moved`, new pin `snapshot`; email-type header **edited** (signature `bfc2f80cdccacb27…` → `2a144141f4836ed1…`); control `cf-customers-columns` header **unchanged**; review pin `snapshot` → **`moved`** | — | 24.2 / 43.0 (renders); recompile 186.4 total |
| R6 | properties visible; legacy transclusion a placeholder; conflict cell unreadable | **columns visible** `["id","email","name","phone","created_at","updated_at"]`; legacy (old and new pins) `unavailable`, text `[transclusion: 1 atoms of src-legacy, not readable by you]`; shop `snapshot`; **0** legacy bytes (plain or hex) in anything reader-shop received; conflict read **refused** | `refused: no-grant: this key holds no grant covering this target and operation (phase observation)` | 9.4 / 9.0 / 4.0 |
| R7a | the verifier's command SHA-256 equals the compile-run's | **equal**: `bcd84c6407873338f39a80edc4eacadd836dca7ec48f8c1f40909b8d43778443`; export body identical (only the header's `generated_at` and workspace path differ); request files byte-identical; attestation **accepted** (`match: true`, `liveness: replayedDeterministic`) | — | 21.0 (incl. EKOS) |
| R7b | unchanged re-import submits nothing | **nothing submitted** for both sources. Control: an empty command sent by hand is refused **by the client** before signing: `mini: content proposal requires 1..64 actions` (the Host's `empty_command_rejected` is never reached) | client refusal | 7.7 / 3.3 |

### What R5 "moved" means here, precisely

The Host's own `view-document` render gives `"view":"moved"` for a snapshot whose pinned atom has a newer revision. The client then re-reads the source `at` the opening height. A reader whose grant stood at that height (the verifier, the reviewer) is shown the old bytes with `snapshot@70`/`snapshot@80`. A reader whose grant did not stand then keeps the `moved` placeholder. So R5's `moved` is the Host render that the client asked for first, captured from the attempt's `transclusions.json` (`world-lib.sh renders`). `*.client.json` holds the client's final view, which shows `snapshot@H`. Both files are kept in `var/w17/run-2/r5-{before,after}/`.

## Step wall-clock (run-2, `var/w17/run-2/steps.tsv`)

| Step | Seconds | Note |
|---|---|---|
| S2 setup (bootstrap 3.4, enroll 5 × `--new-key` 21.7, 2 rooms + 5 cells 15.5, 13 grants 65.6) | 106.8 | |
| S2 import (2 births) | 13.2 | shop: header + 13 statement atoms; legacy: header + 1 |
| S2 compile (EKOS 1.1 s; owner births 10 cells + 25 grants 292.5; 9 births + compile-run ≈ 201) | 500.0 | each propose+submit ≈ 17-24 s under load ≈ 12 |
| S3 R1-R4 | 32.4 | |
| S4 replay + attestation / re-import / empty | 21.0 / 13.7 / 3.8 | |
| S5 review / edit / R5-before / recompile / R5-after | 21.4 / 22.2 / 24.7 / 186.4 / 43.5 | recompile: 3 requests (8, 10, 12 actions) + compile-run |
| S6 reader | 22.7 | |

Cells: 2 rooms (`shop`, `legacy`, declared), 2 source cells, `review`, `compile-run`, `attestation`, 6 object cells, 2 conflict cells, `manifest`, and the spare `obj-r2`. That is 15 content cells plus 2 rooms.

## The exact commands

Everything runs from `slice1/run.sh run-2` on the Mac. The world steps go over ssh to hbox, where the code is rsynced to `~/verekos-runs/slice1/code/{slice1,laws}`. EKOS runs on the Mac, because the release binary is a Mac build.

```sh
# Mac
bash slice1/run.sh run-2            # nohup'd; PID in var/w17/run-2/run.pid; log var/w17/run-2/run.log
# hbox pieces it calls (RUNID=run-2):
bash code/slice1/s2-setup.sh        # sha256sum -c SHA256SUMS; newparticipant-acceptance.sh HOST MINI STORE VERIFIER $RUN/world $RUN/w.sock
bash code/slice1/s-import.sh 1 S2   # importer: read, mapper import, propose+submit
bash slice1/compile.sh 1 S2 0       # compiler reads -> render -> EKOS -> plan -> s-cells.sh -> s-compile.sh
TAG=1 bash code/slice1/s3-refusals.sh
bash slice1/replay.sh 1 S4          # verifier reads -> render -> fresh EKOS -> s4-attest.sh
EXPECT=nothing-submitted bash code/slice1/s-import.sh 2 R7b; bash code/slice1/s4-empty.sh
bash code/slice1/s5-review.sh
LEGACY_FILE=code/slice1/inputs/legacy_customers.v2.sql bash code/slice1/s-import.sh 3 S5
bash code/slice1/s5-r5.sh before; bash slice1/compile.sh 2 S5 1; bash code/slice1/s5-r5.sh after
bash code/slice1/s6-reader.sh
bash code/slice1/s-stop.sh          # stops the server by world/public/server.pid after checking its args
```

These are the raw `mini` lines behind the scripts. They use the same forms as `journey.d/j12t-kernel.sh` and `j10-kernel.sh`:

```sh
mini enroll --action plan --sponsor-workspace $W/sponsor --factory-ref factory --name NAME-1 --new-key $W/NAME.key --dir $W/attempts/NAME
mini enroll --action seal|submit --dir $W/attempts/NAME
mini workspace --action init --host H --config C --socket S --enrollment $W/attempts/NAME/enrollment.json --dir $W/NAME-workspace
mini workspace --action create --dir $W/sponsor --name src-shop --storage content --predicate laws/L-src.json --in shop
mini workspace --action propose --dir WS --request REQ.json --proposal-id ID      # delegate {verbs, room:true} or invoke {targets}
mini workspace --action submit --dir WS --intent WS/proposals/ID/intent.json --attempt WS/attempts/ID
mini workspace --action publish-delegation --dir $W/sponsor --proposal-id ID --attempt ...
mini workspace --action import --dir WS --name N --from-ref .../recipient-reference.json
mini workspace --action import --dir WS --name N --kind object --target T --observe-capability ROOMCAP   # a room cell
mini workspace --action read|transclusions --dir WS --name N
mini workspace --action doc-show --dir WS --name N --format json
```

And the EKOS commands (`slice1/ekos-compile.sh`):

```sh
ekos init; ekos build; ekos recover; ekos resolve; ekos compile; ekos commit
ekos graph export --format ndjson --include-property columns ... --include-property subject_name   # 15 keys
ekos conflicts list --json
```

## How the laws were installed, and who holds installPolicy

- Each cell is born by the sponsor (subject `7`, the only owner) with its law as the birth predicate: `workspace --action create … --predicate $RUN/laws/L-*.json`.
- `slice1/laws.py` writes those law files from `verekos/laws/L-*.json`, replacing the placeholders with real subjects: 91001 → importer, 91002 → `7`, 91003 → compiler (or the verifier, for the attestation cell's `L-run`), and 91004 → reviewer. Copies are in `var/w17/run-2/laws/`.
- The sponsor holds the only control capability on every cell. Every delegation to the five principals names `["observe"]` or `["observe","mutate"]` only (requests in `~/verekos-runs/slice1/run-2/req/g-*.json` on hbox).
- **L-src and L-obj** add a law-level guard: verb 4 passes only for subject `7`.
- **L-rev and L-run** let verb 4 pass for anyone (the shell-template shape, `memberOf verb [1,3,4,5]`). On `review`, `compile-run` and `attestation`, human-only therefore rests on nobody but the sponsor holding a control capability. This is the exploration's §2.3 caveat, and it is now visible in the deployed law. I did not try a law replacement by a non-owner, because no non-owner holds a capability that could even form one.

## What the mapper approximated, and whose problem each is

| # | Approximation | Kind |
|---|---|---|
| 1 | **Identifiers.** Atom, element, run, link and transclusion ids, and schema digests, are SHA-256 over a tagged tuple (`VEREKOS/ID/v1`, source key, path, structural key, occurrence), truncated to 120 bits. They are not `deriveIdentifier` over a Lean `IdPreimage`. The deployed client takes any decimal the command names and exposes no derivation. | schema gap here |
| 2 | **Schema digests on `createDocument`** are expressible through the raw `invoke` path (`schema` is a Nat in `Host/Json.lean contentAction`), so every document carries its `ekos/*/v1` digest. I did not use the shell's `doc new`, and I did not check what schema it sends. | none (worked) |
| 3 | **Redaction did not run.** The Redact kernel is not built, and `ekos_common::redaction` has no CLI entry. The source header says so in words. | schema gap here |
| 4 | **Table evidence is located by structural key** (`create-table:<name>#0`). EKOS's table evidence names the file only, with fragment `CREATE TABLE <name>` and no line. | EKOS evidence-location defect |
| 5 | **A merged object keeps only the survivor's evidence in EKOS.** `ekos query object` on customers lists `src/shop/ecommerce.sql` only, and the legacy definition appears only in the conflict's claims. The mapper adds the legacy evidence by structural key. | EKOS defect (provenance lost on `duplicate_definitions` collapse) |
| 6 | **Edge evidence.** The export carries none for `ForeignKey` edges (`graph_export.rs` emits source/target/kind). The mapper cites the referencing table's own statement when its text contains `REFERENCES <to>`. | EKOS export gap |
| 7 | **Conflict claims** carry `path` with `line: null`. The mapper pins the subject table's `create-table` statement in the source whose rendered path matches `src/<key>/<path>`. | EKOS evidence-location defect |
| 8 | **Room placement.** The export has no per-object source attribution: the `source`/`sources` properties are absent on every node of this workspace. A table therefore goes to the room of its first defining source in `[[sources]]` order, so `customers` went to `shop`. Conflicts and the manifest go in no room. | both: EKOS export gap; the placement rule is mine |
| 9 | **The properties atom of a merged object holds the survivor's values**, chosen by EKOS's input order (`chosen_by_ekos: varchar(255)`). Here it is shop-derived, so `reader-shop` seeing it leaks nothing. If legacy had won, legacy-derived bytes would sit in a shop-room cell: properties are compiled bytes, not transclusions, so admission does not scope them. | design limit of admission-level P8 |
| 10 | **Two conflicts, not one.** EKOS emitted `customers.columns` (the column set differs) and `customers.columns.email.data_type`. `UNIQUE` is not compared. The mapper maps both. The email-type conflict is the R5 subject, and the column-set conflict is its control. | EKOS behaviour, observed (not a defect) |
| 11 | **Statement atoms: 13 in shop**, not the exploration's 7: 6 tables, 5 indexes, and 2 comment blocks kept as `anon:<sha>` atoms so that rendering is byte-exact. Blank lines stay with the preceding statement. | schema choice here |
| 12 | **Nesting** is `createContainer` / `createAtom` / `transclude` (each appends to the root) followed by `editElement remove` from the root and `splice` into the container. That is two actions per child, which costs action budget (item 13). | deployed shape |
| 13 | **The client caps a content target at 64 actions** (`content proposal requires 1..64 actions`). The largest request here was 40 (`obj-order-items`). A wide table or many edges would need several commands per birth, but L-obj's birth clause wants the transclusion in the birth command. | schema gap here |
| 14 | **The manifest is under L-obj**, so its birth needs a transclusion. It transcludes each source header. Its external links use the EKOS object UUID as `authority`, not the logical key. | approximation of exploration §2.1 |
| 15 | **The compile-run record** holds the source atoms and revisions it read plus the command SHA-256. It does not record the read heights (the views carry `judgedAt.height`, unused). | schema gap here |
| 16 | **Recompile re-pins moved evidence.** It writes a new container and detaches the old one from the tree, and the old transclusion record stays. The `customers` cell therefore keeps both legacy pins: old `moved`, new `snapshot`. | design choice |
| 17 | **The review transcludes an `inlineObject` header atom.** The client renders it `[source fragment: unsupported content]`; the Host render and the pins are unaffected. | client display gap |

## The first run (run-1) and what it taught

- `run-1` was the debugging world.
- The first compile failed client-side with `mini: content identifier must be a decimal string`. `editElement`'s `index` had been sent as a JSON number, and the Host decoder wants a decimal string. Only the manifest, which has no element edits, landed.
- After the fix, the rest landed as compile `1b`, and R1-R7 all behaved on `run-1`.
- Because `run-1`'s compile was split, its replay mismatched as it should. That attestation is recorded `match: false` / `reconstructedApproximate`.
- `run-2` is the clean record. Both servers were stopped by their `server.pid` after checking `ps` args.

## Disk

hbox `/`: **30 G available (94 %) before and after**. Run roots are `run-1` 50 M and `run-2` 41 M, plus 256 K of code, all under `~/verekos-runs/slice1/`. Locally, `var/w17/` holds the EKOS scratch workspaces, the `run-1` debugging copies and about 3 M of `run-2` artifacts.

## What I could not do

- **Replay of compile 2.** It needs the compiled cells as they stood before the recompile. `workspace --action read` takes no `--at`, and `doc-show --at` returns a rendering, not entries. I replayed compile 1 only, whose pre-state is "every cell unborn".
- **Laws are not generated from Lean `Pred` values.** I used `verekos/laws/*.json`, checked by `laws/check.py`.
- **No lens layer.** R6 is admission only (grants and rooms). `Vis`, the scope theorem and `replayedDeterministic` as a computed label are not built; the label is a field the verifier writes.
- **The reviewer did not sign with `--remote`.** Its key is a file on hbox.
- **No law-replacement attempt by a non-owner** (see the laws section).
- **The law refusals do not name a single `LawLeaf` in text.** They print the whole installed law. The Host also shows each installed law wrapped as `any [ not (all [ open, open, open ]), <ours> ]`. I did not find where that prefix comes from.
- **No scale numbers.** The only latency here is about 17-24 s per propose+submit and about 5 s per grant (four client calls), with the box at load about 12.

## Artifacts

- **Committed:** `slice1/{mapper.py, laws.py, world-lib.sh, s2-setup.sh, s-import.sh, s-cells.sh, s-compile.sh, compile.sh, s3-refusals.sh, replay.sh, s4-attest.sh, s4-empty.sh, s5-review.sh, s5-r5.sh, s6-reader.sh, s-stop.sh, run.sh, ekos-compile.sh, ekos.toml, fixtures/legacy_customers.sql, inputs/{ecommerce.sql, legacy_customers.v2.sql}}`.
- **Local, in `var/w17/` (gitignored, like `var/w7`):**
  - `run-2/`: `receipts.tsv`, `steps.tsv`, `run.log`, `principals.json`, `cells.json`, `manifest.json`, `laws/`.
  - `run-2/compile-{1,2}/`: `export.ndjson`, `plan.json`, `req/*.json`, `commands.json`.
  - `run-2/`: `refusals/`, `r5-*/`, `r6/`, `review/`, `replay-1/`.
  - `run-2/receipts/world/*/attempts/*/{outcome.json, pre-submit-refusal.json, .frame, intent.json}`.
  - `c1/export.ndjson` and `c1/conflicts.json`, from the step-0 local EKOS run.
- **On hbox:** `~/verekos-runs/slice1/{run-1, run-2}` (full Store roots) and `code/`.
