# W20: the ledger versions dump — lane memo (2026-10-19)

1. `control-dump ledger <workspace-dir> [--panel panels/ledger/items.jsonl]`
   opens the workspace's fact store READ-ONLY (`FactLedger::open_read_only` on
   `.ekos/ledger/facts`, exactly where the CLI's `facts_dir` points) and prints
   one control line: per object (sorted by id) the id, kind, name, version count
   (`object_history` length), a locally recomputed `content_signature` per
   version plus a no-evidence variant, and every version's evidence id list;
   the workspace totals; and `diff(epoch, now)` as a sorted id list.
2. `content_signature` is `pub(crate)` (ekos-ledger lib.rs:47-53): recomputed
   locally — strip top-level `created_at` (3 lines here), then hash with EKOS's
   own exported `ekos_artifact::ArtifactId::compute`. Two self-checks on every
   line falsify a wrong recomputation: adjacent versions must differ in
   signature (FactLedger appends only when the signature moves,
   fact_ledger.rs:722-724) and `get_object` must equal the last history
   version. Both pass on all controls.
3. Both fixtures' controls (`controls/ledger.<name>.versions.control.jsonl`,
   the untouched W18 workspaces) are byte-identical across two runs, verified
   three times (manual ×2, full regen ×2); W18's trees hashed byte-unchanged
   after every dump pass (`var/w20/w18-workspaces-*.sha256`).
4. EKOS#10 reproduced and classified: `ekos clean` (empties
   `.ekos/artifacts` incl. the pass-manifests that gate `should_recompute`;
   the ledger is untouched — clean.rs removes only the artifact dir) followed
   by recover/resolve/compile/commit on unchanged sources forked a version of
   every Table; the difference is in `controls/classified.jsonl`
   (diff_id `07e3cb27…`), with score.py runs recorded unexplained-then-classified.
5. The controls are registered: `regen_controls.py`'s `LEDGER_REGISTRY` is a
   second entry kind (workspace dir + fixture panel, no expected file) sharing
   `drive(entry, runner)` with the six panel entries — same double-run
   byte-identity, committed-control comparison and `--accept` semantics;
   `panels/LABELS.json` and `docs/parity/BOARD.md` updated (full regen green:
   nine controls identical, all drift checkers exit 0).

Spec: design §1 rows P1/P2/P4, §6; exploration 03 §2.2. Commands: this memo.
Prior lanes: `notes/W18-fixture-pipeline.md` (the workspaces),
`notes/W5-control-dump.md` (the control binary's rules).

## Per-fixture counts (the committed controls: one pipeline run, no re-runs)

| fixture | objects | versions | relationships | evidence | entries |
|---|---|---|---|---|---|
| ecommerce | 8 (6 Table + 2 File) | all 1 | 6 | 14 | 28 |
| northwind | 15 (13 Table + 2 File) | all 1 | 13 | 28 | 56 |

`diff(epoch, now).touched` lists every object and relationship id (nothing
predates the single commit); `added` is the full entry-id list 1..28 / 1..56.

## The EKOS#10 reproduction (var/w20/ecommerce, a copy of W18's workspace)

Sources never touched: the dump's own provenance check (fixture sha256
`accad143…` against `panels/ledger/items.jsonl`) passed before and after.
Driver: `var/w20/run-repro.sh` — `ekos clean` then the four stages, release
binary `03cf977b…` (W18's pin), `nice -n 10`, logged under
`var/w20/ecommerce/logs-w20/`, `EKOS_HOME` = the copied scratch home, the five
leak-suite selectors scrubbed.

| kind | name | before | after |
|---|---|---|---|
| Table | categories, customers, order_items, orders, payments, products | 1 | **2** |
| File | ekos.toml, schemas/ecommerce.sql | 1 | 1 |

Totals 28→52 entries, 14→26 evidence. Entry arithmetic says the 6 relationships
forked too (52−28 = 6 object versions + 6 relationship versions + 12 evidence);
relationship history is not in the control (objects only), so this half is
inferred, not pinned.

The exact field — customers (`f8dd66c6-8d25-54cc-a18a-282ec7b1100a`), evidence
id list per version:

- v1: `["a5e8f77f-1616-48fb-a0b6-0cb3f2a00714"]`
- v2: `["11ce6850-e338-40a7-a571-130614cb6d16"]`

`version_signatures` moved (v1 `e73b63b8…`, v2 `7a6669ee…`) while
`version_signatures_no_evidence` stayed byte-equal (`f6e3f621…` on both) for
every table — the evidence id list is the *only* payload change (volatile
`created_at` already stripped). v2's evidence id differs per reproduction
(`834d2a7d…` in the first run, `11ce6850…` in the second): the mint is random.
The File objects did not fork — their re-derived evidence stayed stable, so
only the sql-analyzer's table evidence carries the defect.

Scored with score.py against the panel (`var/w20/score-run{1,2}-*.log`):
unclassified `{mismatch:1, unexplained:1}` exit 1 → entry added →
`{classified:1, unexplained:0}` exit 0. The control side of that pair is the
W20 before-dump (`var/w20/ecommerce/versions-before.jsonl`); the committed
control remains the untouched W18 workspace's dump, which is byte-different
from the before-dump only in the `workspace` path field.

## What I could not do

- Relationship version history per edge (`relationship_history` exists; the
  control pins objects only, per the task's shape) — the EKOS#10 relationship
  half rests on entry arithmetic plus commit's "Relationships written: 6".
- Nothing observes the orphaned old evidence records directly (the 14 original
  evidence ids remain in the store, unreferenced by any current object; only
  the counts show 14→26).
- `ekos clean`'s own ledger-preservation was verified from source (clean.rs
  removes only `artifact_dir`) and from the growth being confined to the
  post-clean stages; I did not snapshot the facts dir between clean and
  recover.
- Incident, cleaned up: the reproduction driver's first version lacked
  `cd "$ws"`, so one `ekos` pipeline ran against the verekos repo root and
  wrote a scratch ledger at `/Users/ember/dev/verekos/.ekos` (62 files). It
  was created 15:45:50 by that run and removed by me the same minute; nothing
  tracked and no other lane's file was touched (`git status` clean of it).
- The MySQL/docs/git fixtures and the W18 controls' self-scoring on the board
  remain as W18 left them (whole-workspace artifacts; the board rows carry —
  numbers with the detail sections doing the work).

## Build time

`nice -n 10 cargo build` in `tools/scoreboard/control-dump` (one at a time):
12.49s initial (ekos-artifact/sha2/hex added), 2.19s + 0.78s for the
no-evidence-signature revision; logs appended to `var/w20/build-ledger-dump.log`.
Full `regen_controls.py` run: all nine controls + drift checkers in ~40s.
