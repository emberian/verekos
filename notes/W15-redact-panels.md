# W15 — redact panel from the common redaction tests

## Summary

Sixteen tests in `ekos/crates/common/src/redaction.rs` are panel `redact.unit`: inputs in `panels/redact/items.jsonl`, outcomes in `controls/redact.expected.jsonl`.
Each item's input is one `text` (`redact`), one `json` value (`redact_json`), or one `path` (`is_excluded_path`), plus `extra_patterns` and `extra_excluded_globs`. An extra pattern is a `[label, regex source]` pair, the `RedactionConfig` tuple. Empty lists are `RedactionConfig::default()` (`cfg()`).
A test with more than one call is more than one item, split on a `#` suffix. 16 tests, 26 items, 26 control lines.
`expect` is the string, bool, or JSON that call returns. Where the test asserts only a substring or a count, `expect_from_test` says so.
The drift record hashes the 16 functions at EKOS `8e3c178`. `--update` and the check both exited 0 with `drifted: 0`.

## Test → item → assertion

| test | item | assertion (the test's own) |
| --- | --- | --- |
| `redacts_kettle_passwords_and_keeps_the_xml_well_formed` (`:337`) | `#xml` | `!contains` the hex, `!contains` `plain-secret`, contains `<username>sa</username>`, contains `<httpPassword>[REDACTED:xml-password-element]</httpPassword>`, and `roxmltree_like_balanced` (`<` count equals `>` count) |
| same | `#properties` | `!contains` the hex on `DWH_PASSWORD=Encrypted <hex>\n` |
| same | `#plain` | `assert_eq` to `<description>Encrypted at rest</description><passes>3</passes>` |
| `redacts_aws_access_key_id` (`:368`) | same | contains `[REDACTED:aws-access-key-id]`, `!contains` `AKIAABCDEFGHIJKLMNOP`, contains `key = `, contains ` end` |
| `redacts_github_token` (`:377`) | same | contains `[REDACTED:github-token]`, `!contains` `ghp_` plus 36 `a`s |
| `redacts_private_key_block` (`:385`) | same | contains `[REDACTED:private-key-block]`, `!contains` `MIIBOgIBAAJBAK`, contains `before`, contains `after` |
| `redacts_jwt` (`:395`) | same | contains `[REDACTED:jwt]`, `!contains` the jwt |
| `redacts_generic_password_assignment` (`:403`) | same | contains `[REDACTED:generic-assigned-secret]`, `!contains` `hunter2fake` |
| `redaction_preserves_the_real_field_name_and_quotes_replacing_only_the_value` (`:417`) | same | `assert_eq` to `api_key: "[REDACTED:generic-assigned-secret]".to_string(),` |
| `label_match_requires_a_real_word_boundary_not_a_substring_of_a_longer_identifier` (`:431`) | `#api-secret` | `assert_eq` to `api_secret: "[REDACTED:generic-assigned-secret]".to_string(),` |
| same | `#access-token-secret` | `assert_eq` to `access_token_secret: "[REDACTED:generic-assigned-secret]".to_string(),` |
| `generic_pattern_leaves_a_dotted_code_reference_untouched` (`:449`) | same | `assert_eq` to `api_key=settings.azure_openai_api_key,` |
| `generic_pattern_still_redacts_a_dotted_value_that_is_not_a_clean_identifier_chain` (`:465`) | same | contains `[REDACTED:generic-assigned-secret]` |
| `leaves_ordinary_text_untouched` (`:474`) | same | `assert_eq` to `fn main() { println!("hello world"); }` |
| `extra_pattern_from_config_is_additive` (`:480`) | `#extra` | contains `[REDACTED:internal-token]` on `token=ITKN-deadbeef` |
| same | `#baseline` | contains `[REDACTED:aws-access-key-id]` on `key = AKIAABCDEFGHIJKLMNOP`, same config |
| `invalid_extra_pattern_regex_is_skipped_not_fatal` (`:496`) | same | must not panic; contains `[REDACTED:aws-access-key-id]` |
| `is_excluded_path_matches_builtin_globs` (`:507`) | `#env` | `is_excluded_path(".env")` |
| same | `#env-local` | `is_excluded_path("project/.env.local")` |
| same | `#id-rsa` | `is_excluded_path("secrets/id_rsa")` |
| same | `#pem` | `is_excluded_path("certs/server.pem")` |
| same | `#main-rs` | `!is_excluded_path("src/main.rs")` |
| same | `#ekos-toml` | `!is_excluded_path("ekos.toml")` |
| `is_excluded_path_extra_glob_is_additive` (`:517`) | `#yaml` | `is_excluded_path("secrets/prod.yaml")` with extra glob `secrets/*.yaml` |
| same | `#env` | `is_excluded_path(".env")` with that same extra glob |
| `redact_json_recurses_into_arrays_and_objects` (`:528`) | same | `excerpt`, `symbols[1]`, and `nested.inner` contain `[REDACTED:aws-access-key-id]`; `count == 3` |

## Counts

- 16 test functions, 26 panel items, 26 control lines.
- By input: `text` 17, `path` 8, `json` 1.
- Whole-string `assert_eq`: 6 (`#plain`, the field-name test, both boundary items, the dotted-reference test, ordinary text). Bool asserts: 8. The other 12 expects are the call's full output, and the test only checked a substring, an absence, or `count == 3`.
- Drift: 16 functions. Populate (`--update`) exit 0, `{"updated": 16, "failures": []}`. Check exit 0, `{"functions": 16, "drifted": 0, "failures": []}`. Record `panels/redact/drift.json`, EKOS `8e3c178fc45741c7e2b1576e936646e0c461e75c`, `recorded` `2026-10-19`. The checker is `panels/transcribed/drift_check.py`.

## What was not transcribed faithfully

- `cfg` (`:331`) and `roxmltree_like_balanced` (`:361`) are helpers, not tests. The balance check is on `#xml`. On that output both counts are 11. The test does not assert 11.
- The kettle xml literal is three strings joined with `\` continuations, which drop the newline and the indent. `#xml` stores the one concatenated line. `redacts_github_token` builds the token with `format!("ghp_{}", "a".repeat(36))`. The item stores that expansion, `ghp_` and 36 `a`s.
- On `#xml`, `kettle-encrypted-password` matches first. `xml-password-element` then matches `<password>` because its value group is `[^<]+` and the kettle placeholder contains no `<`, so that element ends as `xml-password-element` too. The test never names the kettle label on this call. `#properties` keeps the kettle label: `[` is outside `generic-assigned-secret`'s value class. `<password/>` has no text and stays.
- `slack-token`, `google-api-key`, and `stripe-key` are built-in patterns. No test in this file calls them, so they are not items.
- Twelve expects are stronger than the test. The whole string (or the whole JSON value) is what `redact` / `redact_json` returns for that input, replayed from the pattern table and the replace rules with the `regex` 1 and `glob` 0.3 crates. Every `assert_eq` in the file matches that replay, and every substring, absence, and bool assert listed above holds of the corresponding `expect`. This lane did not run `cargo test` in EKOS. `serde_json`'s map is a `BTreeMap`, so a serialized document would order keys `count`, `excerpt`, `nested`, `symbols`. The test never serializes. The JSON item keeps the literal's order. `symbols[0]` stays `fn main` and is not asserted.
- The drift hash covers the test function's source, not the pattern table above `mod tests`. A pattern edit that leaves the test text alone would not show as drift. The checker already says it does not prove the transcription equals the test.
- `controls/MANIFEST.json` does not list this panel. It does not list `impact` either. It was not edited.

## EKOS commit

`8e3c178fc45741c7e2b1576e936646e0c461e75c` (`8e3c178`).
