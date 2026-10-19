#!/usr/bin/env python3
"""Transcription of the EKOS conflicts tests into panel inputs.

Source: ekos/crates/semantic/src/conflicts.rs, `mod tests` (EKOS @ 8e3c178).
The panel carries only inputs — table rows in the test helper `table()`'s
shape (`key` stands where the helper writes `kid("t:{name}")`), enum meanings,
merge proposals, type pairs — and controls/conflicts.unit.expected.jsonl
carries the assertions the Rust test makes (`expect_from_test`), checked by
`control-dump conflicts --expected`.

The review-workflow tests (`a_review_holds_while...`, `resolve_validates_its_input`)
and `column_links` (RFC 0173 table linking) are not transcribed: they exercise
resolve/carry_forward/column_links, not the detectors this panel measures.
Recorded in the W5 memo.
"""

import json
import sys
from pathlib import Path

CONFLICTS_RS = "ekos/crates/semantic/src/conflicts.rs"

ITEMS = []


def add(fn, line, kind, inp, expected):
    ITEMS.append({"fn": fn, "line": line, "kind": kind, "input": inp, "expected": expected})


def table(key, name, path, columns, checks=None):
    """The helper `table(name, path, cols, checks)` (conflicts.rs:611), with
    its `kid("t:{name}")` id carried as a key and its hardcoded line 3 made
    explicit."""
    row = {"key": key, "name": name, "kind": "Table", "path": path, "line": 3,
           "columns": columns}
    if checks is not None:
        row["check_constraints"] = checks
    return row


def enum(key, label, meanings, name="account.category = 'A'"):
    """The helper `enum_meaning(meanings)` (conflicts.rs:811), which always
    builds one `EnumMeaning` object named `account.category = 'A'` with
    `kid("enum:a")`; the key is carried so the two spellings-test objects can
    share it exactly as the test's two helper calls do."""
    return {
        "key": key,
        "name": name,
        # ObjectKind::Custom is `#[serde(untagged)]`: a plain string.
        "kind": "EnumMeaning",
        "properties": {"label": label, "meanings": meanings},
    }


# ── type_aliases_are_one_type (conflicts.rs:649) ─────────────────────────────
for _a, _b, _same in [
    ("INT", "integer", True),
    ("serial", "int4", True),
    ("BOOLEAN", "bool", True),
    ("character varying(20)", "VARCHAR (20)", True),
    ("timestamp with time zone", "timestamptz", True),
    ("NUMERIC(10, 2)", "decimal(10,2)", True),
    ("int", "bigint", False),
    ("varchar(20)", "varchar(40)", False),
]:
    add("type_aliases_are_one_type", 649, "normalize_type_pair",
        {"a": _a, "b": _b}, {"same": _same})

# ── a_table_defined_twice_differently... (conflicts.rs:665) ──────────────────
add("a_table_defined_twice_differently_is_a_conflict_and_collapses_to_the_last", 665,
    "duplicate_definitions",
    {"objects": [
        table("t:user_preference", "user_preference", "sql/Pg-database.sql",
              [{"name": "id", "data_type": "int"},
               {"name": "language", "data_type": "varchar(6)"}]),
        table("t:user_preference", "user_preference", "sql/changes/1.9/transpose_user_prefs.sql",
              [{"name": "id", "data_type": "serial"},
               {"name": "user_id", "data_type": "INT"},
               {"name": "name", "data_type": "text"}],
              checks=[{"expression": "user_id IS NULL OR user_id > 0"}]),
    ]},
    {"remaining_count": 1,
     "remaining_columns_contain": "user_id",
     "conflicts_count": 1,
     "first_conflict": {
         "name": "user_preference.columns",
         "attribute": "columns",
         "conflict_type": "duplicate_definition",
         "status": "open",
         "claims_paths": ["sql/Pg-database.sql", "sql/changes/1.9/transpose_user_prefs.sql"],
         "evidence_count": 2,
     },
     "disputes_to_first_remaining": True})

# ── identical_duplicates_collapse_silently (conflicts.rs:712) ────────────────
_cols = [{"name": "id", "data_type": "int"}]
add("identical_duplicates_collapse_silently", 712, "duplicate_definitions",
    {"objects": [
        table("t:t", "t", "a.sql", _cols),
        table("t:t", "t", "b.sql", _cols),
    ]},
    {"remaining_count": 1, "conflicts_count": 0})

