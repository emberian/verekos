#!/usr/bin/env python3
"""Transcription of the EKOS ScopedStore tests into panel inputs.

Source: ekos/crates/ledger/src/scope.rs, `mod tests`, the store family
(EKOS @ 8e3c178): the helpers `object`/`world`/`scoped`/`names` (:1041-1107)
and the eight store tests (:1109-1308). Not transcribed: the source-inspection
meta-test `every_store_method_has_a_decision_here` (:1310), which reads the
trait's own text and asserts every method has a decision — nothing to replay
against a store.

The existing scope.decision panel cannot carry these: it answers
`Compiled::visible` questions with no store at all. Every test here drives a
`ScopedStore` (a `KnowledgeStore` wrapper) over a real `Ledger` built through
ekos_ledger's public API, so the panel feeds the `store` dump: each item names
a world (the `world()` fixture), the initial scope set, and the ordered steps
of one test; the dump replays them and prints one result per step — names,
counts, booleans and role names, never a random id or a timestamp.

Expected values are the tests' own assertions. Two are predictions the tests
assert only by equality with the inner store (marked below): the unrestricted
`entry_count` (9 = 4 objects + 2 relationships + 3 evidence) and the
unrestricted `all_relationships` pair list. The 59/59-style confirmation is
the dump's `--expected` run itself.

Run with python3 -I:

    python3 -I panels/scope_store_tests.py
"""

import json
import sys
from pathlib import Path

SCOPE_RS = "ekos/crates/ledger/src/scope.rs"

# world() (scope.rs:1062): four objects, two DependsOn edges, evidence on the
# three placed objects. Roles stand in for the tests' `w.public`/`w.secret`/….
WORLD = {
    "objects": [
        {"role": "public", "name": "public_orders", "source": "api", "file": "db/schema.sql"},
        {"role": "secret", "name": "secret_payroll", "source": "api", "file": "secrets/payroll.sql"},
        {"role": "other", "name": "other_pages", "source": "web", "file": "pages/index.sql"},
        {"role": "unplaced", "name": "unplaced_person"},
    ],
    "relationships": [
        {"role": "pub_secret", "kind": "DependsOn", "from": "public", "to": "secret"},
        {"role": "pub_other", "kind": "DependsOn", "from": "public", "to": "other"},
    ],
}

# HIDE_SECRETS_AND_WEB (scope.rs:1094).
HIDE = json.dumps({"default": "deny", "rules": [
    {"effect": "allow", "source": "api"},
    {"effect": "deny", "source": "api", "path": "secrets/**"},
]}, separators=(",", ":"))

WIDER = json.dumps({"default": "deny", "rules": [
    {"effect": "allow", "source": "api"},
    {"effect": "allow", "source": "web"},
    {"effect": "deny", "source": "api", "path": "secrets/**"},
]}, separators=(",", ":"))

API_ONLY = json.dumps({"default": "deny", "rules": [
    {"effect": "allow", "source": "api"},
]}, separators=(",", ":"))

# The second set_scopes of several_scopes_must_all_agree_and_can_be_replaced
# (scope.rs:1289): api allowed AND secrets denied from the other direction.
REPLACEMENT = json.dumps({"default": "allow", "rules": [
    {"effect": "deny", "path": "secrets/**"},
]}, separators=(",", ":"))

ALL_NAMES = ["other_pages", "public_orders", "secret_payroll", "unplaced_person"]

ITEMS = []  # (fn, line, input) — the whole scenario; the expected file carries the per-step assertions


def add(fn, line, scopes, steps):
    ITEMS.append({
        "fn": fn,
        "line": line,
        "input": {"world": WORLD, "scopes": scopes, "steps": steps},
    })


def op(kind, **kw):
    out = {"op": kind}
    out.update(kw)
    return out


# ── an_unrestricted_store_returns_what_the_inner_store_returns (scope.rs:1109)
# entry_count 9 and the relationship pair list are predictions (the test asserts
# equality with the inner store, not numbers); all_objects/count/evidence values
# are the world's own, which the test does assert by comparison.
add("an_unrestricted_store_returns_what_the_inner_store_returns", 1109,
    ['{"default":"allow"}'],
    [op("is_restricted"), op("fingerprint_empty"), op("all_objects"),
     op("all_relationships"), op("object_count"), op("entry_count"),
     op("evidence_count"), op("get_evidence", role="secret"),
     op("append_object", name="new")])

# ── objects_are_filtered_on_every_object_read (scope.rs:1132) ───────────────
_steps = [op("is_restricted"), op("all_objects"), op("get_object", role="public")]
for hidden in ("secret", "other", "unplaced"):
    _steps += [op("get_object", role=hidden), op("object_history", role=hidden),
               op("object_at", role=hidden), op("fact", role=hidden, attr="name"),
               op("audit_trail", role=hidden), op("relationships_for", role=hidden),
               op("relationships_at", role=hidden)]
_steps += [op("all_objects_at"), op("object_history", role="public"),
           op("fact", role="public", attr="name")]
add("objects_are_filtered_on_every_object_read", 1132, [HIDE], _steps)

