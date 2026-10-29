#!/usr/bin/env python3
import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("repl-core1-benchmark.py")
SPEC = importlib.util.spec_from_file_location("repl_core1_benchmark", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ReplOutputTests(unittest.TestCase):
    def test_accepts_core1_preamble_and_exact_replies(self):
        output = (
            "SENS Core1 REPL — українська проєкція\n"
            "Допущених визначень: 92 із 96.\n"
            "10000\n10000\n"
        ).encode()
        self.assertEqual(MODULE.validate_output(output, "core1", 2), ["10000", "10000"])

    def test_accepts_pinned_sens_preamble_and_exact_replies(self):
        output = (
            "SENS REPL версії 0.42.3\n"
            "Поверхня: українська (повна) (укр)\n"
            "D1 у канонічному поданні — 1/0\n"
            "10000\n10000\n"
        ).encode()
        self.assertEqual(MODULE.validate_output(output, "sens", 2), ["10000", "10000"])

    def test_accepts_pinned_sens_prompt_prefixes(self):
        output = (
            "SENS REPL версії 0.42.3\n"
            "Поверхня: українська (повна) (укр)\n"
            "D1 у канонічному поданні — 1/0\n"
            "sens[укр]> 10000\nsens[укр]> 10000\nsens[укр]> \n"
        ).encode()
        self.assertEqual(MODULE.validate_output(output, "sens", 2), ["10000", "10000"])

    def test_accepts_exact_core1_prompt_protocol(self):
        output = "????> ???? >;".encode()
        good = ("????> " * 3 + "; сеанс завершено\n").encode()
        MODULE.validate_stderr(good, "core1", 2)
        with self.assertRaises(ValueError):
            MODULE.validate_stderr(output, "core1", 2)

    def test_rejects_missing_or_wrong_result(self):
        for output in (b"10000\n", b"10000\n9999\n"):
            with self.subTest(output=output), self.assertRaises(ValueError):
                MODULE.validate_output(output, "sens", 2)

    def test_rejects_diagnostics_and_unknown_output_lines(self):
        for output in ("10000\nПомилка REPL\n".encode(), b"10000\nunexpected\n"):
            with self.subTest(output=output), self.assertRaises(ValueError):
                MODULE.validate_output(output, "sens", 1)

    def test_paired_analysis_reports_raw_and_idle_rate_adjusted_package_delta(self):
        rows = []
        for block in range(30):
            rows.extend([
                {"block": block, "lane": "core1", "seconds": 3.0,
                 "energy_uj": {"package-0": 30_000_000}},
                {"block": block, "lane": "sens", "seconds": 6.0,
                 "energy_uj": {"package-0": 60_000_000}},
                {"block": block, "lane": "idle", "seconds": 2.0,
                 "energy_uj": {"package-0": 10_000_000}},
            ])
        result = MODULE.paired_analysis(rows, 11)
        self.assertEqual(result["paired_package_energy_difference_core1_minus_sens_joules"]["median"], -30)
        self.assertEqual(result["paired_idle_rate_adjusted_difference_core1_minus_sens_joules"]["median"], -15)


if __name__ == "__main__":
    unittest.main()
