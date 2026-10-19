# W18: the fixture pipeline — lane memo (2026-10-19)

1. `tools/scoreboard/run_fixture.py` (python3 -I, `run` / `compare`) drives one
   fixture through the real six-stage pipeline (`ekos init && build && recover
   && resolve && compile && commit --yes`) in a scratch workspace under
   `var/w18/<name>/ws` with a scratch `EKOS_HOME` and the five env selectors
   the leak suite scrubs removed; every invocation runs `nice -n 10` and is
   logged and timed per stage.
2. The controls it writes (committed as `controls/ledger.<name>.*`): the graph
   export ndjson (`--max-nodes/--max-edges 1000000 --first-seen`, truncation
   checked and fatal), the EKL object and relationship rows **sorted by id and
   canonicalized** (`sort_keys` — the rows come out of a HashMap whose key
   order varies per process), `ekos status --json`, `ekos conflicts list
   --json`, and a sidecar pinning binary sha256 `03cf977b…`, EKOS `8e3c178`
   (clean), fixture sha256, per-stage wall-clock, and the volatile-field list.
3. Both fixtures reproduce EKOS's own stated numbers: ecommerce 6 Tables (+
   2 File objects = 8 nodes) and 6 ForeignKey edges — the integration test's
   exact claim; northwind 13 Tables (+ 2 File = 15) and 13 edges, its "at
   least 13" floor met exactly.
4. Reproducibility (§3.5-3): a second ecommerce run in a fresh workspace is
   **content-identical** — same ids, names, kinds, degrees, edge multiset,
   EKL rows (byte-identical after canonicalization), counts and conflicts; only
   named volatile fields moved (exact list below). No `ekos_defect`
   classification was warranted: the EKOS#10 evidence-id randomness never
   reaches these controls (why, below).
