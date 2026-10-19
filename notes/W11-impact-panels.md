# W11 — impact panel from the runtime traversal tests

## Summary

Fourteen tests in `ekos/crates/runtime/src/lib.rs` whose names mention neighborhood, impact, dependents, or session, plus the doc-mention sibling `an_rfc_depends_on_link_is_a_real_dependent_but_a_bare_mention_is_not`, are panel `impact.unit`: inputs in `panels/impact/items.jsonl`, assertions in `controls/impact.expected.jsonl`.
Each item is `{objects, relationships, query}` with `query` `{seed, direction, kinds, max_hops}` and, where the test calls `load_neighborhood_bounded`, `max_objects`. Ids are fixed stand-ins for `Uuid::new_v4`, recorded in `expect_from_test`.
`direction` is `Dependents` or `Dependencies` for `trace_impact`, `neighborhood` for `load_neighborhood` (root included), and `related` for `related()` (that walk, root removed). `kinds []` means the function takes no kind filter; a `dependents()` call is written with `DEPENDENT_KINDS`.
26 items, 26 control lines. The drift record hashes the 15 functions at EKOS `8e3c178`; `--update` and the check both exited 0 with `drifted: 0`.
Two session tests and the non-walk asserts inside the session-memory test are not items. No test in this file is named pending or traversable.

## Test → item → assertion

