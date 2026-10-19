# A: the reader-local compile (M1a), run for real against the slice-1 world

**Summary (5 lines).**
1. **It works end to end on the real world.** I restarted slice 1's own server (`run-2`, same Store), and `reader-shop`, who holds a room delegation on `shop` only, synced with its own signed reads: "7 documents, 46 atoms, 7 objects, 2 I could not read" (11 signed reads, 56 s on a box at load about 13). `src-legacy` and the conflict cell were refused `no-grant` by the Host. Nothing was written to the node by the reader.
2. **Three answers, each line ending in a pin the reader re-reads at answer time.** `find customers`, `before customers` (one and two hops, with stale-pin counts) and `disagree` (the reader sees 0, and says why that is not a zero for the world). The pin is `same bytes` or `moved`; it costs one signed read per cited cell (about 4-5 s each).
3. **The scene replays.** An importer edit of one shop statement turned the same pin to `moved` with the old and new line shown; a re-sync made it `same bytes` again. A second `customers` definition added by the importer made the reader's disagreement list go from 0 to 3; the restore took it back to 0.
4. **The re-sync cannot read only the changed cell.** The node offers no way to ask which cell changed except reading it. The sync probes one cell: if `judgedAt.worldRoot` is unchanged it stops after 1 read (A4a); if it moved, it re-reads all 11 (A4d). That is the brief's A4 expectation not met, and a precise negative (below).
5. **I changed the slice-1 world** (three importer `editAtom`s, now restored in text but not in revision). The compiler's `obj-customers` pin on the shop `customers` statement reads `moved` for everyone from now on. W17's R5 numbers cannot be replayed on `run-2` as it now stands. hbox disk: 30 G free before and after; `~/verekos-runs/reader/` is 1.6 M.

## What was built (all under `reader/`)

