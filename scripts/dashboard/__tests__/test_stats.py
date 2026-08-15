import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

from src import stats


def _node(node_id, node_type="story", date=None):
    return {"id": node_id, "type": node_type, "date": date}


def _edge(source, target, kind):
    return {"source": source, "target": target, "kind": kind}


class TestBirthdayAndDays(unittest.TestCase):
    def test_birthday_is_oldest_node_date(self):
        result = stats.compute(
            [_node("a", date="2026-02-01"), _node("b", date="2026-01-15")], []
        )
        self.assertEqual(result["birthday"], "2026-01-15")

    def test_empty_corpus_yields_null_birthday_and_zero_days(self):
        result = stats.compute([], [])
        self.assertIsNone(result["birthday"])
        self.assertEqual(result["days_of_craft"], 0)

    def test_days_of_craft_spans_oldest_to_newest_node_date(self):
        result = stats.compute(
            [_node("a", date="2026-01-01"), _node("b", date="2026-01-11")], []
        )
        self.assertEqual(result["days_of_craft"], 10)

    def test_nodes_without_dates_are_ignored_for_birthday(self):
        result = stats.compute(
            [_node("a"), _node("b", date="2026-03-01")], []
        )
        self.assertEqual(result["birthday"], "2026-03-01")


class TestCounts(unittest.TestCase):
    def test_counts_tally_per_type_absent_types_omitted(self):
        result = stats.compute(
            [_node("a", "story"), _node("b", "story"), _node("c", "fix")], []
        )
        self.assertEqual(result["counts"], {"fix": 1, "story": 2})


class TestKeystone(unittest.TestCase):
    def test_keystone_is_highest_degree_node(self):
        nodes = [_node("a"), _node("b"), _node("c")]
        edges = [_edge("a", "b", "references"), _edge("c", "b", "references")]
        result = stats.compute(nodes, edges)
        self.assertEqual(result["keystone"]["id"], "b")
        self.assertEqual(result["keystone"]["degree"], 2)

    def test_tie_broken_by_earliest_date_then_id(self):
        nodes = [
            _node("late", date="2026-02-01"),
            _node("early", date="2026-01-01"),
        ]
        edges = [_edge("late", "early", "references")]
        result = stats.compute(nodes, edges)
        self.assertEqual(result["keystone"]["id"], "early")

    def test_lineage_kind_preferred_over_structural(self):
        nodes = [_node("a"), _node("b"), _node("c"), _node("d")]
        edges = [
            _edge("b", "a", "references"),
            _edge("c", "a", "references"),
            _edge("d", "a", "graduated_to"),
        ]
        result = stats.compute(nodes, edges)
        self.assertEqual(result["keystone"]["id"], "a")
        self.assertEqual(result["keystone"]["kind"], "graduated_to")

    def test_null_only_for_empty_corpus_single_edgeless_node_wins(self):
        result = stats.compute([_node("only", date="2026-01-01")], [])
        self.assertEqual(result["keystone"]["id"], "only")
        self.assertEqual(result["keystone"]["degree"], 0)
        self.assertIsNone(result["keystone"]["kind"])


if __name__ == "__main__":
    unittest.main()