5. Not registered in `regen_controls.py`: the registry's entry shape drives
   `control-dump <sub> <panel> --expected`, and the ledger control comes from
   the real binary via `run_fixture.py`, not a dump subcommand — wiring it in
   means editing `control-dump/` (lane W12's tree, forbidden) or adding a new
   entry kind. Registration sketch for the root at the end.

Spec: `docs/design/explorations/03-scoreboard.md` §1.3-1.4, §2.1-2.3, §3.5.
Commands: `tools/scoreboard/run_fixture.py` docstring.

## Per-fixture counts

| fixture | objects | relationships | conflicts (`conflicts list --json`) | entries | evidence | kinds |
|---|---|---|---|---|---|---|
| ecommerce.sql | 8 (2 File + 6 Table) | 6 ForeignKey | `[]` (status: open 0 / resolved 0 / dismissed 0) | 28 | 14 | File, Table |
| northwind.sql | 15 (2 File + 13 Table) | 13 ForeignKey | `[]` (0 / 0 / 0) | 56 | 28 | File, Table |

(The File objects are the workspace's own `ekos.toml` and the fixture copy —
the workspace observes itself per `ekos init`'s default `paths = ["."]`, which
this lane pins byte-identically rather than filtering.)

## Stage timings (wall-clock seconds, release binary, nice -n 10)

| stage | ecommerce (run 1) | ecommerce (rerun) | northwind |
|---|---|---|---|
| init | 0.012 | 0.012 | 0.013 |
| build | 0.342 | 0.258 | 0.329 |
| recover | 0.026 | 0.022 | 0.024 |
| resolve | 0.011 | 0.012 | 0.012 |
| compile | 0.024 | 0.029 | 0.024 |
| commit | 0.685 | 0.526 | 1.156 |
| *(controls)* graph-export / ekl-obj / ekl-rel | 0.013 / 0.011 / 0.012 | 0.015 / 0.012 / 0.012 | 0.014 / 0.013 / 0.013 |

commit dominates (it runs the conflicts pass, freshness manifest and segment
sealing); everything else is tens of milliseconds on fixtures this size.

## The reproducibility result (exact differing fields)

`run_fixture.py compare --a var/w18/ecommerce --b var/w18/ecommerce-rerun`
(exit 0; report kept at `var/w18/ecommerce-repro.json`):

- `graph.ndjson` header: `generated_at`, `workspace` — volatile, differ.
- `graph.ndjson` nodes: **all 8** differ in `fs` only (first-seen =
  `created_at`); `id`, `n`, `k`, `d` identical on every node. Edges: the
  (src id, tgt id, kind) multiset is identical; `fs` differs per edge.
- `objects.jsonl` / `relationships.jsonl`: **byte-identical** (after the
  documented id-sort + key-canonicalization).
- `status.json`: `workspace`, `last_write`, `freshness.committed_at`,
  `freshness.git_head_then`/`git_head_now` (the scratch ws sits inside the
  verekos repo, so this echoes *verekos*'s HEAD — it moved between the runs),
  `storage.total_bytes` (28537 → 28527) and `storage.components[0].bytes`
  (24239 → 24229; the fact segments embed timestamp strings). Counts
  (`entries 28, objects 8, relationships 6, evidence 14`), backend, conflicts:
  identical.
- `conflicts.json`: identical (`[]`).
- `content_identical_modulo_volatile: true`; content differences: none.

**Why the EKOS#10 evidence randomness is invisible here** (the "explain why"
branch — no `ekos_defect` entry was added, because no compared field moved):

1. Object ids are deterministic: `File` ids hash from the within-project
   relative path (project key empty for `paths = ["."]`), Table and ForeignKey
   ids are UUIDv5 over names (`table_kir_id` / `foreign_key_kir_id`,
   sql_analyzer.rs:303,316). Nothing that survives into the export or the EKL
   default returns is randomly minted.
2. The export shape drops the random parts: `Node`/`Edge` carry no evidence,
   no properties, no versions; `evidence_is_ignored_by_the_export` pins that a
   stray evidence record changes nothing (§1.4).
3. The EKL default returns are `id, name, kind` (objects) and `id, kind,
   from, to` (relationships) — no evidence, no `created_at`, no content
   signature.
4. The freshness/fingerprint cache is not even involved: each run is a fresh
   workspace, so nothing is skipped — the stability is of the pipeline, not of
   a cache.

That the randomness is real (just hidden) is demonstrated *outside* the
controls: `ekos ledger audit <table id>` on the **same id** in both
workspaces (kept as `var/w18/{ecommerce,ecommerce-rerun}/audit-categories.json`)
differs in `run_id` (`run-1792438372-6b97f879` vs `run-1792438390-82a96247`),
`source_artifact_id` (`ka:cfca6229…` vs `ka:4cd94535…` — the artifact JSON
embeds run-scoped values, so its content hash moves) and `written_at`. The
evidence ids themselves (14 minted per run, `KirEvidence::new` → UUIDv4,
EKOS#10 item 1) are observable through no CLI at all (§2.4) — the control-dump
lane's `get_evidence` walk is what will close that.

## What the export lacks, and how the EKL rows compensate

| lacking from `graph export` | compensated by the EKL rows? |
|---|---|
| relationship ids (edges are `s`/`t` node indexes) | **yes** — `FIND Relationship` returns `id, kind, from, to`, the exact ids the Branch/Ledger kernels key on |
| object properties (`columns`, `check_constraints`, `sources`) | **yes, if asked** — `FIND Object RETURN id, name, columns` returns full column definitions (probed this lane); the panel generator must name the fields, exactly like the export's `--include-property` |
| edge properties, incl. `status`/pending-review | **no** — neither shape carries edge properties; a pending `SameAs` is invisible in both (dump binary needed) |
| evidence | **no** — neither shape; `status --json` counts it (14/28) but no CLI lists it |
| versions / history | **partly** — EKL's `AS OF <ts>` answers point-in-time queries; full per-version history (`object_history`) has no CLI |
| events | **no** — nothing lists events (§2.4); no compensation exists |
| session objects | by design dropped (both) |

## Registering the ledger panel in regen_controls.py (for the root)

The `REGISTRY` entry shape is
`{sub, panel, expected, control, drift}` and `run_dump` invokes
`control-dump <sub> <panel> --expected <expected>`. The ledger control does
not fit it: there is no `control-dump ledger` subcommand (adding one means
editing lane W12's tree) and no transcribed-assertions `expected` file. The
registration I would make once control-dump is settleable:

```python
{"runner": "fixture",                  # new: dispatch to run_fixture.py, not control-dump
 "fixture": "/Users/ember/dev/EKOS/tests/fixtures/ecommerce.sql",
 "panel": "panels/ledger/items.jsonl", # upserted by the run (inputs only)
 "controls": ["controls/ledger.ecommerce.graph.ndjson", "…objects.jsonl",
              "…relationships.jsonl", "…status.json", "…conflicts.json"],
 "sidecar": "controls/ledger.ecommerce.sidecar.json",
 "repro": "second fresh-workspace run + run_fixture.py compare; the
           volatile-field list in the sidecar must cover every differing
           field or the regen fails (§3.5-3)"}
```

plus the same for northwind, the sidecars' `ekos_binary.sha256` /
`ekos.commit` folded into `controls/MANIFEST.json`, and a `--only ledger`
pass-through. Until then the committed controls stand as written (first run
kept; the rerun that validated them lives only under `var/w18/`).

## What I could not run

- `mysql_hash_comments.sql`, `sample_project/`, `sample_docs/`,
  `git_fixture/` (the bundle needs `git clone` materialization first — §1.3
  note (iv) flags this as unchecked): not in W18's task list; the driver
  takes any `.sql` today and any directory once the ws layout generalizes.
- The re-commit append-only check (`commit --yes` twice on one workspace,
  design §1.5's panel): not asked for here; the EKOS#10 caveat (evidence ids
  entering `KirObject`'s payload → content signature) makes it a dump-binary
  question, and `content_signature` is `pub(crate)`.
- Scoring the ledger controls with `score.py`: no kernel binary exists, and
  the controls are whole-fixture artifacts rather than the item-keyed JSONL
  score.py consumes — the panel's scoring contract is the root's to settle
  (this is why the board rows carry `—` numbers with a status).
- Evidence listing, event listing, `object_history`, per-relationship
  properties: no CLI surface exists (§2.4); all are control-dump work.
