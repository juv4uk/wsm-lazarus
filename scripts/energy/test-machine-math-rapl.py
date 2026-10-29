#!/usr/bin/env python3
"""Механічні перевірки RAPL-драйвера; жоден тест не вигадує значень енергії.

Тести передають production-парсерам рядки, `Path`, цілі лічильники й парні
словники. Тимчасові каталоги та підміна власника живуть лише в межах тесту;
інтеграційний шлях збирає workers проти точного SENS worktree з
`SENS_SOURCE_DIR`.

Питання: які некоректні стани лічильника відхиляються? Чому відсутній
worktree пропускає лише інтеграційні тести? Який тест доводить, що публікація
не перезаписує попередні докази?
"""
import math
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from machine_math_rapl import (  # noqa: E402
    build_worker,
    parse_dot_bench_output,
    parse_worker_output,
    prepare_worker_temp,
    publish_pair,
    require_isa,
    run_dot_bench,
    run_worker,
    summarize_pairs,
    validate_authority_sha,
    validate_source_sha,
)
from measure import counter_delta, discover_zones  # noqa: E402


class MachineMathRaplTests(unittest.TestCase):
    def test_worker_result_accepts_one_finite_number_only(self):
        self.assertAlmostEqual(parse_worker_output("1.2345000000000000e+04\n"), 12345.0)

    def test_worker_result_rejects_extra_output_and_non_finite_values(self):
        for output in ("DOT_OK\n1.0\n", "nan\n", "inf\n", "", "1.0\n2.0\n"):
            with self.subTest(output=output), self.assertRaises(ValueError):
                parse_worker_output(output)

    def test_upstream_result_requires_exact_backend_and_success_marker(self):
        output = "BACKEND Avx2Fma\nSCALAR_SUM 1.25\nAVX2_SUM 1.25\nDOT_OK\n"
        self.assertEqual(parse_dot_bench_output(output), {"sse2": 1.25, "avx2": 1.25})
        for bad in (
            "BACKEND Other\nSCALAR_SUM 1\nAVX2_SUM 1\nDOT_OK\n",
            "BACKEND Avx2Fma\nSCALAR_SUM nan\nAVX2_SUM 1\nDOT_OK\n",
            "BACKEND Avx2Fma\nSCALAR_SUM 1\nAVX2_SUM 1\nSUM_MISMATCH\n",
        ):
            with self.subTest(output=bad), self.assertRaises(ValueError):
                parse_dot_bench_output(bad)

    def test_counter_wrap_uses_recorded_hardware_range(self):
        self.assertEqual(counter_delta(990, 15, 1000), 25)
        with self.assertRaises(ValueError):
            counter_delta(1000, 15, 1000)

    def test_root_build_temp_is_traversable_by_unprivileged_worker(self):
        with patch("machine_math_rapl.os.geteuid", return_value=0), \
             patch("machine_math_rapl.child_identity",
                   return_value={"user": 123, "group": 456}), \
             patch("machine_math_rapl.os.chown") as chown:
            prepare_worker_temp(Path("/tmp/build"))
        chown.assert_called_once_with(Path("/tmp/build"), 123, 456)

    def test_publish_pair_rejects_aliasing_artifact_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "same.json"
            with self.assertRaisesRegex(ValueError, "must be different"):
                publish_pair(target, target, {}, [])

    def test_publish_pair_assigns_created_directories_to_output_owner(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            results, samples = root / "out/results.json", root / "out/samples.jsonl"
            with patch("machine_math_rapl.os.chown") as chown, \
                 patch("machine_math_rapl.os.fchown"):
                publish_pair(results, samples, {"ok": True}, [], owner=(123, 456))
            chown.assert_called_once_with(results.parent, 123, 456)
            self.assertTrue(results.is_file())
            self.assertTrue(samples.is_file())

    def test_summary_requires_thirty_complete_randomized_pairs(self):
        pairs = [
            {"block": i, "sse2_package_uj": 1_000_000 + i,
             "avx2_package_uj": 900_000 + i, "idle_package_uj": 100_000,
             "sse2_elapsed_ns": 400_000_000, "avx2_elapsed_ns": 100_000_000,
             "idle_elapsed_ns": 5_000_000}
            for i in range(30)
        ]
        result = summarize_pairs(pairs, seed=598)
        self.assertEqual(result["pairs"], 30)
        self.assertEqual(result["median_avx2_minus_sse2_package_uj"], -100_000)
        self.assertEqual(result["ci95_package_uj"], [-100_000, -100_000])
        self.assertEqual(result["median_avx2_minus_sse2_elapsed_ns"], -300_000_000)
        self.assertEqual(result["ci95_elapsed_ns"], [-300_000_000, -300_000_000])
        self.assertNotIn("per_process_joules", result)
        for bad in (pairs[:29], pairs + [pairs[0]]):
            with self.subTest(count=len(bad)), self.assertRaises(ValueError):
                summarize_pairs(bad, seed=598)

    @unittest.skipUnless(os.environ.get("SENS_SOURCE_DIR"), "задай точний SENS_SOURCE_DIR для інтеграції")
    def test_isolated_workers_match_upstream_direct_kernel_benchmark(self):
        try:
            require_isa()
        except ValueError as error:
            self.skipTest(str(error))
        source = Path(os.environ["SENS_SOURCE_DIR"])
        with tempfile.TemporaryDirectory() as temp:
            binaries = build_worker(source, Path(temp))
            reference = parse_dot_bench_output(run_dot_bench(source, n=65536, repetitions=128))
            for kernel in ("sse2", "avx2"):
                result = run_worker(binaries[kernel], kernel, 65536, 128)
                self.assertTrue(math.isclose(result, reference[kernel], rel_tol=1e-12))

    @unittest.skipUnless(os.environ.get("SENS_SOURCE_DIR"), "задай точний SENS_SOURCE_DIR для інтеграції")
    def test_worker_rejects_bad_kernel_without_running_machine_code(self):
        try:
            require_isa()
        except ValueError as error:
            self.skipTest(str(error))
        source = Path(os.environ["SENS_SOURCE_DIR"])
        with tempfile.TemporaryDirectory() as temp:
            binaries = build_worker(source, Path(temp))
            proc = subprocess.run([str(binaries["sse2"]), "invalid", "65536", "1"],
                                  text=True, capture_output=True, check=False)
            self.assertEqual(proc.returncode, 64)
            self.assertIn("ядро має бути sse2 або avx2", proc.stderr)

    def test_source_sha_is_exact_and_fail_closed(self):
        self.assertTrue(validate_source_sha("33f0c4d1ea812a09dd121bd15ed741241d5dbc65"))
        with self.assertRaises(ValueError):
            validate_source_sha("1f1bf676eeac605e065035d9dd2adaae807f1788")

    def test_wsm_authority_pin_is_exact_and_fail_closed(self):
        self.assertTrue(validate_authority_sha("1f1bf676eeac605e065035d9dd2adaae807f1788"))
        with self.assertRaises(ValueError):
            validate_authority_sha("33f0c4d1ea812a09dd121bd15ed741241d5dbc65")

    def test_missing_rapl_is_not_converted_to_zero_energy(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(ValueError, "ENERGY_NOT_MEASURED"):
                discover_zones(temp)


if __name__ == "__main__":
    unittest.main(verbosity=2)
