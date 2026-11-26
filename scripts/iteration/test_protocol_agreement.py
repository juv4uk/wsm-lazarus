# SPDX-License-Identifier: LicenseRef-Volnist
"""The runner and the protocol must state the same numbers.

`docs/chas-iteratsii.uk.md` fixes what a valid iteration-time series is: at
least 20 repetitions per state, a median together with a tail quantile, and a
monotonic clock. `scripts/iteration/measure.py` implements it.

Two places, one rule. That combination has already gone wrong in this
ecosystem: a census number lived in a test and in a document, the document fell
two behind, and nobody saw it because the test was about something else.

So neither side may drift silently: lowering the repetition floor to make CI
faster, or dropping p90 from the report because the median is easier to quote,
fails here.
"""

from __future__ import annotations

import importlib.util
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROTOCOL = ROOT / "docs" / "chas-iteratsii.uk.md"
RUNNER = ROOT / "scripts" / "iteration" / "measure.py"


def load_runner():
    spec = importlib.util.spec_from_file_location("iteration_measure", RUNNER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


runner = load_runner()


class ProtocolAgreementTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = PROTOCOL.read_text(encoding="utf-8")

    def test_protocol_still_requires_twenty_repetitions(self) -> None:
        self.assertIn("n ≥ 20 повторів", self.text.lower())

    def test_runner_minimum_matches_the_protocol(self) -> None:
        self.assertEqual(runner.MIN_REPETITIONS, 20)

    def test_protocol_still_requires_a_tail_quantile(self) -> None:
        self.assertIn("p90", self.text)

    def test_runner_reports_a_tail_quantile(self) -> None:
        summary = runner.summary([1000 + index for index in range(20)])
        self.assertIn("p90_ns", summary)
        self.assertIn("p50_ns", summary)
        self.assertGreater(summary["p90_ns"], summary["p50_ns"])

    def test_protocol_requires_the_cache_state_to_be_described(self) -> None:
        """A "warm" label on a page cache nobody controlled is a false claim."""
        self.assertIn("стан кешу описувати буквально", self.text.lower())

    def test_runner_declares_the_monotonic_clock_in_its_report(self) -> None:
        self.assertIn("monotonic", RUNNER.read_text(encoding="utf-8"))

    def test_protocol_forbids_publishing_a_single_run(self) -> None:
        self.assertIn("один прогін як результат", self.text.lower())

    def test_runner_refuses_fewer_than_the_minimum(self) -> None:
        with self.assertRaises(ValueError):
            runner.summary([1000] * (runner.MIN_REPETITIONS - 1))


if __name__ == "__main__":
    unittest.main()