| File | What |
|---|---|
| `sync.py` | signed reads of every cell the reader's workspace names (`mini workspace --action list` then `read`), renders source documents, runs the unchanged EKOS pipeline (`init build recover resolve compile commit`, then `graph export`, `conflicts list`), records every atom's (document, atom id, revision, payload sha) |
| `find.py`, `before.py`, `disagree.py` | answers from the local ledger, each with pins re-read through `lib.recheck` |
| `leakcheck.py` | canary scan, planted control, EKOS queries (below) |
| `scene.py` | the replay, writes numbered outputs and `receipts.tsv` |
| `edit_as_importer.py`, `remote/importer-edit.sh`, `remote/edit-atom.py` | **world writes, scene only**, as the `importer` principal; not part of the reader |
| `lib.py`, `remote/read-cells.sh`, `reader.conf.json` | shared code; the reads run on hbox over ssh (the reader's key file is there) |
| `vendor/mapper.py` | W17's `slice1/mapper.py`, copied unchanged (sha256 in `vendor/VENDORED.txt`); the reader uses `Doc`, `Source`, `split`, `structural_key` and `num` from it |
| `README.md` | for a friend |

It differs from the brief in form: Python throughout, no `sync.sh`/`answer.py`/`check.py` split (the pin check is `lib.recheck`, called by every answer), and receipts in `var/lane-a/run4/receipts.tsv` rather than `var/reader/`.

## Receipts (run 4, the clean run; copies in `var/lane-a/receipts/`, git-ignored)

Each row's command line and full output is the numbered file in that folder. Timings are wall clock with hbox at load about 13; one signed read takes 3-6 s.

| # | Expected | Got | Seconds |
|---|---|---|---|
| A1 | `reader-shop` reads `src-shop`; `src-legacy` refused by the host | `src-shop` read (14 atoms). `src-legacy` and `cf-customers-columns-email-data-type`: `refused: no-grant: this key holds no grant covering this target and operation (phase observation)` | 56.2 (whole sync) |
| A2 | 6 tables, 0 conflicts; the compiler's compile of the same world has 2 (slice 1 `var/w17/run-2/compile-1/ekos/conflicts.json`) | **6 tables, 6 foreign keys, 0 conflicts**. The reader's local columns equal the compiler's `properties` atoms on 6 of 6 tables. The 0 is because the reader never had the second source; the cell `obj-customers` itself names `["shop","legacy"]` and `disagree` says so | 56.2 |
| A3 | `find customers` has a hit whose pin re-checks `same bytes` | 2 hits, `customers (Table)` pinned to `src-shop atom 357861120254… @ rev 109080494302…` `[guess: structural key]` and `ecommerce.sql (File)` pinned to the whole document; both `same bytes` | 4.7 |
| A4a | (added) re-sync with nothing changed | 1 signed read, nothing re-read, nothing recompiled | 5.1 |
| A4b | importer edits `email VARCHAR(255)` to `VARCHAR(320)` | `editAtom` accepted (world write, as `importer`) | 17.6 |
| A4c | the same pin re-checks `moved` | `moved (revision 109080494302… -> 802158875616…)` with `the answer said: email VARCHAR(255) …` / `now it says: … VARCHAR(320) …`; the file pin `moved (changed statements: create-table:customers#0)` | 5.1 |
| A4d | re-sync re-reads only the changed cell | **not met**: probe saw the root move (height 88 to 89) and re-read **all 11** cells. The change was found and named (`src-shop: edited ['create-table:customers#0']`); the reader's table `customers` then disagrees with the compiler's columns (5 of 6 agree), which is correct | 47.8 |
| A4e | after re-sync the pin re-checks | `same bytes` at the new revision | 3.8 |
| A5 | `before customers`, two hops, equals EKOS's own answer | ring 1 = `orders`; ring 2 = `order_items`, `payments` (via `orders`). Equal to `ekos query neighbourhood --depth 2`, and equal to the links the compiler wrote into the compiled cells the reader can read. **All three are EKOS or EKOS's export on the same copies: EKOS against itself** | 5.6 |
| A6 | `disagree` | 0 disagreements, then: "A zero over what I can read is not a zero over the world", and "obj-customers says 'customers' is defined in shop and legacy; I can read shop only. I do not know whether they disagree", with a pin on the compiled cell's header atom | 4.5 |
| A6c/d | (added) the importer puts a second `customers` definition in the shop statement | list goes 0 to **3** (`columns`, `columns.email.data_type`, `columns.id.data_type`), both claims pinned, EKOS's pick shown as "by input order" | 12.7 + 8.3 |
| A6f | the restore empties it again | 0 | 4.4 |
| A7 | nothing from `src-legacy` on this machine | `leakcheck.py` **PASS** (below) | 0.6 |

Re-check cost, measured: one signed read per cited cell, 3.4-5.9 s, so every answer adds that. A re-sync is 11 signed reads, 47-56 s, plus about 1-2 s of EKOS.

### The planted check

`reader/leakcheck.py` takes strings that occur in the legacy fixtures and in no shop document (`CITEXT`, `email  TEXT`, `id     INT PRIMARY KEY`; the script asserts none occurs in `ecommerce.sql`) and scans, in plain text and hex (the node's views carry payloads as hex), every file under the reader's state folder (287 files in run 4: views, renders, the EKOS ledger, exports, outputs). Hits: 0. Controls: the same scan over a planted folder holding the legacy fixtures finds all three; `ekos query find` for `legacy_customers` on a scratch ledger built from the legacy fixture alone finds `legacy_customers.sql`, and on the reader's ledger finds nothing named for it. The scan is blind inside compressed ledger segments; the EKOS query is the check there. It is not a proof: the reader's ledger could hold a legacy statement under a name the canaries miss. What makes it hold is that the legacy cell is never returned to the reader (`no-grant`), so the legacy bytes are never on the machine to leak.

One thing I did not expect: `obj-customers`, a compiled cell the reader may read, carries an evidence record `source_key: legacy, structural_key: create-table:customers#0` and a header listing `sources: ["shop","legacy"]`. That is the *name* of a document the reader cannot read, not its bytes (R6 of slice 1 shows the same). The reader's `disagree` reports it. Whether a friend should be told that a hidden source exists is a design question, not an EKOS one.

## What the reader cannot do

- **Publish the graph or let another friend query it.** The ledger is a folder on the reader's machine. No tool here writes anything to the node, and no other principal can reach the laptop.
- **Edit.** I did not try an edit as `reader-shop`; its delegation is `["observe"]` with `room: true` (`slice1/s2-setup.sh:57`), and `s6-reader.sh` shows the conflict cell refused. The scene's three writes are by `importer`, labelled as such in `scene.py` and `edit_as_importer.py`.
- **Read a cell it was not granted, or see which cell changed without reading it.** `mini workspace --action describe` returns the policy (`workspace.rs:6225`, view kind `"policy"`), `read` returns the whole cell (view kind `"resource"`), and `list` is the reader's local reference table. I found no call that returns a revision alone. The one cheap signal is `judgedAt.worldRoot` in any read. It moves for any write by anyone, in any room, so it is a conservative "something changed", not "this changed".
- **Check a pin if the node is down.** It prints `unchecked (the node did not answer…)`, a third word the brief did not ask for; I preferred it to calling a dead server `moved`.
- **Be fast.** 3-6 s per signed read here, serially over ssh. A friend with 40 documents (exploration 04 §4) would wait 2-4 minutes per full sync and 4-5 s per cited cell on each answer. I did not measure on an unloaded box.

## Where EKOS's export or evidence location forced a guess

| Where | Guess | W17's list |
|---|---|---|
| A pin for a table | EKOS's evidence for `customers` is `{"path":"src/shop/ecommerce.sql","line":null,"column":null,"fragment":"CREATE TABLE customers"}`. I turn the fragment into the structural key `create-table:customers#0` (`lib.pin_for_object`, using the mapper's own `CREATE` regex) and pin that statement atom. Every pin line says `[guess: structural key]` | #4 |
| A pin for a conflict claim | claims carry `path` and `value`, `line: null`. Candidates are the subject's statements in that file. After the second-definition edit both claims sit **inside one atom** (the importer cannot put two statements in separate atoms with a rename-free edit, see below), so the two claims get the *same* pin and the output cannot tell them apart: a visible limit of atom-granularity pins | #7 |
| Which source a table belongs to | here the reader's export does carry `source`/`sources` (one source, `shop`), so nothing is guessed on the reader's side; the compiler's room placement rule (W17 #8) is the compiler's guess and the reader inherits it through which cells it can see | #8 |
| Edges | no evidence on `ForeignKey` edges, so an edge answer has no pin of its own; `before` pins the *objects* on each ring | #6 |
| `ekos query find` | it is a loose name match (`legacy_customers` finds `customers`), and the file `ecommerce.sql` is a hit for `customers` because of the path. `--format` exists only on `query object`, not `query find`, so `find`'s output is parsed from text (`lib.parse_find`) | new |
| `ekos ekl ... VIA DependsOn` | finds nothing here: foreign keys are `ForeignKey` edges. `FROM 'name'` takes a **name**, not an id (`FROM anchor not found` for a UUID). I use `FROM 'customers' DEPTH 1/2` without `VIA`; EKOS's walk is undirected | new |
| Two statements with one structural key | `create-table:customers#0` and `#1` in one file make EKOS merge them into one object and report `duplicate_definition` conflicts; its `chosen` value is by input order, which I print rather than hide | #5, #9 |

## Approximations of my own

- The pin's `same bytes` is revision **and** payload SHA-256 equal. If an edit reverted text to the same bytes under a new revision, the revision differs and the pin says `moved` (it did, after the restore).
- `before`'s stale count is the number of pins in the compiled cell of each linked object that name the root's statement atom, counted at the sync's reads. It does not simulate a rewrite. `2 more pins … point into documents I cannot read` are the compiler's legacy pins in `obj-customers`; the reader cannot check them.
- The "plain-text mentions" column is a grep of the rendered text, not EKOS.
- Two edits to the world used two paths: `edit1` through the mapper's own `import` (one statement), `edit2` through `remote/edit-atom.py`, a one-action `editAtom` that puts two `CREATE TABLE customers` statements in one atom. The mapper's `import` uses `insertRun`, which the deployed client refuses ("unknown workspace content action", `content_privacy.rs:83`; `createRun` is allowed, `insertRun` is not). That is a slice-1 mapper defect for any import that *adds* a statement to a non-empty document, first seen here: slice 1 only added statements at birth. Not fixed (W17's file).
- The re-sync's skip rule (`worldRoot` unchanged) is mine. It is only as sound as `judgedAt.worldRoot` covering every cell the reader can read; I saw it change with every write.

## Disk

hbox `/`: 30 G available (94 %) before and after (`var/lane-a/receipts/disk-{before,after}.txt`). `~/verekos-runs/reader/` ended at 1.6 M after I deleted its scratch (`reader-shop-*`, `recheck-*`, `probe`, all created by this lane). `run-2`'s Store grew by the three importer commands and the reads' judged heights. Locally `var/lane-a/` is 12 M.

## What I could not run

- **The brief's A4 "re-reads only the changed cell"**: see above. A real fix needs a node call that returns a cell's current atom revisions cheaply (or a change feed); I did not look in `kn-gate` for one beyond `workspace.rs` actions `describe`, `read`, `list`, `tail`, `who`.
- **A friend principal enrolled with `--new-key`**: not needed; `reader-shop` already existed. Not tried.
- **The reader editing**: not tried (see above).
- **MCP over stdio** (`ekos mcp serve`): I used the CLI (`query find`, `query object --format json`, `ekl --json`, `query neighbourhood`, `conflicts list --json`).
- **`ekos_impact`** (multi-hop `trace_impact`): `ekl ... VIA` is the path to it and returned nothing for foreign keys. The two-hop answer is EKOS's undirected neighbourhood.
- **Prose documents, model summaries, hybrid/vector search**: out of scope; `find --mode hybrid` is passed through but untested (it needs `[embeddings]`).
- **Replay on an unloaded hbox**, any scale number, or a run as a second reader.
- **No theorem or panel number** is claimed. The A5 control is EKOS against itself.

## Follow-ups

1. Ask the node side for a cheap "cells changed since height H" (or revisions in `describe`); that turns A4 into 1 + k reads.
2. Mapper: `insertRun` is refused by the client; adding a statement to an existing source needs another route (`createRun` or element placement, as W17's R5 note on `splice` hints).
3. Decide what a reader should be told about a hidden source named in a cell it can read.
4. `lib.parse_find` should go when `ekos query find` gets `--format json`.
5. The world `run-2` is now at height 94 with the shop `customers` atom at a new revision; if W17's receipts are to be replayed, use a fresh run root.
