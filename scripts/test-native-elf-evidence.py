#!/usr/bin/env python3
"""Негативні механічні перевірки G6.151 без вигаданого SENS oracle."""
import hashlib
import json
import os
from pathlib import Path
import platform
import struct
import subprocess
import sys
import tempfile
import unittest


CLI = Path(__file__).with_name("native-elf-evidence.py")
PAYLOAD = b"\x84\x00\x00"


def test_elf(payload=PAYLOAD, machine=None):
    # Тестовий ELF — лише host witness Linux, не SENS-програма/компілятор.
    if machine is None:
        machine = (b"\xb8\x01\x00\x00\x00"    # mov eax,1
                   b"\xbf\x01\x00\x00\x00"    # mov edi,1
                   b"\x48\x8d\x35" + struct.pack("<i", 16) +
                   b"\xba" + struct.pack("<I", len(payload)) +
                   b"\x0f\x05"                   # write(1,data,len)
                   b"\xb8\x3c\x00\x00\x00"    # exit(0)
                   b"\x31\xff\x0f\x05")
    image = bytearray(120 + len(machine) + len(payload))
    image[:4] = b"\x7fELF"
    image[4:7] = b"\x02\x01\x01"
    struct.pack_into("<HHI", image, 16, 3, 62, 1)
    struct.pack_into("<QQQ", image, 24, 120, 64, 0)
    struct.pack_into("<I", image, 48, 0)
    struct.pack_into("<HHHHHH", image, 52, 64, 56, 1, 0, 0, 0)
    struct.pack_into("<IIQQQQQQ", image, 64, 1, 5, 0, 0, 0,
                     len(image), len(image), 4096)
    image[120:] = machine + payload
    return bytes(image)


@unittest.skipUnless(sys.platform == "linux" and platform.machine() == "x86_64",
                     "машинний профіль — Linux x86-64")