| test | item | assertion (the test's own) |
| --- | --- | --- |
| `load_neighborhood_depth_0_is_root_only` (`:950`) | same | `objects.len()==1`, `relationships.len()==0` on `load_neighborhood(a, 0)`. The one object is a. |
| `load_neighborhood_excludes_unconfirmed_same_as_but_keeps_confirmed` (`:969`) | same | ids exclude b, include c |
| `load_neighborhood_depth_1_returns_direct_neighbours` (`:998`) | same | `objects.len()==2` ("a and b; c is 2 hops away"), `relationships.len()==1` |
| `load_neighborhood_depth_2_returns_two_hops` (`:1016`) | same | `objects.len()==3` ("a, b, c; d is 3 hops away"), `relationships.len()==2` |
| `bounded_neighborhood_truncates_reports_it_and_keeps_no_dangling_edge` (`:1039`) | same | `truncated`, `objects.len()==3`, `relationships.len()==2`, no edge leaves the object set |
| `bounded_neighborhood_under_budget_equals_unbounded` (`:1065`) | same | `truncated==false`, and the bounded call's object-id vec and relationship-id vec equal the unbounded call |
| `load_neighborhood_handles_cycles` (`:1087`) | same | `objects.len()==2` ("cycle must not loop forever") |
| `trace_impact_dependents_and_dependencies_are_disjoint` (`:1102`) | `#dependents` | `trace_impact(b, Dependents, [], 5)` has len 1 and object a |
| same | `#dependencies` | `trace_impact(b, Dependencies, [], 5)` is empty |
| same | `#a-dependencies` | `trace_impact(a, Dependencies, [], 5)` has len 1 and object b |
| `trace_impact_excludes_unconfirmed_same_as_but_keeps_confirmed` (`:1139`) | same | hop ids exclude unrelated, include reviewed |
| `trace_impact_skips_doc_mention_edges` (`:1170`) | `#dependents` | `dependents(symbol, 3) == [caller]` |
| same | `#related` | `related(symbol, 1)` contains the section |
| `an_rfc_depends_on_link_is_a_real_dependent_but_a_bare_mention_is_not` (`:1212`) | same | `dependents(rfc15, 2) == [builds_on]` |
| `trace_impact_filters_by_kind` (`:1239`) | same | `trace_impact(a, Dependencies, [ForeignKey], 5)` has len 1 and object b |
| `trace_impact_handles_cycles` (`:1270`) | same | len 1 ("cycle must not loop forever") and object b |
| `trace_impact_max_hops_bounds_traversal` (`:1288`) | same | len 2 ("only b (hop 1) and c (hop 2) within bound") and every `hop <= 2` |
| `session_memory_is_absent_from_every_object_read_path` (`:1687`) | `#neighborhood` | `load_neighborhood(orders, 3)`: no object has a session kind |
| same | `#bounded-1`, `#bounded-2`, `#bounded-max` | the same assert on `load_neighborhood_bounded(orders, 3, budget)` for `1`, `2`, and `usize::MAX` |
| same | `#bounded-claim` | `load_neighborhood_bounded(claim, 3, 10)` has an empty object list |
| same | `#dependents` | `dependents(orders, 3)` has len 1 and id refunds |
| same | `#related` | every id from `related(orders, 3)` is refunds |
| same | `#impact-claim` | `trace_impact(claim, Dependents, [], 3)` is empty |
| same | `#neighborhood-claim` | `load_neighborhood(claim, 3)` has an empty object list |

## Counts

- 15 test functions, 26 panel items, 26 control lines.
- By direction: neighborhood 13, Dependents 6, Dependencies 5, related 2.
- `max_objects` is set on 6 items (the two bounded-neighborhood tests, and four of the session items).
- Drift: 15 functions. Populate (`--update`) exit 0, `{"updated": 15, "failures": []}`. Check exit 0, `{"functions": 15, "drifted": 0, "failures": []}`. Record `panels/impact/drift.json`, EKOS `8e3c178fc45741c7e2b1576e936646e0c461e75c`. The checker is `panels/transcribed/drift_check.py`; it already takes `--record`.

## What was not transcribed faithfully

- `session_edges_are_absent_from_every_relationship_read_path` (`:1777`) asserts that `list_relationships`, `list_relationships_at`, `relationships_for`, and `reconstruct_state` drop `AnchoredTo` and `ObservedIn`. That is not a `{seed, direction, kinds, max_hops}` walk, so it is not an item. The same for `every_object_returning_read_path_has_an_audited_session_decision` (`:1837`), which compares `pub fn` names in this file to a const list.
- Inside the session-memory test, these asserts are not items either: `load_object` of the claim and the session is `None` and of orders is `Some`; `reconstruct_state` and `reconstruct_state_at` of the claim are `None`; `object_history` of the claim is empty; `list_objects` and `list_objects_at` are exactly orders and refunds; `build_world` over all four ids has 2 objects and 1 relationship.
- No test in this module is named `pending` or `traversable`. `is_traversable` (`:148`) is the predicate the neighborhood and session walks assert. `is_pending_review`'s own tests are `kir/src/lib.rs:916-967`, a different file, and they were not transcribed.
- `named_graph_ops_respect_direction_edge_kind_and_hops` (`:880`) does call `dependencies`, `dependents`, `callers`, `related`, and `graph_op`, including the hop bound `dependencies(a, 1) == [b]` against `dependencies(a, 5) == [b, c]`. Its name matches none of the words, so it is not an item. `the_kind_prefilter_is_not_the_decision` (`:1810`) is the same: an `AnchoredTo` between two tables must survive `relationships_for`.
- `an_rfc_depends_on_link_is_a_real_dependent_but_a_bare_mention_is_not` says "dependent", not "dependents". It is an item because it calls `dependents()` and it is the other half of the doc-mention rule in the `:1102-1310` span the design names.
- `dependents()` does not take a kind list. The query writes `DEPENDENT_KINDS` (`DependsOn`, `Calls`, `ForeignKey`, `References`, `lib.rs:464`), which is what that function passes to `trace_impact`. `dependencies()` would also pass `Contains`; no transcribed test calls `dependencies()` except through `trace_impact` with `&[]` or `[ForeignKey]`.
- `query.max_objects` is not in the envelope. Without it the bounded tests are a different call. `usize::MAX` is `18446744073709551615`.
- The truncation test does not say which two of `spoke0`..`spoke4` survive. `relationships_for` (`ledger/src/lib.rs:762`) has no `ORDER BY`. The control is the counts and the no-dangling assert, not a spoke set.
- Several asserts are weaker than the walk. `related`'s `all(|o| o.id == refunds)` is true of an empty vec. The session neighborhood asserts no session kind, which an empty graph also satisfies. The determined walks are described in `expect_from_test` and are not extra expect fields.
- Where a test checks `len` and an id but not `hop`, the control still carries hop 1, because `trace_impact` sets `hop` to `current_depth + 1` and the root is not emitted. `expect_from_test` says the test did not assert it.
- Kinds are the `Display` / `FromStr` spelling: `Table`, `ForeignKey`, `SameAs`, `Session`, `SessionClaim`, `AnchoredTo`, `ObservedIn`. `Custom` is `#[serde(untagged)]` on the variant (`kir/src/lib.rs:116`, `:142`), so that spelling is a bare JSON string. This lane did not round-trip a value through `serde_json`.
- `created_at` (`Utc::now()`) and empty `evidence` are omitted. The walks do not read them.

## EKOS commit

`8e3c178fc45741c7e2b1576e936646e0c461e75c` (`8e3c178`).
