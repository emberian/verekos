#!/usr/bin/env python3
"""Transcription of the EKOS scope decision tests into panel inputs.

Source: ekos/crates/ledger/src/scope.rs, `mod tests`, the parsing and decision
families (EKOS @ 8e3c178). Each Rust test function becomes one or more panel
items; the input side goes to panels/scope/decision.jsonl and the boolean (or
error kind) the test asserts goes to controls/scope.decision.expected.jsonl,
never both into the panel (exploration 03 §1.1).

This file is data plus a generator; it is not a checker. The drift checker is
drift_check.py with the recorded hashes in scope_drift.json: it fails when any
transcribed function's source text changes in the EKOS checkout.

Expected error kinds for the `parse` items are read off `ReadScope::from_json`
(scope.rs:94): serde and shape errors are ScopeError::Parse; everything its
`check()` — that is, `Compiled::new` — refuses (empty source/path, a rule that
names both an object and a source, an uncompilable glob) is ScopeError::Rule.
Only the first `a_scope_without_a_default...` input and the `both` input of
`unknown_fields...` have their variant asserted by the Rust test itself; the
rest are the test's `.is_err()` plus the variant predicted from the source.

Not transcribed here (out of this panel's shape, recorded in the W5 memo):
`ReadScope::unrestricted()` (not a JSON input) and the `ScopedStore` family
(scope.rs:1041 on), which needs a real store — that is the leak-suite panel.
"""

import json
import sys
from pathlib import Path

SCOPE_RS = "ekos/crates/ledger/src/scope.rs"

# `wanted` in object_rules_name_one_object and a_deny_on_a_source_beats...:
# the tests mint a random KirId; the decision only compares ids for equality,
# so any fixed uuid is the same test.
WANTED = "00000000-0000-5000-8000-000000000001"
OTHER = "00000000-0000-5000-8000-000000000002"
# The object named by the object+source rule in unknown_fields_and_bad_rules.
RULE_OBJECT = "00000000-0000-5000-8000-0000000000ff"


def scope(**kw) -> str:
    """A scope as compact JSON text, the form `ReadScope::from_json` takes."""
    return json.dumps(kw, separators=(",", ":"))


def rule(effect, source=None, path=None, object_=None):
    r = {"effect": effect}
    if source is not None:
        r["source"] = source
    if path is not None:
        r["path"] = path
    if object_ is not None:
        r["object"] = object_
    return r


def o(source=None, path=None):
    """One origin: the test helper `o(source, path)`."""
    return {"source": source, "path": path}


ITEMS = []  # (fn, line, kind, input, expected)


def add(fn, line, kind, inp, expected):
    ITEMS.append({"fn": fn, "line": line, "kind": kind, "input": inp, "expected": expected})


# ── parsing: a_scope_without_a_default_does_not_parse (scope.rs:812) ─────────
# The test asserts ScopeError::Parse for the first input and is_err for the rest.
add("a_scope_without_a_default_does_not_parse", 812, "parse",
    {"scope": '{"rules": []}'}, {"error": "parse"})
add("a_scope_without_a_default_does_not_parse", 812, "parse",
    {"scope": "{}"}, {"error": "parse"})
add("a_scope_without_a_default_does_not_parse", 812, "parse",
    {"scope": "null"}, {"error": "parse"})
add("a_scope_without_a_default_does_not_parse", 812, "parse",
    {"scope": ""}, {"error": "parse"})

# ── unknown_fields_and_bad_rules_are_refused (scope.rs:823) ──────────────────
# Six malformed scopes the test asserts is_err on (variants predicted from
# from_json + Compiled::new), then a rule naming both an object and a source,
# which the test asserts is ScopeError::Rule { index: 0 }.
add("unknown_fields_and_bad_rules_are_refused", 823, "parse",
    {"scope": '{"default":"deny","rule":[]}'}, {"error": "parse"})
add("unknown_fields_and_bad_rules_are_refused", 823, "parse",
    {"scope": '{"default":"deny","rules":[{"effect":"allow","sources":"a"}]}'}, {"error": "parse"})