# ── a_relationship_needs_both_ends (scope.rs:1170) ──────────────────────────
add("a_relationship_needs_both_ends", 1170, [HIDE],
    [op("all_relationships"), op("all_relationships_at"),
     op("relationships_for", role="public"), op("get_relationship", rel="pub_secret"),
     op("relationship_history", rel="pub_secret"),
     op("set_scopes", scopes=[WIDER]),
     op("all_relationships"), op("relationships_for", role="public")])

# ── evidence_is_readable_only_through_something_visible (scope.rs:1197) ──────
add("evidence_is_readable_only_through_something_visible", 1197, [HIDE],
    [op("get_evidence", role="public"), op("get_evidence", role="secret"),
     op("get_object", role="public"), op("get_object", role="secret"),
     op("get_evidence", role="public"), op("get_evidence", role="secret")])

# ── search_returns_only_visible_hits (scope.rs:1210) ────────────────────────
_steps = []
for query in ("secret_payroll", "payroll", "other_pages", "unplaced_person"):
    _steps += [op("find_objects", query=query), op("retrieve", query=query)]
_steps += [op("find_objects", query="public_orders"), op("retrieve", query="public_orders")]
add("search_returns_only_visible_hits", 1210, [HIDE], _steps)

# ── counts_and_diff_cover_only_what_is_visible (scope.rs:1234) ───────────────
add("counts_and_diff_cover_only_what_is_visible", 1234, [HIDE],
    [op("object_count"), op("relationship_count"), op("evidence_count"),
     op("entry_count"), op("diff")])

# ── a_restricted_store_refuses_writes_events_and_copies (scope.rs:1250) ──────
add("a_restricted_store_refuses_writes_events_and_copies", 1250, [HIDE],
    [op("append_object", name="x"), op("append_evidence"),
     op("append_relationship", frm="public", to="public"),
     op("vacuum_into"), op("get_event")])

# ── several_scopes_must_all_agree_and_can_be_replaced (scope.rs:1276) ────────
add("several_scopes_must_all_agree_and_can_be_replaced", 1276, [API_ONLY],
    [op("all_objects"), op("fingerprint_nonempty"),
     op("set_scopes", scopes=[API_ONLY, REPLACEMENT]),
     op("all_objects"), op("fingerprint_differs_from_last"),
     op("get_object", role="secret"), op("get_evidence", role="secret"),
     op("set_scopes", scopes=[]),
     op("all_objects")])


def write(panel_path: Path, expected_path: Path) -> None:
    """The panel (scenario inputs) and the expected file (per-step assertions).

    The assertions are positional: `results` must equal the list below
    element-for-element, in step order — the same order the Rust test asserts
    them in.
    """
    EXPECTED = {
        "an_unrestricted_store_returns_what_the_inner_store_returns#1": [
            False, True, ALL_NAMES,
            ["public_orders->other_pages", "public_orders->secret_payroll"],
            4, 9, 3, True, True],
        "objects_are_filtered_on_every_object_read#1": (
            [True, ["public_orders"], "public_orders"]
            + [None, [], None, None, 0, [], []] * 3
            + [["public_orders"], ["public_orders"], "public_orders"]),
        "a_relationship_needs_both_ends#1": [
            [], [], [], None, 0,
            "ok",
            ["public_orders->other_pages"], ["public_orders->other_pages"]],
        "evidence_is_readable_only_through_something_visible#1": [
            False, False, "public_orders", None, True, False],
        "search_returns_only_visible_hits#1": (
            [[], 0, [], 0, [], 0, [], 0]
            + [["public_orders"], 1]),
        "counts_and_diff_cover_only_what_is_visible#1": [
            1, 0, 1, 2, {"touched": ["public_orders"], "added": 0}],
        "a_restricted_store_refuses_writes_events_and_copies#1": [
            "read_scope", "read_scope", "read_scope", "read_scope", True],
        "several_scopes_must_all_agree_and_can_be_replaced#1": [
            ["public_orders", "secret_payroll"], True,
            "ok",
            ["public_orders"], True,
            None, False,
            "ok",
            ALL_NAMES],
    }
    counts: dict = {}
    with panel_path.open("w") as panel, expected_path.open("w") as expected:
        for entry in ITEMS:
            fn = entry["fn"]
            counts[fn] = counts.get(fn, 0) + 1
            item_id = f"{fn}#{counts[fn]}"
            panel.write(json.dumps({
                "panel": "scope.store",
                "item": item_id,
                "kind": "store",
                "origin": "test",
                "source": f"{SCOPE_RS}:{entry['line']} {fn}",
                "input": entry["input"],
            }, separators=(",", ":")) + "\n")
            expected.write(json.dumps({
                "item": item_id,
                "expect": {"results": EXPECTED[item_id]},
                "expect_from_test": f"the assertions of {SCOPE_RS}:{entry['line']} {fn}, transcribed in panels/scope/gen_store.py",
            }, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    panel = root / "panels" / "scope" / "store.jsonl"
    expected = root / "controls" / "scope.store.expected.jsonl"
    if len(sys.argv) > 2:
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
