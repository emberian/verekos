# W3 — Identity panels (unit tests as data)

**Date:** 2026-10-19 · **EKOS pinned at commit `8e3c178`** (`8e3c178fc45741c7e2b1576e936646e0c461e75c`, clean tree)
**Owns:** `panels/identity/` — `identity.unit.jsonl` (inputs), `controls/identity.unit.controls.jsonl` (expected), `drift.py`, `drift.json`. Source: `ekos/crates/identity/src/lib.rs` `mod tests` (line 719+).

## Summary (5 lines)

1. Transcribed the five in-scope test families of `identity/src/lib.rs` into panel `identity.unit`: **58 items over 45 test functions**, inputs only, JSONL envelope `{"panel","item","origin":"test","source","input"}` (03-scoreboard.md §1.1–1.2).
2. Items carry fixed ids (`00000000-0000-5000-8000-0000000000NN`); object `kind` uses `ObjectKind`'s serde/Display string (`"Table"`, `"Document"`, `"Pipeline"`, … — builtins and `Custom(_)` serialize identically as plain strings).
3. Expected outcomes live separately in `controls/identity.unit.controls.jsonl`, one line per item, same order: `expect` (merge groups as member-id sets with `exact_name_match`, or conflict groups with `kind`+`ids`, or `name_for_similarity` strings) plus `expect_from_test` quoting the Rust assertion each control pins.
4. `drift.py` (stdlib-only, `python3 -I`) hashes each cited test function from its `#[test]` line to the closing `    }` into `drift.json`; populated against EKOS `8e3c178` (45 functions), second run passes; negative tests confirm a one-word comment change → `DRIFTED: <fn>`, exit 1, and a removed function → `DISAPPEARED: <fn>`, exit 1.
5. Test loop helpers were inlined per source: `make_graph` (bare `KirObject::new(name, kind)`) and `table_with_columns` (`properties.columns = [{"name": c, "data_type": "text"}, …]` — the helper hardcodes `"data_type": "text"` for every column, transcribed as-is).

## Counts

| family | tests fns | items | item ids |
|---|---|---|---|
| threshold regressions on real data (`real_*`) | 5 | 5 | `real_*` |
| `exact_name_match` (RFC 0060/0063) | 4 | 6 | `exact_name_match_*` (`…residual_known_wrong_pairs-c1..c3`) |
| `name_for_similarity` (RFC 0060/0062) | 5 | 5 | `name_for_similarity_*` |
| `detect_kind_conflicts` + five narrowings | 18 | 27 | `*_conflict*`, `*conflicts*` (`-c1..cN` per loop group) |
| `candidate_blocks` / structurally-keyed exclusion | 13 | 15 | `*_never_merged_*`, `concept_*`, `unrelated_documents_*`, `a_non_keyed_*` |
| **total** | **45** | **58** | |

Multi-case tests were split one `resolve()` input per item, `-cN` suffixed, all citing the same `source` fn (the drift hash is per function, so sibling items share it): residual pairs ×3, trigger ×2, view/table ×2, perl-beside-db ×4, languages ×2, perl-excuse ×2, binary intruders ×3, elixir/js kinds ×3.

## Table: test → item(s) → asserted