add("unknown_fields_and_bad_rules_are_refused", 823, "parse",
    {"scope": '{"default":"deny","rules":[{"effect":"permit","source":"a"}]}'}, {"error": "parse"})
add("unknown_fields_and_bad_rules_are_refused", 823, "parse",
    {"scope": '{"default":"deny","rules":[{"effect":"allow","source":""}]}'}, {"error": "rule"})
add("unknown_fields_and_bad_rules_are_refused", 823, "parse",
    {"scope": '{"default":"deny","rules":[{"effect":"allow","path":"[unclosed"}]}'}, {"error": "rule"})
add("unknown_fields_and_bad_rules_are_refused", 823, "parse",
    {"scope": '{"default":"maybe"}'}, {"error": "parse"})
add("unknown_fields_and_bad_rules_are_refused", 823, "parse",
    {"scope": scope(default="deny", rules=[rule("allow", source="a", object_=RULE_OBJECT)])},
    {"error": "rule"})

# ── only_default_allow_without_a_deny_is_unrestricted (scope.rs:845) ─────────
# The test's first line (ReadScope::unrestricted()) is not a JSON input and is
# not transcribed.
add("only_default_allow_without_a_deny_is_unrestricted", 845, "unrestricted",
    {"scope": scope(default="allow")}, {"unrestricted": True})
add("only_default_allow_without_a_deny_is_unrestricted", 845, "unrestricted",
    {"scope": scope(default="deny")}, {"unrestricted": False})
add("only_default_allow_without_a_deny_is_unrestricted", 845, "unrestricted",
    {"scope": scope(default="allow", rules=[rule("deny", source="a")])}, {"unrestricted": False})

# ── default_deny_hides_everything_without_a_rule (scope.rs:869) ──────────────
_deny = {"scope": scope(default="deny")}
add("default_deny_hides_everything_without_a_rule", 869, "visible",
    {**_deny, "origins": [o("api", "a.rs")]}, {"visible": False})
add("default_deny_hides_everything_without_a_rule", 869, "visible",
    {**_deny, "origins": [o()]}, {"visible": False})

# ── an_allowed_source_shows_its_objects_and_no_others (scope.rs:876) ─────────
_api = {"scope": scope(default="deny", rules=[rule("allow", source="api")])}
add("an_allowed_source_shows_its_objects_and_no_others", 876, "visible",
    {**_api, "origins": [o("api", "src/a.rs")]}, {"visible": True})
add("an_allowed_source_shows_its_objects_and_no_others", 876, "visible",
    {**_api, "origins": [o("api")]}, {"visible": True})
add("an_allowed_source_shows_its_objects_and_no_others", 876, "visible",
    {**_api, "origins": [o("web", "src/a.rs")]}, {"visible": False})

# ── an_object_without_a_source_is_hidden_from_a_reader_limited_by_source (884)
add("an_object_without_a_source_is_hidden_from_a_reader_limited_by_source", 884, "visible",
    {**_api, "origins": [o()]}, {"visible": False})
add("an_object_without_a_source_is_hidden_from_a_reader_limited_by_source", 884, "visible",
    {**_api, "origins": [o(None, "src/a.rs")]}, {"visible": False})

# ── an_object_in_two_sources_needs_both (scope.rs:891) ───────────────────────
_two = [o("api", "x"), o("web", "x")]
add("an_object_in_two_sources_needs_both", 891, "visible",
    {"scope": scope(default="deny", rules=[rule("allow", source="api")]), "origins": _two},
    {"visible": False})
add("an_object_in_two_sources_needs_both", 891, "visible",
    {"scope": scope(default="deny", rules=[rule("allow", source="api"),
                                           rule("allow", source="web")]), "origins": _two},
    {"visible": True})

# ── deny_wins_over_allow_whatever_the_order (scope.rs:903) ───────────────────
# Both rule orders, three origins each.
_origins_deny_wins = [
    ([o("api", "src/a.rs")], True),
    ([o("api", "secrets/key.pem")], False),
    ([o("api", "secrets/deep/er/x")], False),
]
for _rules in ([rule("allow", source="api"), rule("deny", source="api", path="secrets/**")],
               [rule("deny", source="api", path="secrets/**"), rule("allow", source="api")]):
    for _origins, _expected in _origins_deny_wins:
        add("deny_wins_over_allow_whatever_the_order", 903, "visible",
            {"scope": scope(default="deny", rules=_rules), "origins": _origins},
            {"visible": _expected})

