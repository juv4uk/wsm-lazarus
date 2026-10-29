#!/usr/bin/env python3
"""G6.143: незалежні негативи host-вимірювача й реальні ELF інтеграційні тести.

Справжній ELF та canonical T5M встановлює FPC CI; тест їх не вигадує.
"""
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
TOOL = HERE / "sens-elf-sample.py"
SPEC = importlib.util.spec_from_file_location("sens_elf_sample", TOOL)
METER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(METER)


def synthetic_header() -> bytes:
    """Лише host-структура для unit-негативів, НЕ виконуваний ELF."""
    data = bytearray(120)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<HH", data, 16, 3, 62)
    struct.pack_into("<Q", data, 32, 64)
    struct.pack_into("<HH", data, 54, 56, 1)
    struct.pack_into("<I", data, 64, 1)
    return bytes(data)


class GeometryTests(unittest.TestCase):
    def test_host_header(self):
        METER.check_elf(synthetic_header())

    def test_forbid_dynamic_segment(self):
        data = bytearray(synthetic_header())
        struct.pack_into("<I", data, 64, 2)
        with self.assertRaises(METER.WitnessError):
            METER.check_elf(data)

    def test_forbid_interpreter(self):
        data = bytearray(synthetic_header())
        struct.pack_into("<I", data, 64, 3)
        with self.assertRaises(METER.WitnessError):
            METER.check_elf(data)

    def test_forbid_wrong_machine(self):
        data = bytearray(synthetic_header())
        struct.pack_into("<H", data, 18, 3)
        with self.assertRaises(METER.WitnessError):
            METER.check_elf(data)

    def test_forbid_truncated_phdr(self):
        data = bytearray(synthetic_header())
        struct.pack_into("<Q", data, 32, 115)
        with self.assertRaises(METER.WitnessError):
            METER.check_elf(data)


class RealELFTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        paths = [os.environ.get("SENS_SAMPLE_SOURCE"),
                 os.environ.get("SENS_SAMPLE_ELF"),
                 os.environ.get("SENS_SAMPLE_EXPECTED")]
        if not all(paths):
            raise unittest.SkipTest("реальний FPC ELF доступний лише після збірки CI")
        cls.source, cls.elf, cls.expected = map(Path, paths)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def sample(self, source=None, elf=None, expected=None, *extra):
        cmd = [sys.executable, str(TOOL),
               "--source", str(source or self.source),
               "--elf", str(elf or self.elf),
               "--expected", str(expected or self.expected),
               "--repeats", "3", "--warmup", "0", *extra]
        return subprocess.run(cmd, capture_output=True, text=True, timeout=35)

    def test_actual_machine_bytes_and_provenance(self):
        p = self.sample()
        self.assertEqual(p.returncode, 0, p.stderr)
        data = json.loads(p.stdout)
        self.assertEqual(data["побайтовий_збіг"], 3)
        self.assertEqual(data["джоулі"], "НЕ_ВИМІРЯНО")
        self.assertEqual(data["семантичний_оракул"],
                         "НЕ_ЗАПУСКАВСЯ_ЦИМ_ВИМІРЮВАЧЕМ")
        self.assertEqual(len(data["виконуваний_elf64_sha256"]), 64)
        self.assertGreater(data["медіана_часу_нс"], 0)

    def test_corrupt_expected_is_atomic_failure(self):
        destination = self.root / "помилкова.sens"
        physical = bytearray(self.expected.read_bytes())
        physical[0] ^= 1
        destination.write_bytes(physical)
        p = self.sample(expected=destination)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")
        self.assertIn("ЕЛЬФ-ВИМІР-ВІДМОВА", p.stderr)

    def test_invalid_binary_never_runs(self):
        target = self.root / "підробка.elf"
        target.write_bytes(b"\x7fELF")
        target.chmod(0o700)
        p = self.sample(elf=target)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")

    def test_forbid_symlink_and_lisp_input(self):
        link = self.root / "посилання.elf"
        link.symlink_to(self.elf)
        p = self.sample(elf=link)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")
        impostor = self.root / "людська.lisp"
        impostor.write_bytes(self.source.read_bytes())
        p = self.sample(source=impostor)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")

    def test_limits_and_missing_files(self):
        p = self.sample(None, None, None, "--repeats", "0")
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")
        p = self.sample(expected=self.root / "немає.sens")
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