| test fn (`lib.rs`) | item id(s) | asserted outcome |
|---|---|---|
| `real_clickhouse_imported_tables_do_not_merge` | same | 0 proposals (8 vs 10 real columns) |
| `real_postgres_email_template_tables_do_not_merge` | same | 0 proposals (identical columns, name sim below threshold) |
| `real_distinct_contributors_with_similar_names_do_not_merge` | same | 0 proposals (two real people) |
| `real_same_contributor_under_different_git_names_still_merges` | same | 1 proposal, both members |
| `real_github_pull_requests_do_not_all_merge_into_one_identity` | same | 0 proposals (shared `owner/repo#` prefix) |
| `exact_name_match_true_for_identical_normalized_names` | same | 1 proposal, `exact_name_match == true` |
| `exact_name_match_false_for_the_rfc_0060_known_good_fuzzy_merges` | same | 1 proposal, flag `false` |
| `exact_name_match_false_for_rfc_0060_residual_known_wrong_pairs` | `-c1..-c3` | per pair: 1 proposal, flag `false` |
| `exact_name_match_false_for_a_transitively_chained_mixed_group` | same | 1 proposal, 3 members, flag `false` |
| `name_for_similarity_strips_schema_qualifier_for_tables` | same | `"imported_visitors"` |
| `name_for_similarity_leaves_unqualified_table_names_untouched` | same | `"orders"` |
| `name_for_similarity_does_not_strip_non_table_kinds` | same | `"test/priv/README.md"` |
| `name_for_similarity_does_not_strip_a_table_name_containing_a_slash` | same | `"path/to/file.sql"` |
| `name_for_similarity_strips_owner_repo_number_prefix_for_github_items` | same | title strings for PR and Issue (2 objects, 1 item) |
| `different_kind_same_name_conflict` | same | 1 conflict, `SameNameDifferentKind` |
| `newly_added_object_kind_participates_in_conflict_detection` | same | 1 conflict, `SameNameDifferentKind` (Person/Table) |
| `technology_and_bare_specifier_jsmodule_sharing_a_name_do_not_conflict` | same | 0 conflicts |
| `a_third_kind_mixed_into_the_technology_jsmodule_group_still_conflicts` | same | 1 conflict |
| `a_perl_package_and_a_perl_sub_sharing_a_name_do_not_conflict` | same | 0 conflicts |
| `a_view_and_a_same_named_routine_do_not_conflict` | same | 0 conflicts (View + 2×Procedure) |
| `a_trigger_named_after_its_function_does_not_conflict` | `-c1`, `-c2` | c1: 0 conflicts (Trigger + 2×Procedure); c2: 1 conflict (Trigger + Table) |
| `a_view_beside_a_same_named_table_still_conflicts` | `-c1`, `-c2` | 1 conflict each (View+Table; View+Procedure+Table) |
| `perl_code_beside_same_named_database_objects_does_not_conflict` | `-c1..-c4` | 0 conflicts per group |
| `code_in_different_languages_sharing_a_name_does_not_conflict` | `-c1`, `-c2` | c1: 0; c2: 1 (JsModule beside JsSymbol) |
| `perl_does_not_excuse_a_database_side_conflict_or_another_kind` | `-c1`, `-c2` | 1 conflict each |
| `a_third_kind_mixed_into_the_perl_group_still_conflicts` | same | 1 conflict |
| `a_binary_method_and_a_same_named_field_do_not_conflict` | same | 0 conflicts |
| `a_binary_field_named_after_its_type_does_not_conflict` | same | 0 conflicts |
| `a_non_declaration_kind_mixed_into_the_binary_group_still_conflicts` | `-c1..-c3` | 1 conflict per intruder |
| `a_binary_method_paired_with_an_unrelated_kind_still_conflicts` | same | 1 conflict (BinaryMethod + Table) |
| `two_perl_packages_sharing_a_name_are_not_silently_excluded` | same | 1 conflict (PerlPackage + Technology) |
| `a_relative_specifier_jsmodule_sharing_a_technology_name_still_conflicts` | same | 1 conflict (`./utils`) |
| `unrelated_documents_sharing_a_folder_prefix_do_not_all_merge` | same | 0 proposals (7 Documents) |
| `section_objects_are_never_merged_even_with_near_identical_names` | same | 0 proposals |
| `transform_node_objects_are_never_merged_even_with_shared_source_prefix` | same | 0 proposals |
| `rust_symbol_objects_are_never_merged_even_with_shared_name_suffix` | same | 0 proposals |
| `crate_objects_are_never_merged_even_with_shared_name_prefix` | same | 0 proposals |
| `elixir_module_objects_are_never_merged_even_with_unrelated_names` | same | 0 proposals |
| `elixir_symbol_and_js_module_and_js_symbol_objects_are_never_merged` | `-c1..-c3` | 0 proposals per kind |
| `claim_objects_are_never_merged_even_with_shared_statement_prefix` | same | 0 proposals |
| `architecture_gap_objects_are_never_merged_even_with_shared_question_prefix` | same | 0 proposals |
| `document_objects_are_never_merged_even_with_identical_names` | same | 0 proposals (two real `README.md`) |
| `concept_same_real_entity_across_two_documents_merges` | same | 1 proposal, 2 members |
| `concept_generic_short_names_across_unrelated_documents_do_not_all_merge` | same | 0 proposals (degenerate names excluded from blocking) |
| `a_non_keyed_custom_kind_still_resolves_normally` | same | `is_structurally_keyed("Issue") == false`; 1 proposal, 2 members |

The five narrowings map to `is_expected_technology_jsmodule_pair`, `is_expected_perl_package_symbol_pair`, `is_expected_sql_namespace_group` (View/Procedure/Trigger), `is_expected_binary_declaration_group`, `is_expected_cross_namespace_group` (`lib.rs:439-443`); every control that asserts a conflict carries the forced member ids (the full normalized-name group, `lib.rs:447`).

## Fidelity notes / not transcribed, and why

- `exact_name_match` on merge groups is *asserted* by the four `exact_name_match_*` tests; for the other three merge items (`real_same_contributor…`, `concept_same…`, `a_non_keyed…`) the flag in `expect` is derived from `resolve()`'s rule (all members equal after `normalize(name_for_similarity)`, `lib.rs:569-572`) and each control's `expect_from_test` says so. Notably the Issue item's flag is `true`: `name_for_similarity` strips `owner/repo#n:`, leaving identical titles.
- Split-loop items keep the loop body's per-iteration inputs; loop order and the `assert!` phrasing are preserved in `expect_from_test` ("loop group k/N …").
- Not transcribed (15 fns), by scope: `empty_graph_returns_empty`, `single_object_no_merge`, `exact_case_difference_proposes_merge`, `plural_singular_proposes_merge`, `underscore_variant_proposes_merge`, `dissimilar_names_no_merge` (base merge path, none of the five families); `prefix_sharing_tables_with_disjoint_columns_do_not_merge`, `similar_names_with_overlapping_columns_still_merge`, `distinct_pdf_tables_in_one_document_do_not_all_merge`, `pdf_tables_with_identical_row_content_still_merge` (exercise `structural_score`'s columns/rows signals, not `candidate_blocks` — good candidates for a structural-score panel); `three_way_transitivity_single_proposal` (covered on the exact-flag side by the transitive-chain item); `stats_counts_pairs_and_candidates`, `custom_threshold_prevents_merge`, `result_is_serializable` (stats/threshold-API/serde, not kernel-input shapes); `every_pipeline_custom_kind_is_registered` (walks the EKOS source tree with `walkdir` — no object inputs exist to transcribe; it is CI machinery, not data).
- Nothing in the transcription was un-faithful to the best of my reading; the one lossy step is unavoidable: tests use random `KirObject::new` UUIDs, items use fixed ones (spec §1.5 Branch pattern), and control member-ids refer to those fixed ids.

## Commands run (both recorded)

```
python3 -I drift.py   # → populated drift.json: 45 functions (ekos 8e3c178fc457)
python3 -I drift.py   # → drift check passed: 45 functions unchanged (ekos 8e3c178fc457), exit 0
```