# ── one_denied_origin_hides_an_object_with_several_paths (scope.rs:916) ──────
add("one_denied_origin_hides_an_object_with_several_paths", 916, "visible",
    {"scope": scope(default="allow", rules=[rule("deny", path="secrets/**")]),
     "origins": [o("api", "src/a.rs"), o("api", "secrets/k")]},
    {"visible": False})

# ── a_path_deny_hides_what_has_no_path (scope.rs:926) ────────────────────────
_path_deny = {"scope": scope(default="allow", rules=[rule("deny", source="api", path="secrets/**")])}
for _origins, _expected in [
    ([o("api")], False),
    ([o("web")], True),
    ([o("web", "secrets/x")], True),
    ([o()], False),
    ([o(None, "secrets/x")], False),
    ([o(None, "src/a.rs")], True),
]:
    add("a_path_deny_hides_what_has_no_path", 926, "visible",
        {**_path_deny, "origins": _origins}, {"visible": _expected})

# ── a_path_deny_without_a_source_applies_to_every_source_and_to_none (942) ───
add("a_path_deny_without_a_source_applies_to_every_source_and_to_none", 942, "visible",
    {"scope": scope(default="allow", rules=[rule("deny", path="hr/**")]),
     "origins": [o("handbook", "hr/salaries.md")]}, {"visible": False})
add("a_path_deny_without_a_source_applies_to_every_source_and_to_none", 942, "visible",
    {"scope": scope(default="allow", rules=[rule("deny", path="hr/**")]),
     "origins": [o(None, "hr/salaries.md")]}, {"visible": False})
add("a_path_deny_without_a_source_applies_to_every_source_and_to_none", 942, "visible",
    {"scope": scope(default="allow", rules=[rule("deny", path="hr/**")]),
     "origins": [o()]}, {"visible": False})
add("a_path_deny_without_a_source_applies_to_every_source_and_to_none", 942, "visible",
    {"scope": scope(default="allow", rules=[rule("deny", path="hr/**")]),
     "origins": [o("handbook", "public/a.md")]}, {"visible": True})

# ── a_path_allow_needs_a_path_that_matches (scope.rs:951) ────────────────────
_allow_pub = {"scope": scope(default="deny", rules=[rule("allow", source="docs", path="public/**")])}
for _origins, _expected in [
    ([o("docs", "public/a.md")], True),
    ([o("docs", "hr/a.md")], False),
    ([o("docs")], False),
    ([o("docs", "public/a.md"), o("docs", "hr/a.md")], False),
]:
    add("a_path_allow_needs_a_path_that_matches", 951, "visible",
        {**_allow_pub, "origins": _origins}, {"visible": _expected})

# ── a_star_stays_in_one_component_and_two_cross_them (scope.rs:969) ──────────
add("a_star_stays_in_one_component_and_two_cross_them", 969, "visible",
    {"scope": scope(default="deny", rules=[rule("allow", path="src/*.rs")]),
     "origins": [o(None, "src/a.rs")]}, {"visible": True})
add("a_star_stays_in_one_component_and_two_cross_them", 969, "visible",
    {"scope": scope(default="deny", rules=[rule("allow", path="src/*.rs")]),
     "origins": [o(None, "src/deep/a.rs")]}, {"visible": False})
add("a_star_stays_in_one_component_and_two_cross_them", 969, "visible",
    {"scope": scope(default="deny", rules=[rule("allow", path="src/**")]),
     "origins": [o(None, "src/deep/a.rs")]}, {"visible": True})
add("a_star_stays_in_one_component_and_two_cross_them", 969, "visible",
    {"scope": scope(default="deny", rules=[rule("allow", path="src/**")]),
     "origins": [o(None, "srcs/a.rs")]}, {"visible": False})
add("a_star_stays_in_one_component_and_two_cross_them", 969, "visible",
    {"scope": scope(default="deny", rules=[rule("allow", path="src/**")]),
     "origins": [o(None, "other/src/a.rs")]}, {"visible": False})

