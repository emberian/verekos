#!/usr/bin/env python3
"""Tests for project_conflict_keys.py. Run: python3 -I <this file>."""

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import project_conflict_keys as pk  # noqa: E402

ROOT = HERE.parent.parent


class Projection(unittest.TestCase):
    def test_kid_matches_ekos_ids_in_the_control(self):
        # `5146b1c0-…` is the id EKOS printed for the key "t:t" (control, item
        # identical_duplicates_collapse_silently#1, remaining[0].id).
        self.assertEqual(pk.kid("t:t"), "5146b1c0-218b-5ddc-a6c0-684b4a16b9d7")

    def test_conflict_becomes_its_key(self):
        inp = {"objects": [{"key": "t:t"}, {"key": "t:t"}]}
        ctl = {"item": "x", "conflicts": [
            {"subject_id": pk.kid("t:t"), "attribute": "columns.a.data_type", "chosen": "int"},
            {"subject_id": pk.kid("t:t"), "attribute": "columns", "chosen": ["a"]}],
            "remaining": [{"id": "whatever"}], "disputes": []}
        self.assertEqual(pk.project_line(ctl, inp), {"item": "x", "keys": [
            ["t:t", "columns"], ["t:t", "columns.a.data_type"]]})

    def test_no_conflict_is_an_empty_key_set_and_permuted_stable_is_kept(self):
        ctl = {"item": "x", "conflicts": [], "permuted_stable": True}
        self.assertEqual(pk.project_line(ctl, {}),
                         {"item": "x", "keys": [], "permuted_stable": True})

    def test_type_pair_keeps_only_same(self):
        ctl = {"item": "x", "a": "int", "b": "int", "same": True}
        self.assertEqual(pk.project_line(ctl, {"a": "INT", "b": "integer"}),
                         {"item": "x", "same": True})

    def test_unknown_subject_is_fatal(self):
        ctl = {"item": "x", "conflicts": [{"subject_id": pk.kid("nope"), "attribute": "a"}]}
        with self.assertRaises(ValueError):
            pk.project_line(ctl, {"objects": [{"key": "t:t"}]})

    def test_proposal_and_enum_keys_are_found(self):
        inp = {"proposals": [{"canonical_key": "t:o", "source_keys": ["t:o", "orm:o"]}],
               "enums": [{"key": "enum:a"}]}
        self.assertEqual(set(pk.keys_named(inp)), {"t:o", "orm:o", "enum:a"})

    def test_the_real_control_projects_every_line(self):
        panel = pk.read_jsonl(ROOT / "panels/conflicts/unit.jsonl")
        control = pk.read_jsonl(ROOT / "controls/conflicts.unit.control.jsonl")
        out = pk.project(panel, control)
        self.assertEqual(len(out), 16)
        self.assertEqual(sum(1 for l in out if "same" in l), 8)
        n_conflicts = sum(len(c.get("conflicts", [])) for c in control)
        self.assertEqual(sum(len(l.get("keys", [])) for l in out), n_conflicts)


if __name__ == "__main__":
    unittest.main()
