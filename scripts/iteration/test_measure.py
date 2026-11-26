"""Тести контракту вимірювача; не вимірюють швидкодію чи енергію."""
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from unittest import mock
from types import SimpleNamespace
from pathlib import Path

SCRIPT = Path(__file__).with_name("measure.py")
SPEC = importlib.util.spec_from_file_location("iteration_measure_under_test", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
measure = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(measure)


class IterationMeasureTests(unittest.TestCase):
    def test_type7_percentiles_preserve_tail(self):
        values = list(range(1, 11))
        self.assertAlmostEqual(measure.percentile(values, 10), 1.9)
        self.assertAlmostEqual(measure.percentile(values, 50), 5.5)
        self.assertAlmostEqual(measure.percentile(values, 90), 9.1)

    def test_summary_requires_twenty_positive_integer_samples(self):
        summary = measure.summary([1_000_000] * 20)
        self.assertEqual(summary["count"], 20)
        self.assertEqual(summary["p50_ns"], 1_000_000)
        for values in ([], [1] * 19, [0] * 20, [-1] * 20, [1.0] * 20):
            with self.subTest(values=values[:2]):
                with self.assertRaises(ValueError):
                    measure.summary(values)

    def test_percentile_rejects_invalid_quantiles_and_samples(self):
        for percent in (-0.1, 100.1):
            with self.subTest(percent=percent), self.assertRaises(ValueError):
                measure.percentile([1, 2], percent)
        for values in ([], [0], [1, -1], [1, 1.5]):
            with self.subTest(values=values), self.assertRaises(ValueError):
                measure.percentile(values, 50)

    def test_repetition_count_has_bounded_minimum_and_maximum(self):
        self.assertEqual(measure.validate_repetitions(20), 20)
        self.assertEqual(measure.validate_repetitions(100), 100)
        for count in (0, 1, 19, 101, -20):
            with self.subTest(count=count), self.assertRaises(ValueError):
                measure.validate_repetitions(count)

    def test_fpc_324_requires_exact_upstream_source_revision(self):
        for revision in (None, "3.2.4", "0" * 40, "66940ee65006538dba16b4c584d3cfb1cc08985e0"):
            with self.subTest(revision=revision), self.assertRaises(measure.MeasurementError):
                measure.inspect_compiler(Path("/not-used"), "3.2.4", "rtl-3.2.4", revision)

    def test_source_pinned_324_compiler_metadata_is_captured(self):
        with tempfile.TemporaryDirectory() as temporary:
            fpc = Path(temporary) / "fpc"
            fpc.write_text(
                "#!/bin/sh\n"
                "case \"$1\" in\n"
                "  -iV) printf '3.2.4\\n' ;;\n"
                "  -iTP) printf 'x86_64\\n' ;;\n"
                "  -iTO) printf 'linux\\n' ;;\n"
                "  *) exit 2 ;;\n"
                "esac\n",
                encoding="utf-8",
            )
            fpc.chmod(0o755)
            info, environment = measure.inspect_compiler(
                fpc, "3.2.4", "rtl-3.2.4-source", measure.FPC_324_SOURCE
            )
            self.assertEqual(info["version"], "3.2.4")
            self.assertEqual(info["target_cpu"], "x86_64")
            self.assertEqual(info["target_os"], "linux")
            self.assertEqual(info["source_revision"], measure.FPC_324_SOURCE)
            self.assertIn("operator-declared", info["source_revision_provenance"])
            self.assertEqual(environment["FPC"], str(fpc.resolve()))
            self.assertEqual(len(info["binary_sha256"]), 64)

    def test_unsupported_embedded_version_is_not_mixed_into_host_series(self):
        with self.assertRaises(measure.MeasurementError):
            measure.inspect_compiler(Path("/not-used"), "3.3.1", "rtl-snapshot", None)

    def test_source_revision_format_is_checked_for_322_when_present(self):
        for revision in ("tag-name", "abc", "g" * 40):
            with self.subTest(revision=revision), self.assertRaises(measure.MeasurementError):
                measure.inspect_compiler(Path("/not-used"), "3.2.2", "rtl-3.2.2", revision)

    def test_rapl_wrap_is_counted_and_ambiguous_gap_is_rejected(self):
        rapl = object.__new__(measure.PackageRapl)
        rapl.module = SimpleNamespace(
            counter_delta=lambda before, after, maximum: (after - before) % maximum
        )
        rapl.zones = [SimpleNamespace(name="package-0", maximum=100)]
        self.assertEqual(
            rapl.delta({"package-0": 95}, {"package-0": 4}, 99),
            {"package-0": 9},
        )
        self.assertIsNone(rapl.delta({"package-0": 95}, {"package-0": 4}, 100))
        self.assertIn("оберти", rapl.error)
        self.assertEqual(
            rapl.delta({"package-0": 10}, {"package-0": 19}, 9),
            {"package-0": 9},
        )
        self.assertEqual(rapl.error, "")

    def test_host_guard_rejects_cross_target_measurements(self):
        with mock.patch.object(measure.platform, "system", return_value="Darwin"):
            with self.assertRaises(measure.MeasurementError):
                measure.validate_host()

    def test_log_writer_never_overwrites_existing_sample(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            first = measure.write_log(directory, "cycle.stdout.log", b"BUILD-OK\n")
            self.assertEqual(first["bytes"], 9)
            with self.assertRaises(FileExistsError):
                measure.write_log(directory, "cycle.stdout.log", b"spoofed\n")
            self.assertEqual((directory / "cycle.stdout.log").read_bytes(), b"BUILD-OK\n")

    def test_cold_and_warm_commands_are_the_same_build_command(self):
        self.assertEqual(measure.MEASURE_COMMAND, ["bash", "scripts/build.sh"])
        self.assertEqual(measure.PRECHECK_COMMAND, ["bash", "scripts/test.sh"])
        args = measure.parse_args([
            "--expected-version", "3.2.2", "--rtl-id", "rtl", "--toolchain-id", "t",
            "--output-dir", "/tmp/out",
        ])
        self.assertFalse(hasattr(args, "command"))


if __name__ == "__main__":
    unittest.main()
