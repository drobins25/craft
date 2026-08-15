import importlib.util
import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

from src import coverage


def _load_inventory():
    fixture = os.path.join(
        os.path.dirname(_HERE), "__fixtures__", "link_inventory.py"
    )
    spec = importlib.util.spec_from_file_location("link_inventory", fixture)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.INVENTORY


INVENTORY = _load_inventory()


class TestCoverage(unittest.TestCase):
    def test_handled_plus_ruled_out_equals_the_inventory(self):
        declared = coverage.HANDLED | set(coverage.RULED_OUT)
        self.assertEqual(
            declared,
            INVENTORY,
            "unmapped: %r / stale: %r"
            % (
                sorted(INVENTORY - declared),
                sorted(declared - INVENTORY),
            ),
        )

    def test_no_pair_is_both_handled_and_ruled_out(self):
        overlap = coverage.HANDLED & set(coverage.RULED_OUT)
        self.assertEqual(overlap, set())

    def test_every_ruled_out_pair_has_a_reason(self):
        for pair, reason in coverage.RULED_OUT.items():
            self.assertTrue(reason.strip(), pair)

    def test_mechanism_is_not_vacuous_removing_a_handler_fails(self):
        broken = set(coverage.HANDLED)
        broken.discard(("story", "cycle"))
        self.assertNotEqual(broken | set(coverage.RULED_OUT), INVENTORY)


if __name__ == "__main__":
    unittest.main()
