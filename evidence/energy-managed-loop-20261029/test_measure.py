#!/usr/bin/env python3
"""Тести фактичного runtime протоколу та паритету трьох реалізацій."""
import os
import importlib.util
import subprocess
import unittest
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
BIN = HERE.parents[1] / "build/energy/managed-d12-loop"
N = "8388361"
RUNTIMES = {
    "go": ([str(BIN / "sum-go")], {"GOMAXPROCS": "1", "GOGC": "100"}),
    "hotspot": ([os.environ.get("JAVA", "java"), "-Xms32m", "-Xmx32m", "-XX:+UseSerialGC",
                 "-XX:+TieredCompilation", "-XX:ActiveProcessorCount=1", "-cp", str(BIN / "java"), "Sum"],
                {}),
    "dotnet": ([os.environ.get("DOTNET", "dotnet"), str(BIN / "dotnet/ManagedBench.dll")],
               {"DOTNET_gcServer": "0", "DOTNET_TieredCompilation": "1",
                "DOTNET_TieredPGO": "1", "DOTNET_ReadyToRun": "0",
                "DOTNET_GCHeapHardLimit": "02000000",
                "DOTNET_CLI_TELEMETRY_OPTOUT": "1", "DOTNET_NOLOGO": "1"}),
}
MEASURE_SPEC = importlib.util.spec_from_file_location("managed_measure", HERE / "measure.py")
MEASURE = importlib.util.module_from_spec(MEASURE_SPEC)
MEASURE_SPEC.loader.exec_module(MEASURE)


def invoke(runtime, args, payload=None):
    command, environment = RUNTIMES[runtime]
    env = os.environ.copy()
    env.update(environment)
    return subprocess.run(command + args, input=payload, text=True, capture_output=True,
                          timeout=90, env=env, check=False)


class ManagedLoopParity(unittest.TestCase):
    def test_artifacts_exist(self):
        self.assertTrue((BIN / "sum-go").is_file())
        self.assertTrue((BIN / "java/Sum.class").is_file())
        self.assertTrue((BIN / "dotnet/ManagedBench.dll").is_file())

    def test_cold_execution_returns_same_exact_low_byte(self):
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                result = invoke(runtime, ["single", N])
                self.assertEqual(result.returncode, 173)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, "")

    def test_missing_mode_or_arguments_are_rejected(self):
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                result = invoke(runtime, [])
                self.assertEqual(result.returncode, 64)
                self.assertEqual(result.stdout, "")

    def test_invalid_counts_are_rejected(self):
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                result = invoke(runtime, ["single", "0"])
                self.assertEqual(result.returncode, 65)
                self.assertEqual(result.stdout, "")

    def test_persistent_protocol_returns_correct_checksum_and_gc_counters(self):
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                result = invoke(runtime, ["server", N], "1\n50\n")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
                lines = result.stdout.splitlines()
                self.assertEqual(len(lines), 2)
                for line, count, checksum in zip(lines, (1, 50), (173, 202)):
                    fields = line.split("\t")
                    self.assertEqual(fields[:3], ["OK", str(count), str(checksum)])
                    self.assertEqual(len(fields), 5)
                    self.assertGreaterEqual(int(fields[3]), 0)
                    self.assertGreaterEqual(int(fields[4]), 0)

    def test_invalid_persistent_request_is_rejected(self):
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                result = invoke(runtime, ["server", N], "0\n")
                self.assertEqual(result.returncode, 65)
                self.assertEqual(result.stdout, "")
                self.assertIn("invalid repetitions", result.stderr)

    def test_pinned_native_sens_elf_has_the_same_answer(self):
        sens_elf = BIN / "sens-native.elf"
        result = subprocess.run([str(sens_elf)], capture_output=True, timeout=15, check=False)
        self.assertEqual(result.returncode, 173)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"")

    def test_pairwise_summary_uses_matched_blocks_and_normalizes_batches(self):
        rows = []
        for block in range(30):
            idle_energy = 1_000_000 + block * 10_000
            rows.append({"phase": "cold", "block": block, "lane": "idle", "seconds": 1.0,
                         "elapsed_seconds": 1.0, "operations_per_program": 0,
                         "process_cpu_seconds": 0.0, "rss_kib": None, "gc_count": 0,
                         "gc_pause_ms": 0, "user_cpu_seconds": 0.0, "system_cpu_seconds": 0.0,
                         "energy_uj": {"package-0": idle_energy}})
            for lane, energy_delta, elapsed in (("go", 100_000, 5.0), ("hotspot", 150_000, 10.0)):
                rows.append({"phase": "cold", "block": block, "lane": lane, "seconds": 1.0,
                             "elapsed_seconds": elapsed, "operations_per_program": 5,
                             "process_cpu_seconds": 1.0, "rss_kib": 100, "gc_count": None,
                             "gc_pause_ms": None, "user_cpu_seconds": .8, "system_cpu_seconds": .2,
                             "energy_uj": {"package-0": idle_energy + energy_delta}})
        result = MEASURE.summarize_phase(rows, "cold", [SimpleNamespace(name="package-0")],
                                         ("go", "hotspot"), 30, 600)
        contrast = result["pairwise_differences"]["go_minus_hotspot"]
        energy = contrast["energy_joules_per_operation_difference"]
        elapsed = contrast["elapsed_seconds_per_operation_difference"]
        self.assertEqual(contrast["paired_blocks"], 30)
        self.assertAlmostEqual(energy["median"], -.01, places=9)
        self.assertAlmostEqual(elapsed["median"], -1.0, places=9)
        self.assertAlmostEqual(energy["bootstrap_95_percentile_interval"][0], -.01, places=9)
        self.assertAlmostEqual(energy["bootstrap_95_percentile_interval"][1], -.01, places=9)


if __name__ == "__main__":
    unittest.main(verbosity=2)