# ── a_column_type_disagreement_is_its_own_conflict (conflicts.rs:723) ────────
add("a_column_type_disagreement_is_its_own_conflict", 723, "duplicate_definitions",
    {"objects": [
        table("t:t", "t", "a.sql",
              [{"name": "amount", "data_type": "int", "not_null": True}]),
        table("t:t", "t", "b.sql",
              [{"name": "AMOUNT", "data_type": "numeric(10,2)"}]),
    ]},
    {"conflicts_count": 1,
     "first_conflict": {"attribute": "columns.amount.data_type", "chosen": "numeric(10,2)"}})

# ── detection_is_independent_of_input_order_and_ids_are_stable (745) ─────────
# One item, run forward and (by the dump) reversed: id, claims and signature
# must survive the permutation — exactly what the test asserts by comparing
# the two runs.
add("detection_is_independent_of_input_order_and_ids_are_stable", 745,
    "duplicate_definitions",
    {"also_reversed": True,
     "objects": [
         table("t:t", "t", "a.sql", [{"name": "x", "data_type": "int"}]),
         table("t:t", "t", "b.sql", [{"name": "x", "data_type": "text"}]),
     ]},
    {"conflicts_count": 1,
     "first_conflict": {"attribute": "columns.x.data_type"},
     "permuted_stable": True})

# ── merge_groups_report_what_the_merge_would_drop (conflicts.rs:780) ─────────
# The exact-name group reports the attribute the merge would drop; the fuzzy
# copy of the same proposal reports nothing.
_merge_objects = [
    table("t:orders", "orders", "schema.sql", [{"name": "total", "data_type": "int"}]),
    table("orm:orders", "orders", "models/orders.py", [{"name": "total", "data_type": "bigint"}]),
]
_proposal = {"canonical_key": "t:orders", "canonical_name": "orders",
             "canonical_kind": "Table", "source_keys": ["t:orders", "orm:orders"],
             "confidence": 1.0, "exact_name_match": True}
add("merge_groups_report_what_the_merge_would_drop", 780, "merge_losses",
    {"objects": _merge_objects, "proposals": [_proposal]},
    {"conflicts_count": 1,
     "first_conflict": {"attribute": "columns.total.data_type",
                        "conflict_type": "merge_loss",
                        "chosen": "int"}})
add("merge_groups_report_what_the_merge_would_drop", 780, "merge_losses",
    {"objects": _merge_objects,
     "proposals": [{**_proposal, "exact_name_match": False}]},
    {"conflicts_count": 0})

# ── labels_from_different_sources_that_share_no_word_conflict (conflicts.rs:832)
_meanings = [
    {"label": "asset", "source": "column_comment", "path": "sql/Pg-database.sql", "line": 72},
    {"label": "L", "source": "case_label", "path": "sql/modules/FinStatements.sql", "line": 690},
]
add("labels_from_different_sources_that_share_no_word_conflict", 832,
    "label_mismatches",
    {"enums": [enum("enum:a", "asset", _meanings)]},
    {"conflicts_count": 1,
     "first_conflict": {"attribute": "label", "conflict_type": "label_mismatch",
                        "claims_count": 2}})

# ── spellings_of_one_label_and_same_source_variants_do_not (conflicts.rs:882) ─
# Both objects carry kid("enum:a") — the helper mints the same id for each —
# and neither is a conflict.
add("spellings_of_one_label_and_same_source_variants_do_not", 882,
    "label_mismatches",
    {"enums": [
        enum("enum:a", "asset", [
            {"label": "Sales Order", "source": "lookup_seed", "path": "a.sql"},
            {"label": "sales_order", "source": "app_constant", "path": "b.pm"},
            {"label": "SalesOrder", "source": "case_label", "path": "c.sql"},
        ]),
        enum("enum:a", "asset", [
            {"label": "asset", "source": "column_comment", "path": "a.sql"},
            {"label": "holding", "source": "column_comment", "path": "b.sql"},
        ]),
    ]},
    {"conflicts_count": 0})


def write(panel_path: Path, expected_path: Path) -> None:
    counts: dict = {}
    with panel_path.open("w") as panel, expected_path.open("w") as expected:
        for entry in ITEMS:
            fn = entry["fn"]
            counts[fn] = counts.get(fn, 0) + 1
            item_id = f"{fn}#{counts[fn]}"
            panel.write(json.dumps({
                "panel": "conflicts.unit",
                "item": item_id,
                "kind": entry["kind"],
                "origin": "test",
                "source": f"{CONFLICTS_RS}:{entry['line']} {fn}",
                "input": entry["input"],
            }, separators=(",", ":")) + "\n")
            expected.write(json.dumps({
                "item": item_id,
                "assert": entry["expected"],
            }, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    panel = root / "panels" / "conflicts" / "unit.jsonl"
    expected = root / "controls" / "conflicts.unit.expected.jsonl"
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
