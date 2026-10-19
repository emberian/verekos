# W24 — the slice-1 mapper and laws, in Lean (`map/`, `verekos-map`)

**Summary (5 lines).**
1. `verekos-map` (Lean, `map/`) writes every file `slice1/mapper.py` and `slice1/laws.py` wrote on run-2, **71 of 71 byte-identical**: compile 1's nine requests (concatenation SHA-256 `bcd84c6407873338f39a80edc4eacadd836dca7ec48f8c1f40909b8d43778443`), compile 2's three (`2d0da4d2a60b05f81338847039871a3c527c8142d09085c7fa3e09f2c5a048a9`), the replay, `plan`, `render`, three imports, both compile-run records, the attestation, the review, `split` and `id`.
2. Cell contents are computed by the World shapes (world pinned at `cd753c1`, WorldCore only, no Mathlib linked): `toDocument`, `encodeConflict`, `Manifest.compile`, `importSource`/`reimport`, `ReviewDoc.append`, `replayedDeterministic`. The conflict signature is the model's `sigOf`, and it equals EKOS's on both conflicts (otherwise the header bytes would differ).
3. The laws are `Minidregg.Pred.Pred` values (minidregg's own type, not a copy). Rendered, they are byte-identical to `laws/L-{src,obj,rev,run}.json` (hand layout included) and to the five law files installed on hbox; `laws/check.py` passes on the generated files; `MapProofs.lean` runs minidregg's `eval` on them and they refuse R2 and R3 and admit the controls (by `decide`, six concrete states).
4. One deliberate difference: an import that **adds** a statement folds it into the preceding atom with `editAtom`, because the client refuses mapper.py's `insertRun` (`native/resource-client/src/content_privacy.rs:83`, lane A). No receipt covers that path.
5. Clean build 11.2 s wall (56 jobs). Untrusted: the JSON renderer, the view/export parser, the SQL splitter; each says so in its docstring.

## Receipts

`bash map/receipt.sh` (from the repo root; reads `var/w17/run-2/`, writes `var/w24/receipt/`, exits 0 only when every row is `same`). Full table in `var/w24/receipt.tsv`. Selected rows (SHA-256 of the Lean output):

| File | SHA-256 |
|---|---|
| compile-1, 9 request files concatenated | `bcd84c6407873338f39a80edc4eacadd836dca7ec48f8c1f40909b8d43778443` |
| compile-2, 3 request files concatenated | `2d0da4d2a60b05f81338847039871a3c527c8142d09085c7fa3e09f2c5a048a9` |
| replay-1, 9 request files concatenated | `bcd84c6407873338f39a80edc4eacadd836dca7ec48f8c1f40909b8d43778443` |
| compile-1 `commands.json` / compile-2 `commands.json` | `fcc58020…` / `7e6fa87d…` |
| compile-1 / compile-2 `compile-run.req.json` | `3b010e6d…` / `7412f55f…` |
| import-1 shop / legacy, import-3 legacy | `e25fea4b…` / `f3d6ee2f…` / `791b920a…` |
| `attest.req.json` / `review.req.json` | `9ba32906…` / `ee9fd1ff…` |
| `plan.json` (both compiles) | `99406f39…` |
| installed `L-obj`, `L-rev`, `L-run-compiler`, `L-run-verifier`, `L-src` | `8e1fb895…`, `1b167ec8…`, `9b8af3f8…`, `cbae1f5c…`, `03eee917…` |
| `laws/L-obj.json`, `L-rev`, `L-run`, `L-src` | `3670e540…`, `60160b57…`, `3c549b56…`, `ac9f58cd…` |

Also identical: every individual request file, both `commands.sha256`, the stdout line of every command, the six rendered source files, import-2 (both "nothing to submit") and import-3 shop.

The laws are byte-identical, not just equal after reformatting. The layout of `laws/L-*.json` is reproduced by a rule I fitted to the four files (two-space indent, string arrays on one line, a leaf predicate on one line when it is a list element at least two lists deep). The installed files are `json.dumps(sort_keys=True)`.

**Control.** Before writing any Lean I re-ran `mapper.py compile` on the same inputs; it reproduced the committed files (`diff -r` empty), so the target was stable.

**One input note.** The compile-run record holds `mapper_sha256`, the SHA-256 of the mapper file. The run used `slice1/mapper.py` as of `fc8c7e1` (SHA-256 `c9264a14…`; the committed file at `58a0d62` differs only in a docstring and hashes `7ceeb05f…`). The Lean takes the file to hash as `--mapper-file` (default: its own executable). The receipt passes the `fc8c7e1` version, extracted with `git show`.

## Where the model's values come from (map/VerekosMap/Model.lean, Render.lean)

Carriers: everything is a string. A source is its key (`shop`), a range is a statement's structural key, an atom revision is (atom id, revision string), and a claim id is the logical key `sql-analyzer-table:<name>`.

| Cell | Model value | Rendered by `Render.lean` from it |
|---|---|---|
| `obj-*` | `toDocument derivation edgeView tableClaim edgeClaims`. The table claim's pins are `.source key (some structural) / .atoms [(atom, rev)] / 1000`; each FK edge is a claim `[from, kind, to]` whose pins are the defining statements that say `REFERENCES <to>` | header from `cell.header` + payload; properties from the payload; one container per `cell.evidence`; per `EdgeContainer` the edge atom (status, window → `valid_from`/`valid_until`), the link to `ec.link`, its evidence |
| `cf-*` | `encodeConflict sigOf k`, where `sigOf` is EKOS's `conflicts.rs:162-171` signature (SHA-256 of `{"attribute":…,"claims":[[value,path,source],…]}`) | header (subject, attribute, type, **signature from the model**), one container per member, the `Disputes` link to `D.disputes` |
| `manifest` | `Manifest.compile` over the manifest decoded from the current document (empty at birth) | one external link per entry that `compile` adds |
| `src-*` | `importSource` at birth; `reimport` on re-import, against the current document decoded into a `SourceDoc` (a key is re-derived from each atom's text, and an atom whose id is not derived from its key is refused, i.e. `WellKeyed` is checked) | births; `editAtom` for a changed revision; tombstones for keys that are gone |
| `review` | `ReviewDoc.append` of one `ReviewEntry` (verb as a `Status`) | the decision container |
| `compile-run` | a `CompileRunDoc` (inputs = header pins, command = the digest) | record atom and header transclusions |
| `attestation` | `ReplayAttestation`; `liveness` is `decide (replayedDeterministic run [att])` | the attestation container |

## The 17 approximations (W17 memo), reproduced exactly

1 (ids: SHA-256 `VEREKOS/ID/v1`, 120 bits; `Bytes.lean num`), 2 (schema digests on `createDocument`), 3 (redaction not run; the header says so), 4 (table evidence by structural key `create-table:<name>#0`; `Render.defining`), 5 (legacy evidence added to a merged object), 6 (edge evidence by a `REFERENCES <to>` search; `referencesName`), 7 (conflict claims pinned to the subject's `create-table` statement), 8 (room = first defining source), 9 (properties are the survivor's), 10 (both conflicts mapped), 11 (13 statement atoms incl. two `anon:` comment blocks; `Split.lean`), 12 (`createContainer`/`createAtom`/`transclude` then `remove`+`splice`), 13 (no splitting at 64 actions; not checked, as in Python), 14 (the manifest transcludes source headers; authority = EKOS node id), 15 (no read heights: the model's `InputPin.height` is set to 0 and not rendered), 16 (recompile writes a new evidence container and detaches the old), 17 (the review transcludes an `inlineObject` header atom).

## What the Lean shapes could not express (taken from the inputs by the renderer)

- Evidence meta atoms: `pass`, `fragment_kind`, `located_by` (constants per role); the shape has weight and range only.
- Object header: `ekos_id`, `compiler`, `mapper` (in the payload or the context, not `ClaimKey`).
- Edge atom: `status: "confirmed"` and `properties: {}` (constants).
- Conflict: `subject_name`, `ekos_id`, `compiler` on the header; each claim's `path`, `line`, `claimed_by` (`ConflictMember` has value and pin only); the claim pin's range (`SnapshotPin` has no range).
- Manifest: the source-header transclusions (`Manifest` has links only); the link id uses the cell name.
- Source header: `cell`; `pipeline_logic_version: null` is the model's empty `pipeline` digest.
- Compile run: `mapper_sha256` and the full statement map (`inputs`); the model's `identity`, `outputs`' post roots and `height` are not rendered.
- Review: `pick` and `conflict_cell`; the model's `reviewer` is not rendered (the deployed decision never named it).
- Attestation: `claimed`/`match`; the model's `outputs` are empty on both sides, so the label reduces to "same command, and the replayer is not `compiler`".

## Where the Lean behaves differently from mapper.py (no run-2 receipt touches these)

- **Adding a statement on re-import**: `editAtom` folding into the preceding live atom (or the following one when the new statement comes first) instead of `createAtom` + `insertRun`. The fold refuses to grow an `anon:` atom, because its id is derived from its whole text. Caveat: after a fold, the model's `SourceDoc` has one atom per statement and the deployed document does not, so a later re-import of the same file sees the folded statement as missing again. Fixing that needs a client action that places a new atom in a run.
- **Non-ASCII**: where Python's Unicode `lower()`, `\w`, `\b` or `re.I` folding would decide a key, cell name or `REFERENCES` match, the Lean refuses with an error. The fixtures are ASCII (checked: 0 non-ASCII bytes in every input).
- **Manifest unlink**: if a compile stops emitting an object, `Manifest.compile` unlinks it. The Lean refuses, because no unlink action spelling is on record. mapper.py silently kept the stale link.
- **Attestation by `--replayer compiler`**: the model's label says `reconstructedApproximate`; mapper.py said `replayedDeterministic` whenever the digests matched.
- **Review verbs**: only resolve/confirm/reject/dismiss (they map to a `Status`); mapper.py wrote any string.
- **Pred constructors**: only eq/le/memberOf/not/all/any are rendered. The others are refused rather than spelled from memory.

## Deletion list for the root (twins with no remaining reader once lane A is done)

- `slice1/mapper.py`: replaced by `verekos-map` (every subcommand). Readers today: `slice1/{compile,replay,s-compile,s-import,s4-attest,s5-review}.sh` (switch to `map/.lake/build/bin/verekos-map` with the same flags; on hbox the binary must be built or copied, since it is a Mac build), `slice1/{s3-refusals,s5-r5,s6-reader}.sh` `idof` (→ `verekos-map id`), `reader/lib.py` and `reader/edit_as_importer.py` through the **vendored copy** `reader/vendor/mapper.py` (lane A's; a twin of the twin), and `check/slice1_log.py` (docstring only).
- `slice1/laws.py`: replaced by `verekos-map laws --owner … --verifier …`. Reader: `slice1/s2-setup.sh:31`.
- `laws/L-{src,obj,rev,run}.json` as sources: produced by `verekos-map laws --out laws` byte for byte. They stay as build output if `slice1/` still reads them. Keep `laws/check.py`: it is an independent spelling checker, not a twin. Keep `laws/L-*.md` (prose).
- I did not put a banner in `laws/*.json` because JSON has no comments, and a banner key would break `laws.py` and `check.py`. `slice1/mapper.py` has its banner.

## What was not verified

- Nothing generated by `verekos-map` was submitted to hbox; byte-identity with files that were accepted is the evidence.
- The `editAtom` fold for added statements was run once locally (`var/w24/addstmt/`: one `editAtom` whose payload is the previous statement plus the new one). It was not submitted.
- `MapProofs` is six concrete evaluations, not a theorem over all requests.
- The `split` diagnostic's Python `repr` is ASCII-only.

## Files

`map/{lakefile.toml, lake-manifest.json, lean-toolchain, Main.lean, VerekosMap.lean, MapProofs.lean, receipt.sh, README.md}`, `map/VerekosMap/{Json, Bytes, Split, View, Model, Render, Commands, Laws}.lean`. Scratch: `var/w24/` (`receipt/`, `receipt.tsv`, `build-*.log`, `diffreq.py`, `addstmt/`, `py/`, `lean/`).

## W25: the twins deleted (2026-10-19)

**Deleted** (`bddd85f`, `git rm`, named): `slice1/mapper.py` (721 lines with the banner), `slice1/laws.py` (41), `reader/vendor/mapper.py` (718, lane A's copy), `reader/vendor/VENDORED.txt` (6), `reader/remote/edit-atom.py` (18, replaced by `verekos-map edit-atom`). 1504 lines in all. `laws/L-*.json` stay committed as generated artifacts (`laws/GENERATED.md`); `laws/check.py` stays.

**Repointed** (`e86d32a`). Every mapping step now runs **on the Mac** with `verekos-map`. hbox only reads cells and submits the files it is sent, so no Lean toolchain, build or binary is needed on hbox. Shared helpers are in `slice1/mac-lib.sh` (`hread`: signed reads on hbox copied back; `hput`; `render_sources`; `map_compile`; `map_runrec`).

| Was (on hbox unless noted) | Now |
|---|---|
| `s2-setup.sh` called `laws.py` mid-setup | `s2-setup.sh` stops after enrolment; `laws.sh` (Mac) copies `principals.json` back, runs `verekos-map laws --owner … --verifier …`, sends `$RUN/laws/` + `laws.tsv`; `s2-cells.sh` (new) creates cells and grants |
| `s-import.sh` read + `mapper.py import` + submit | `import.sh` (Mac): reads via `hread`, `verekos-map import`, sends the request; `s-import.sh` only submits and reads after |
| `compile.sh` (Mac) `render`/`plan`; `s-compile.sh` `compile` + `runrec` on hbox | `compile.sh` does render, EKOS, plan, `compile` (current reads via `hread`), `runrec`; `s-compile.sh` submits the requests, `s-runrec.sh` (new) submits the record |
| `replay.sh` (Mac) `render`; `s4-attest.sh` `compile` + `attest` | `replay.sh` does render, EKOS, `compile`, the claimed-record lookup, `attest`; `s4-attest.sh` compares and submits |
| `s5-review.sh` `mapper.py review` | `review.sh` (Mac) reads and maps; `s5-review.sh` submits and renders |
| `s3-refusals.sh`, `s5-r5.sh`, `s6-reader.sh` `idof` (imported mapper.py) | **values computed on the Mac**: `ids.sh` writes `verekos-map id` for the 17 tuples to `ids.tsv`, and `run.sh` copies it to hbox `code/slice1/ids.tsv`; `idof` is a lookup in that file |
| `reader/lib.py` `import mapper as M` (vendored) | `lib.vmap(...)`: `id schema …`, `source --read` (statement keys and order), `structural-key` (the evidence-fragment guess), `table-cell`. A view reader `Doc`, a `Source` built from `verekos-map source`, and the export reader are small local code that parses JSON and derives nothing |
| `reader/edit_as_importer.py` ran the vendored mapper on hbox | maps on the Mac (`verekos-map import`, or `edit-atom` with `--atom-key`); `remote/importer-edit.sh` has `read` and `submit` phases only |

New Lean subcommands for these callers: `source`, `edit-atom`, `structural-key`, `table-cell`, `runrec --mapper-sha256`.

**Receipts.**
- (a) `bash map/receipt.sh`: **95/95 same** after the deletions. It compares against the committed run-2 request files, `laws/L-*.json`, and `map/fixtures/` (the twin's `split` output for the three inputs, 18 ids, 6 structural keys and 3 table cells, recorded from the `fc8c7e1` twin just before deletion). The compile-run records now get `--mapper-sha256 c9264a14…` (the twin as it ran) as a value. Concatenations: compile-1 `bcd84c64…`, compile-2 `2d0da4d2…`, replay-1 `bcd84c64…`.
- (b) `bash slice1/dry.sh`: the Mac half of `run.sh`'s compiles and replay without hbox. From run-2's saved signed reads it renders the sources (byte-equal to run-2's `ws/` files), runs the unchanged EKOS pipeline afresh, plans and compiles through the same `mac-lib.sh` functions `compile.sh`/`replay.sh` call. Result: `commands.sha256` **bcd84c64… (compile-1), 2d0da4d2… (compile-2), bcd84c64… (replay-1)**; `plan.json` identical for both compiles; the runrec stdout lines equal the run's. About 12 s.
- (c) reader: no hbox run was needed. `var/w24/sync_offline.py` runs `reader/sync.py`'s own `main` with the node replaced by lane A's saved reads (`var/lane-a/reader/reader-shop/20261019T163112/cells`); EKOS runs for real. It prints **"7 documents, 46 atoms, 7 objects, 2 I could not read"**, and every field of the new `sync.json` except timings equals lane A's (cells, unreadable, files with statement keys/atoms/revisions, kinds, edges, conflicts, the crosscheck). `find`/`before`/`disagree` re-read pins live over ssh, so I did not run them; the mapper-touching code they use (`table_cell`, `Doc`) is covered by the fixtures and by sync.
- (d) `grep -rn mapper.py` outside `var/`, `.lake/` and `.git/` finds `notes/` history plus four files I do not own. The `map/` files now say "the Python twin". The four: `CLAUDE.md:18` (layout table: "driver scripts, `mapper.py`"), `project/PLAN.md:108,118,123,125` (the root's log), `docs/design/explorations/05-next-lanes.md:40-71` (a dated exploration), `check/slice1_log.py:7` (a docstring, lane B's). The root should reword `CLAUDE.md:18`; the rest are records.

**Not run, and why.** Nothing went to hbox: the drivers' hbox halves (`s-import.sh`, `s-compile.sh`, `s-runrec.sh`, `s4-attest.sh`, `s5-review.sh`, `s2-setup.sh`/`s2-cells.sh`, the `idof` lookups) are syntax-checked (`bash -n`) but not executed. A full `slice1/run.sh` on a fresh run root is the test of them, about 20 minutes and about 40 MB on hbox. Two side effects of the split: hbox-side row timings no longer include the mapper (compile passes `MAPSEC` instead), and a few run-root artifact names changed (`import-N/before/CELL.json`, `compile-N/cur/CELL.json`, `review/CELL.json`). `reader/vendor/__pycache__/` (lane A's untracked bytecode of the deleted file, git-ignored) is still there; I did not create it, so I left it.
