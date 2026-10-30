#!/usr/bin/env python3
"""GЕ.8 — механічні негативи без вигаданих фізичних джоулів."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).with_name("compare-four-elf.py")
SPEC = importlib.util.spec_from_file_location("four_elf_energy", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def good_manifest():
    return {
        "схема": "sens-elf-c-rust-fpc-coldstart/1",
        "pinned_SENS_SHA": MODULE.PIN,
        "енергія": "ENERGY_NOT_MEASURED",
        "виконувані": {
            case + "/" + lang: {"sha256": "a" * 64, "ELF_байтів": 1}
            for case in MODULE.CASES for lang in MODULE.LANGS
        },
    }


class NegativeWitnesses(unittest.TestCase):
    def test_16_distinct(self):
        self.assertEqual(len(MODULE.validate_manifest(good_manifest())), 16)

    def test_broken_manifest(self):
        for field, value in (
            ("схема", "wrong"), ("pinned_SENS_SHA", "not-pinned"),
            ("енергія", "0J"), ("виконувані", {})):
            x = good_manifest()
            x[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                MODULE.validate_manifest(x)

    def test_per_entry_bad_and_misleading(self):
        variants = [
            {"sha256": "z" * 64, "ELF_байтів": 1},
            {"sha256": "a" * 63, "ELF_байтів": 1},
            {"sha256": "a" * 64, "ELF_байтів": 0},
            {"sha256": "a" * 64, "ELF_байтів": True},
            {"sha256": "a" * 64, "ELF_байтів": 1.5},
            {"sha256": "a" * 64},
        ]
        for item in variants:
            x = good_manifest()
            x["виконувані"][next(iter(x["виконувані"]))] = item
            with self.subTest(item=item), self.assertRaises(ValueError):
                MODULE.validate_manifest(x)

    def test_tampered_extra_or_missing_program(self):
        for extra in (True, False):
            x = good_manifest()
            if extra:
                x["виконувані"]["other/evil"] = {"sha256": "a" * 64, "ELF_байтів": 1}
            else:
                x["виконувані"].pop(next(iter(x["виконувані"])))
            with self.assertRaises(ValueError):
                MODULE.validate_manifest(x)

    def test_evidence_json_strict_positive_and_nested_negatives(self):
        # Жодної RAPL-енергії: тільки допуск байтів паспорта 16 ELF.
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = root / "паспорт.json"
            valid = json.dumps(good_manifest(), ensure_ascii=False).encode("utf-8")
            path.write_bytes(valid)
            self.assertEqual(len(MODULE.validate_manifest(
                MODULE.load_evidence_json(path))), 16)

            invalid = {
                "верхній-дубль": valid.replace(
                    b'"pinned_SENS_SHA": ', b'"pinned_SENS_SHA": "other", "pinned_SENS_SHA": ', 1),
                "вкладений-дубль": valid.replace(
                    b'"sha256": ', b'"sha256": "tampered", "sha256": ', 1),
                "нечисловий-NaN": valid[:-1] + b', "false_energy": NaN}',
                "нечисловий-Infinity": valid[:-1] + b', "false_energy": Infinity}',
                "нечисловий-negative-Infinity": valid[:-1] + b', "false_energy": -Infinity}',
                "зламаний-UTF8": b'{"схема": "' + bytes([255]) + b'"}',
                "порожній": b"",
                "скаляр": b"42",
            }
            for name, content in invalid.items():
                with self.subTest(name=name):
                    path.write_bytes(content)
                    with self.assertRaises(ValueError):
                        MODULE.load_evidence_json(path)

            path.write_bytes(valid)
            link = root / "посилання.json"
            link.symlink_to(path)
            with self.assertRaisesRegex(ValueError, "посиланням"):
                MODULE.load_evidence_json(link)
            large = root / "завеликий.json"
            with large.open("wb") as out:
                out.truncate(16_000_001)
            with self.assertRaisesRegex(ValueError, "завеликий"):
                MODULE.load_evidence_json(large)
            # Після всіх відмов той самий правильний паспорт приймається.
            self.assertEqual(len(MODULE.validate_manifest(
                MODULE.load_evidence_json(path))), 16)

    def test_output_fail_closed(self):
        cwd = Path.cwd()
        for source, wanted in (
            ("import sys;sys.stdout.buffer.write(b'0')", b"1"),
            ("import sys;sys.stdout.buffer.write(b'00')", b"0"),
            ("import sys;sys.exit(3)", b""),
            ("import sys;sys.stderr.write('ERROR')", b""),
        ):
            with self.subTest(source=source), self.assertRaises(ValueError):
                MODULE.run([sys.executable, "-c", source], cwd, wanted=wanted)

    def test_rapl_is_existing_strict_parser(self):
        raw = (b"RAPL-DELTA1\telapsed_us=50000\tmax_watts=1000\n"
               b"intel-rapl:0\tpackage-0\t99999990\t20\t100000000\t30\n")
        self.assertEqual(MODULE.RAPL_PARSER(raw, 50000, 1000),
                         {"intel-rapl:0": 30})
        for bad in (raw.replace(b"\t30\n", b"\t31\n"),
                    raw.replace(b"intel-rapl:0", b"forged"),
                    raw + raw.splitlines()[1] + b"\n"):
            with self.assertRaises(ValueError):
                MODULE.RAPL_PARSER(bad, 50000, 1000)

    def test_no_fake_sensor_and_no_json(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "result.json"
            args = type("Args", (), {"блоки": 30, "повторів": 30,
                   "макс_ват": 1000, "idle_ms": 50,
                   "rapl": Path("/missing/sensrapl"),
                   "живлення": Path(td), "корінь": Path(td)})()
            with self.assertRaisesRegex(ValueError, "ENERGY_NOT_MEASURED"):
                MODULE.measure(args, [])
            self.assertFalse(out.exists())

    def test_atomic_no_clobber_and_no_nan(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "свідок.json"
            MODULE.publish(path, {"статус": "ENERGY_NOT_MEASURED"})
            original = path.read_bytes()
            with self.assertRaises(ValueError):
                MODULE.publish(path, {"статус": "HARDWARE_RAPL_MEASURED"})
            self.assertEqual(path.read_bytes(), original)
            broken = Path(td) / "неприпустимий.json"
            with self.assertRaises(ValueError):
                MODULE.publish(broken, {"joules": float("nan")})
            self.assertFalse(broken.exists())
            self.assertFalse(list(Path(td).glob(".sens-rapl-*")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