# ── a_path_recorded_with_its_source_in_front_still_matches (scope.rs:980) ────
_recorded = {"scope": scope(default="allow", rules=[rule("deny", source="api", path="secrets/**")])}
add("a_path_recorded_with_its_source_in_front_still_matches", 980, "visible",
    {**_recorded, "origins": [o("api", "api/secrets/k")]}, {"visible": False})
# The test's second half feeds `origins(&["api"], &["./secrets\\k"])`: the
# sources × paths shape, with a `./` prefix and a backslash to normalize.
add("a_path_recorded_with_its_source_in_front_still_matches", 980, "visible",
    {**_recorded, "sources": ["api"], "paths": ["./secrets\\k"]}, {"visible": False})

# ── object_rules_name_one_object (scope.rs:990) ──────────────────────────────
add("object_rules_name_one_object", 990, "visible",
    {"scope": scope(default="deny", rules=[rule("allow", object_=WANTED)]),
     "id": WANTED, "origins": [o()]}, {"visible": True})
add("object_rules_name_one_object", 990, "visible",
    {"scope": scope(default="deny", rules=[rule("allow", object_=WANTED)]),
     "id": OTHER, "origins": [o()]}, {"visible": False})
add("object_rules_name_one_object", 990, "visible",
    {"scope": scope(default="allow", rules=[rule("deny", object_=WANTED)]),
     "id": WANTED, "origins": [o("api", "a")]}, {"visible": False})
add("object_rules_name_one_object", 990, "visible",
    {"scope": scope(default="allow", rules=[rule("deny", object_=WANTED)]),
     "id": OTHER, "origins": [o("api", "a")]}, {"visible": True})

# ── a_deny_on_a_source_beats_an_allow_on_the_object (scope.rs:1008) ──────────
_beats = {"scope": scope(default="deny", rules=[rule("allow", object_=WANTED),
                                                rule("deny", source="api")]), "id": WANTED}
add("a_deny_on_a_source_beats_an_allow_on_the_object", 1008, "visible",
    {**_beats, "origins": [o("api")]}, {"visible": False})
add("a_deny_on_a_source_beats_an_allow_on_the_object", 1008, "visible",
    {**_beats, "origins": [o("web")]}, {"visible": True})

# ── origins_cross_sources_with_paths (scope.rs:1020) ─────────────────────────
add("origins_cross_sources_with_paths", 1020, "origins",
    {"sources": [], "paths": []}, {"origins": [o()]})
add("origins_cross_sources_with_paths", 1020, "origins",
    {"sources": ["a", "b"], "paths": ["x"]},
    {"origins": [o("a", "x"), o("b", "x")]})


def write(panel_path: Path, expected_path: Path) -> None:
    counts: dict = {}
    with panel_path.open("w") as panel, expected_path.open("w") as expected:
        for entry in ITEMS:
            fn = entry["fn"]
            counts[fn] = counts.get(fn, 0) + 1
            item_id = f"{fn}#{counts[fn]}"
            source = f"{SCOPE_RS}:{entry['line']} {fn}"
            panel.write(json.dumps({
                "panel": "scope.decision",
                "item": item_id,
                "kind": entry["kind"],
                "origin": "test",
                "source": source,
                "input": entry["input"],
            }, separators=(",", ":")) + "\n")
            expected.write(json.dumps({
                "item": item_id,
                "expect": entry["expected"],
                "expect_from_test": f"the assertion of {source}, transcribed in panels/scope/gen_decision.py",
            }, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    panel = root / "panels" / "scope" / "decision.jsonl"
    expected = root / "controls" / "scope.decision.expected.jsonl"
    if len(sys.argv) > 1:
        panel, expected = Path(sys.argv[1]), Path(sys.argv[2])
    panel.parent.mkdir(parents=True, exist_ok=True)
    expected.parent.mkdir(parents=True, exist_ok=True)
    write(panel, expected)
    print(json.dumps({
        "panel": str(panel),
        "expected": str(expected),
        "items": len(ITEMS),
        "functions": len({e["fn"] for e in ITEMS}),
    }))