class TestNativeELFEvidence(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.source = root / "джерело.sens"
        self.expected = root / "очікуване.sens"
        self.elf = root / "машина.elf"
        self.report = root / "доказ.json"
        self.source.write_bytes(b"\x08\x00")
        self.expected.write_bytes(PAYLOAD)
        self.elf.write_bytes(test_elf())
        self.elf.chmod(0o700)

    def run_cli(self, source=None, expected=None, elf=None, seconds="2"):
        return subprocess.run([
            sys.executable, str(CLI),
            "--джерело", str(source or self.source),
            "--машина", str(elf or self.elf),
            "--очікувано", str(expected or self.expected),
            "--звіт", str(self.report),
            "--межа-секунд", seconds,
        ], capture_output=True, text=True, timeout=15)

    def reject(self, *args, **kwargs):
        result = self.run_cli(*args, **kwargs)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("НАТИВНИЙ-ELF-ВІДМОВА", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertFalse(self.report.exists())

    def test_actual_machine_and_owned_report(self):
        r = self.run_cli()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stderr, "")
        data = json.loads(self.report.read_text(encoding="utf-8"))
        self.assertEqual(data["статус"], "побайтово_виконано")
        self.assertEqual(data["elf_host_тип"], "ET_DYN")
        self.assertEqual(data["виконане_sha256"], hashlib.sha256(PAYLOAD).hexdigest())
        self.assertEqual(data["енергія"], "ENERGY_NOT_MEASURED")
        self.assertEqual(data["семантичний_оракул"], "НЕ_ПЕРЕВІРЕНО")
        self.assertGreater(data["час_процесу_нс"], 0)
        self.assertEqual(self.report.stat().st_mode & 0o777, 0o600)

    def test_physical_mismatch(self):
        self.expected.write_bytes(b"\x84\x00\x01")
        self.reject()

    def test_rwx_is_forbidden(self):
        b = bytearray(self.elf.read_bytes())
        struct.pack_into("<I", b, 68, 7)
        self.elf.write_bytes(b)
        self.reject()

    def test_unsupported_machine(self):
        b = bytearray(self.elf.read_bytes())
        struct.pack_into("<H", b, 18, 3)
        self.elf.write_bytes(b)
        self.reject()

    def test_executable_permission(self):
        self.elf.chmod(0o600)
        self.reject()

    def test_text_source_not_physical(self):
        name = self.source.with_suffix(".lisp")
        name.write_bytes(self.source.read_bytes())
        self.reject(source=name)

    def test_missing_source(self):
        self.reject(source=self.source.parent / "missing.sens")

    def test_symlink_machine(self):
        link = self.elf.parent / "link.elf"
        link.symlink_to(self.elf)
        self.reject(elf=link)

    def test_infinite_machine_timeout(self):
        self.elf.write_bytes(test_elf(payload=b"", machine=b"\xeb\xfe"))
        self.reject(seconds="0.1")

    def test_no_clobber(self):
        self.report.write_text("НЕЗМІННО", encoding="utf-8")
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.report.read_text(encoding="utf-8"), "НЕЗМІННО")

    def test_output_symlink_no_clobber(self):
        dest = self.report.parent / "external"
        dest.write_text("НЕЗМІННО", encoding="utf-8")
        self.report.symlink_to(dest)
        r = self.run_cli()
        self.assertEqual(r.returncode, 2)
        self.assertEqual(dest.read_text(encoding="utf-8"), "НЕЗМІННО")


    def test_actual_et_exec_machine(self):
        # Та сама тестова машинна програма без PIE: реальний Linux ET_EXEC.
        # 1) Чому entry містить базову адресу? 2) Чому payload не є оракулом?
        # 3) Чим відрізняються ET_EXEC і ET_DYN? 4) Хто володіє доказом?
        image = bytearray(self.elf.read_bytes())
        base = 0x400000
        struct.pack_into("<H", image, 16, 2)
        struct.pack_into("<Q", image, 24, base + 120)
        struct.pack_into("<QQ", image, 80, base, base)
        self.elf.write_bytes(image)
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        proof = json.loads(self.report.read_text(encoding="utf-8"))
        self.assertEqual(proof["elf_host_тип"], "ET_EXEC")
        self.assertEqual(proof["виконане_sha256"], hashlib.sha256(PAYLOAD).hexdigest())
        self.assertEqual(proof["енергія"], "ENERGY_NOT_MEASURED")
        self.assertEqual(proof["семантичний_оракул"], "НЕ_ПЕРЕВІРЕНО")

    def test_wrong_entry_is_not_machine_proof(self):
        image = bytearray(self.elf.read_bytes())
        struct.pack_into("<Q", image, 24, 0)
        self.elf.write_bytes(image)
        self.reject()

    def test_wrong_segment_extent_is_not_machine_proof(self):
        image = bytearray(self.elf.read_bytes())
        struct.pack_into("<Q", image, 96, len(image) - 1)
        self.elf.write_bytes(image)
        self.reject()

    def test_correct_stdout_with_nonzero_exit_is_not_proof(self):
        # Після write(1, PAYLOAD) syscall exit(2) замість exit(0).
        # 1) Чому stdout недостатній? 2) Де код завершення?
        # 3) Чому звіт не можна створювати? 4) Чи є це SENS-семантикою?
        image = bytearray(self.elf.read_bytes())
        self.assertEqual(image[149:151], b"\x31\xff")  # xor edi,edi
        image[149:151] = b"\xff\xc7"  # inc edi; rdi: 1 -> 2
        self.elf.write_bytes(image)
        self.reject()

    def test_machine_stderr_is_not_success(self):
        # Замінити машинний file descriptor 1 на 2, не чіпаючи фізичний payload.
        image = bytearray(self.elf.read_bytes())
        self.assertEqual(image[126], 1)  # mov edi,1
        image[126] = 2  # write(2, PAYLOAD) -> діагностика, не відповідь
        self.elf.write_bytes(image)
        self.reject()

    def test_output_above_quota_is_not_success(self):
        # Успішний хибний успіх через обрізаний stdout заборонено.
        self.elf.write_bytes(test_elf(payload=b"X" * 65537))
        self.reject()


if __name__ == "__main__":
    unittest.main(verbosity=2)
