# W16 — EKL panels from the parser and interpreter tests

## Summary

The 26 `#[test]` functions in `ekos/crates/ekl/src/parser.rs` and the 32 in `interpreter.rs` are panel items: inputs in `panels/ekl/items.jsonl`, assertions in `controls/ekl.expected.jsonl`.
Parser items are panel `ekl.parser` (50). The input is the query string. The expect is the AST fields the test asserts (entity, predicates, from, returns, order, limit, as-of, group-by, semantic, and via/depth/count where the test asserts them) or the error kind.
Interpreter items are panel `ekl.interpreter` (33). The input is `{objects, relationships, query}` as the test builds the world. `Uuid::new_v4` ids are fixed, in construction order, to `00000000-0000-5000-8000-0000000000NN` (relationships from `000000000101`), and `expect_from_test` says so.
83 items, 83 control lines. The drift record hashes the 58 functions at EKOS `8e3c178`; `--update` and the check both exited 0 with `drifted: 0`.
Loops are one item per case. Three `AS OF` tests have no fixed timestamp, the fuzz test asserts only that parse does not panic, and several rejects assert only `is_err()`.

## Test → item → assertion

| test | item | assertion (the test's own) |
| --- | --- | --- |
| `parses_minimal_find_object` (`parser.rs:539`) | same | entity `Object`, one predicate `kind Eq "Table"` |
| `parses_return_clause` (`:553`) | same | `returns == ["name", "evidence"]` |
| `parses_relationship_with_from` (`:559`) | same | entity `Relationship`, `from == "orders"` |
| `parses_order_by_and_limit` (`:566`) | same | `order_by == ("name", Asc)`, `limit == 1` |
| `parses_order_by_desc` (`:573`) | same | `order_by == ("name", Desc)` |
| `parses_and_chained_predicates` (`:579`) | same | `predicates.len() == 2`, second op `Contains` |
| `parses_query_with_no_where` (`:586`) | same | predicates empty, `from == "orders"` |
| `parses_numeric_comparison_operators` (`:593`) | `-gt`, `-lt`, `-ge`, `-le`, `-ne` | `predicates[0].op` is `Gt`, `Lt`, `Ge`, `Le`, `Ne` for `>`, `<`, `>=`, `<=`, `!=` |
| `parses_via_and_depth` (`:607`) | same | `from == "orders"`, `via == "DependsOn"`, `depth == 3` |
| `depth_alone_generalizes_from_without_via` (`:615`) | same | `via` is `None`, `depth == 2` |
| `queries_without_via_or_depth_default_to_none` (`:622`) | same | `via` is `None`, `depth` is `None` |
| `rejects_via_without_from` (`:629`) | same | `is_err()`. Kind recorded: `VIA requires a FROM anchor` |
| `parses_semantic_clause` (`:636`) | same | semantic `"authentication and sessions"`, `limit` is `None` |
| `parses_semantic_with_where_and_inline_limit` (`:643`) | same | semantic `"welcome email"`, `limit == 5`, one predicate |
| `rejects_semantic_combined_with_from_asof_count_and_relationship` (`:653`) | `-from`, `-as-of`, `-count`, `-relationship` | each `is_err()`. Kinds are the four `SEMANTIC is not compatible with …` messages, in loop order |
| `rejects_unknown_entity` (`:665`) | same | `is_err()`. Kind recorded: `unknown entity 'Widget'` |
| `rejects_missing_find_keyword` (`:670`) | same | `is_err()`. Kind recorded: `expected 'FIND', found 'Object'` |
| `rejects_unterminated_string` (`:675`) | same | `is_err()`. Kind recorded: `unterminated string literal` |
| `rejects_trailing_garbage` (`:680`) | same | `is_err()`. Kind recorded: `unexpected trailing token 'ZZZ'` |
| `parses_as_of_clause` (`:685`) | same | `as_of` equals `2026-01-01T00:00:00Z` parsed as `DateTime<Utc>` |
| `rejects_malformed_as_of_timestamp` (`:695`) | same | `err.message` contains `"AS OF"` |
| `parses_bare_count` (`:701`) | same | `count`, `group_by` is `None` |
| `parses_count_with_group_by` (`:708`) | same | `count`, `group_by == "kind"` |
| `rejects_group_by_without_count` (`:715`) | same | message contains `GROUP BY requires COUNT` |
| `rejects_count_combined_with_return` (`:721`) | same | message contains `RETURN is not compatible with COUNT` |
| `fuzz_random_strings_never_panic` (`:727`) | `-c1`..`-c18` | `let _ = ekl_parse(s)` must not panic. No Ok/Err assert |
| `where_filters_on_a_property` (`interpreter.rs:545`) | same | 1 row, `name == "b"`, `status == "confirmed"` |
| `a_dotted_field_reads_a_nested_property` (`:558`) | same | 1 row, `name == "a"` |
| `count_groups_by_a_property` (`:567`) | same | `rows.len() == 3` |
| `relationship_properties_filter_too` (`:576`) | same | `rows.len() == 1` |
| `a_field_no_row_has_is_an_error_not_zero_rows` (`:584`) | same | `UnknownField` with `field == "statuz"`, Display contains `"id, name, kind"` |
| `an_unknown_field_over_no_candidates_is_empty` (`:594`) | same | rows empty, on an empty ledger |
| `a_built_in_column_wins_over_a_property_of_the_same_name` (`:602`) | `-real`, `-shadow` | `WHERE name = 'real'` has len 1; `WHERE name = 'shadow'` is empty |
| `example_1_all_tables` (`:619`) | same | len 3, `rows[0]` contains key `id` |
| `example_2_return_name_only` (`:628`) | same | len 3, `rows[0].len() == 1`, key `name` |
| `example_3_exact_name_match` (`:638`) | same | 1 row, `name == "orders"` |
| `example_4_contains_predicate` (`:647`) | same | `rows.len() == 2` |
| `semantic_clause_seeds_candidates_from_retrieval` (`:657`) | same | 1 row, `name == "orders"` |
| `semantic_clause_with_no_match_is_empty_not_an_error` (`:667`) | same | rows empty (`run` unwraps, so not an error) |
| `example_5_order_by_and_limit` (`:675`) | same | 1 row, `name == "customers"` |
| `example_6_all_foreign_keys` (`:687`) | same | `rows.len() == 2` |
| `example_7_relationships_from_anchor` (`:695`) | same | `rows.len() == 2` |
| `example_8_object_neighbourhood` (`:706`) | same | `rows.len() == 3` |
| `example_9_no_matches` (`:714`) | same | rows empty |
| `example_10_return_projection_with_limit` (`:722`) | same | 1 row, `len == 2`, keys `from` and `to` |
| `via_kind_filters_and_traces_dependencies` (`:735`) | same | len 3, no row named `shipping_notes` |
| `depth_without_via_generalizes_single_hop_default` (`:770`) | same | len 3, message `"same as no-DEPTH default"` |
| `unknown_anchor_returns_error` (`:778`) | same | `EklError::AnchorNotFound(_)` |
| `finds_objects_of_a_newly_added_object_kind` (`:787`) | same | 1 row, `name == "Alice"` |
| `as_of_before_anything_written_returns_empty` (`:802`) | same | rows empty. Query timestamp is `(Utc::now() - 60s).to_rfc3339()` |
| `as_of_now_returns_current_objects` (`:812`) | same | len 3. Query timestamp is `Utc::now().to_rfc3339()` |
| `as_of_reconstructs_a_past_version_not_a_later_update` (`:822`) | same | EKL rows: `len == 1` only |
| `as_of_combined_with_from_is_rejected` (`:857`) | same | `EklError::AsOfWithFromUnsupported` |
| `bare_count_returns_one_row_with_total` (`:866`) | same | 1 row, `count` is `Value::Number(3)` |
| `count_group_by_kind_groups_correctly` (`:875`) | same | 2 rows: Table count 3, Person count 2, found by kind |
| `count_group_by_respects_where_predicate_first` (`:901`) | same | 1 row, `kind == "Table"`. Count value not asserted |
| `count_group_by_honors_limit` (`:914`) | same | `rows.len() == 1` |
| `finds_relationships_of_a_custom_kind` (`:925`) | same | 1 row, `kind == "DEPLOYED"` |

## Counts

- Parser: 26 test functions, 50 items. The extras are the numeric loop (5), the semantic-reject loop (4), and the fuzz seeds (18).
- Interpreter: 32 test functions, 33 items. The extra is `a_built_in_column_wins_over_a_property_of_the_same_name` split into `-real` and `-shadow`.
- 83 items, 83 control lines, same order.
- Drift: 58 functions (26 in `parser.rs`, 32 in `interpreter.rs`). Populate (`--update`) exit 0, `{"updated": 58, "failures": []}`. Check exit 0, `{"functions": 58, "drifted": 0, "failures": []}`. Record `panels/ekl/drift.json`, EKOS `8e3c178fc45741c7e2b1576e936646e0c461e75c`, `recorded` `2026-10-19`. The checker is `panels/transcribed/drift_check.py`.

## What was not transcribed faithfully

- These tests were not executed. Parser expects are the `assert_eq` fields. Where a test only calls `is_err()`, the error kind is the `ParseError` message that path builds in `parser.rs`, and `expect_from_test` says the test does not read it. The four semantic messages were taken from `semantic_conflict`, including the em dash in the `COUNT` line. `rejects_malformed_as_of_timestamp` only requires the substring `"AS OF"`; the chrono `Display` after `invalid AS OF timestamp 'not-a-timestamp': ` is not copied. `ParseError.position` is never asserted.
- `fuzz_random_strings_never_panic` discards the `Result`. Each of the 18 seeds (source order, including `""` and `"\u{0}\u{1}\u{2}"`) is an item whose expect is `{"panics": false}`. That is not an AST and not an error kind.
- `as_of_before_anything_written_returns_empty`, `as_of_now_returns_current_objects`, and `as_of_reconstructs_a_past_version_not_a_later_update` format the timestamp from `Utc::now()` (minus 60 seconds, or between two 5ms sleeps). `input.query` keeps the `format!` placeholder (`{before}`, `{now}`, `{mid}`). Those three are not fixed query strings. Each of them adds `input.clock`, which says how the placeholder is filled. That key is outside `{objects, relationships, query}`. The reconstruct item also has `later_objects`.
- On that reconstruct test the EKL assert is only `rows.len() == 1`. The absence of `row_count` is `Runtime::reconstruct_state_at(&orders_id, mid)`, not an `EklResult` field. The test comment says default returns omit properties, so the row cannot show it. `later_objects` is the second `append_object` of the same orders id, with `properties.row_count = 42`, written after `mid`.
- `count_groups_by_a_property` asserts len 3 only. The comment about the empty group key is not an assert. `example_4`, `example_6`, `example_7`, `example_8`, and `count_group_by_honors_limit` do not name which rows. `example_10` has no `ORDER BY`, so which foreign key is the one returned row is not asserted. `via_kind_filters_and_traces_dependencies` asserts len 3 and that no name is `shipping_notes`; the comment's three names (orders, customers, order_items) are not asserted. `count_group_by_kind_groups_correctly` finds rows by kind, so the control's Table-then-Person list is not an order.
- `an_unknown_field_over_no_candidates_is_empty` builds no object and no relationship, so the fixed-id sentence does not apply there. `a_built_in_column_wins_over_a_property_of_the_same_name` draws one object id and no relationship.
- `ObjectKind::Custom("Wallet")`, `Custom("Token")`, and `RelationshipKind::Custom("DEPLOYED")` are written as `"Wallet"`, `"Token"`, and `"DEPLOYED"`, which is what `Display` emits (`Custom` writes the inner string; a unit variant writes its `Debug` name). This lane did not round-trip a value through `serde_json`. `created_at` (`Utc::now()`) is omitted. No assertion reads it. `stats` is `json!({"rows": 12})` and `row_count` is `json!(42)`.
- The drift hash covers the test function body only. `fixture`, `property_fixture`, and `run` sit above the tests at the same indent and are not entries. A change inside a helper would not move a hash.
- `panels/LABELS.json` still lists `ekl.grid` as a placeholder for the `ekos ekl --json` binary. These files are the unit transcription, not that grid. This lane did not edit `LABELS.json`.

## EKOS commit

`8e3c178fc45741c7e2b1576e936646e0c461e75c` (`8e3c178`).
