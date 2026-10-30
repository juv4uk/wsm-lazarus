#!/usr/bin/env python3
"""G6.176: перевірки точного кадру до будь-якого вимірювання."""
# Questions: How does the byte-exact fixture catch a shared encode/decode bug?
# Why must no-clobber preserve both outputs? Why does signed D12 use 12 bits?
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SOURCE = Path(__file__).with_name("quot-runtime-benchmark.py")
if not SOURCE.is_file():
    raise AssertionError("відсутній quot-runtime-benchmark.py: очікуваний RED")
SPEC = importlib.util.spec_from_file_location("quot_energy", SOURCE)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class T5MExactFrame(unittest.TestCase):
    def test_d12_pair_round_trips_canonical_six_byte_host_frame(self):
        self.assertEqual(MODULE.encode_pair(0, 1), bytes((0, 0, 26, 0, 0, 53)))
        for left, right in ((7, 7), (-12, 3), (2047, 1), (-2048, -1)):
            frame = MODULE.encode_pair(left, right)
            self.assertEqual(len(frame), 6)
            self.assertEqual(MODULE.decode_pair(frame), (left, right))

    def test_result_is_canonical_three_byte_t5m_d12(self):
        self.assertEqual(MODULE.encode_result(1), bytes.fromhex("00 00 35"))
        for value in (-2048, -1, 0, 1, 2047):
            encoded = MODULE.encode_result(value)
            self.assertEqual(len(encoded), 3)
            self.assertEqual(MODULE.decode_result(encoded), value)

    def test_rejects_malformed_frames_without_decoding_a_partial_pair(self):
        valid = MODULE.encode_pair(21, 3)
        invalid = (b"", valid[:5], valid + b"x", bytes([255]) + valid[1:])
        for frame in invalid:
            with self.subTest(frame=frame), self.assertRaises(ValueError):
                MODULE.decode_pair(frame)

    def test_rejects_division_domain_failures(self):
        for left, right in ((1, 0), (7, 2), (-2048, -1)):
            with self.subTest(left=left, right=right), self.assertRaises(ValueError):
                MODULE.quotient_d12(left, right)

    def test_publishes_both_reports_without_clobber_or_temp_debris(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            report, samples = base / "run.json", base / "run.jsonl"
            MODULE.publish_pair(report, samples, {"status": "ENERGY_NOT_MEASURED"}, [])
            original = report.read_bytes(), samples.read_bytes()
            with self.assertRaises(ValueError):
                MODULE.publish_pair(report, samples, {"status": "fake"}, [])
            self.assertEqual((report.read_bytes(), samples.read_bytes()), original)
            self.assertEqual({path.name for path in base.iterdir()},
                             {report.name, samples.name})

    def test_second_link_failure_rolls_back_first_report(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            report, samples = base / "run.json", base / "run.jsonl"
            real_link = MODULE.os.link
            calls = 0

            def fail_second_link(source, target):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("injected second publication failure")
                real_link(source, target)

            with mock.patch.object(MODULE.os, "link", side_effect=fail_second_link):
                with self.assertRaises(OSError):
                    MODULE.publish_pair(report, samples, {"status": "measured"}, [])
            self.assertFalse(report.exists())
            self.assertFalse(samples.exists())
            self.assertEqual(list(base.iterdir()), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
