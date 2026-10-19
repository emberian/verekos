# W6 — branch panel from the merge_branch tests

## Summary

Three `merge_branch_*` tests in `ekos/crates/ledger/src/lib.rs` (2861, 2878, 2897) are panel `branch.unit`: inputs in `panels/branch/items.jsonl`, assertions in `panels/branch/controls/expected.jsonl`.
Each item is `{main, branch}` lists of `{id, name, kind, properties}`. Ids are UUIDv5 (`uuid.uuid5(NAMESPACE_URL, seed)`), standing in for `KirObject::new`'s random id.
`created_at` is not in the input. `content_signature` (`lib.rs:47`) drops it before hashing, and the tests stamp `Utc::now()`.
Expected reports are `{objects_merged, relationships_merged, conflicts}` plus `expect_from_test`. Counts: 3 items, objects_merged 1/0/0, relationships_merged 0/0/0, one conflict id.
`drift.py` populated `drift.json` at EKOS `8e3c178` (exit 0) and the check run reported `drifted: 0` (exit 0).

## Test → item → assertion

| test | item | assertion (the test's own) |
| --- | --- | --- |
| `merge_branch_adds_new_objects_from_branch` (`lib.rs:2861`) | `adds-new` | `report.objects_merged == 1`; `report.conflicts` is empty; `main.object_count() == 2` |
| `merge_branch_flags_diverged_objects_as_conflicts` (`lib.rs:2878`) | `flags-diverged` | `report.objects_merged == 0`; `report.conflicts.len() == 1`; `report.conflicts[0].object_id` is the shared orders id |
| `merge_branch_is_noop_for_identical_objects` (`lib.rs:2897`) | `identical-noop` | `report.objects_merged == 0`; `report.conflicts` is empty |

`relationships_merged` is 0 on every line. None of the three tests assert it; none append a relationship, so the report field stays at its default.

## Ids

UUIDv5, URL namespace, seed `verekos.branch/<function>/<role>`:

| seed | id |
| --- | --- |
| `…/merge_branch_adds_new_objects_from_branch/main/customers` | `59195f83-24f8-5f83-8f1b-9aa2f4301756` |
| `…/merge_branch_adds_new_objects_from_branch/branch/orders` | `45356cb2-e87d-5677-a17a-0e3d56ec286e` |
| `…/merge_branch_flags_diverged_objects_as_conflicts/orders` | `fb1e850a-d3d3-5698-9fec-95a942ae1876` |
| `…/merge_branch_is_noop_for_identical_objects/orders` | `9465d25d-abd3-5299-9a6e-75f6a9eaa7e9` |

The diverged and identical items use one id on both sides, because those tests append the same `KirObject`. The add test uses two ids, because it calls `KirObject::new` twice. Only equality of ids matters to `merge_branch`; the particular values do not.

## content_signature

`content_signature` (`ekos/crates/ledger/src/lib.rs:47`) is the SHA-256 (`ArtifactId::compute`) of the payload's canonical JSON with the `created_at` field removed, so two objects that differ only by that stamp are the same content.

`merge_branch` (`lib.rs:1621`) adds an id missing from main, skips an id whose signature matches, and records a conflict (it does not overwrite) when the same id has a different signature. That comparison is what makes the diverged item a conflict: main has `properties: {}`, branch has `properties.row_count = 5` on the same id, which is the mutation the test performs after appending to main.

## Counts

- 3 test functions transcribed, 3 panel items, 3 expected lines.
- 4 distinct ids, 6 object appearances (one on each side of each item).
- `objects_merged`: 1, 0, 0. `relationships_merged`: 0, 0, 0. `conflicts`: `[]`, `[fb1e850a-…]`, `[]`.
- Drift: 3 functions hashed. Populate exit 0. Check exit 0, `drifted: 0`.

## Drift runs

Populate (`python3 -I panels/branch/drift.py --ekos /Users/ember/dev/EKOS --populate`), exit 0:

```
{"populated": 3, "record": "/Users/ember/dev/verekos/panels/branch/drift.json", "ekos_commit": "8e3c178fc45741c7e2b1576e936646e0c461e75c"}
```

Check (same command without `--populate`), exit 0:

```
{"record": "/Users/ember/dev/verekos/panels/branch/drift.json", "functions": 3, "drifted": 0, "failures": []}
```

Hashes (span is the `#[test]` line through the `    }` at that indent):

| function | sha256 |
| --- | --- |
| `merge_branch_adds_new_objects_from_branch` | `d15145bd52ca6c77139647521eaba37ddfa495abd78eb3a092df927c80d8d5d6` |
| `merge_branch_flags_diverged_objects_as_conflicts` | `cbc9dd16c0469c014ec785bdbf2eb37af6293ec1c4a80d4eb07ee60c6f63f998` |
| `merge_branch_is_noop_for_identical_objects` | `19635a010a436b138d3e5ada920f38edf1ed8a4c129939d352e7a1468fec8e3d` |

A copy of those three spans, not the EKOS tree, was then renamed and edited: the checker exited 1 with `merge_branch_is_noop_for_identical_objects: disappeared` and `merge_branch_adds_new_objects_from_branch: hash changed`. That copy was deleted.

## What was not transcribed faithfully

- The tests' ids and timestamps are not constants. `KirId::new()` and `Utc::now()` inside `KirObject::new` were replaced by the fixed ids above, and `created_at` was left out. `expect_from_test` on each expected line says so.
- `evidence` is omitted. Every `KirObject::new` in these tests leaves it empty, and the field is `#[serde(default)]`, so a deserializer fills `[]`. It is part of the signature when present; the empty default is the test.
- `KirObject.created_at` has no serde default. A runner that builds a real `KirObject` must stamp one. Any stamp is signature-equivalent.
- `main.object_count() == 2` on the add test is a ledger side effect, not a `MergeReport` field. It is in `expect_from_test` and not a separate expected column.
- The conflict's `reason` (`"object diverged between branches"`, `lib.rs:1643`) is not asserted by the test. `conflicts` is a list of ids only.
- No `merge_branch_*` test appends a relationship, so there is no `from`/`to` to transcribe. `merge_branch` does walk relationships (`lib.rs:1651`) and would conflict them under `MergeConflict.object_id` set to the relationship id. That path is unmeasured. The design's extra relationship items and the generated ecommerce family (`03-scoreboard.md` §1.5) are not these tests; they were not invented here.

## EKOS commit

`8e3c178fc45741c7e2b1576e936646e0c461e75c` (`8e3c178`), the checkout `drift.json` was populated from.
