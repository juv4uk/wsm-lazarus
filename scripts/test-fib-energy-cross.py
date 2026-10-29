#!/usr/bin/env python3
"""G6.138 — механічні негативи й єдиний wrap із фізичної межі sysfs.

Жоден результат із mock-root не є фізичними джоулями.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

METER = Path(__file__).with_name("run-fib-energy-cross.py")


class CrossEnergyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.zone = self.base / "intel-rapl:0"
        self.zone.mkdir()
        (self.zone / "name").write_text("package-0\n", encoding="ascii")
        (self.zone / "energy_uj").write_text("84\n", encoding="ascii")
        (self.zone / "max_energy_range_uj").write_text("100\n", encoding="ascii")
        self.bin = self.base / "обчислювач"
        self.bin.write_text(
            "#!/usr/bin/env python3\n"
            "from pathlib import Path\n"
            "import os,sys\n"
            "p=Path(os.environ['FAKE_COUNTER'])\n"
            "v=int(p.read_text())\n"
            "p.write_text(str((v+9)%100))\n"
            "sys.exit(int(os.getenv('FAKE_EXIT','7')))\n",
            encoding="utf-8",
        )
        self.bin.chmod(0o700)
        self.shadow = self.base / "shadow_energy"
        self.shadow.write_text("0\n", encoding="ascii")

    def run_meter(self, *args, expected=7, mock=True, env_override=None):
        env = os.environ.copy()
        env["FAKE_COUNTER"] = str(self.zone / "energy_uj")
        if env_override:
            env.update(env_override)
        cmd = [sys.executable, str(METER), "--program", f"SENS={self.bin}",
               "--expected", str(expected), "--repeats", "3", "--warmup", "0"]
        if mock:
            cmd += ["--mock-root", str(self.base)]
        cmd += list(args)
        return subprocess.run(cmd, capture_output=True, text=True,
                              timeout=15, env=env)

    def test_mock_wrap_range_and_label(self):
        p = self.run_meter()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("СИМУЛЬОВАНО-НЕ-ФІЗИЧНА-ЕНЕРГІЯ", p.stdout)
        self.assertIn("range_uj=100", p.stdout)
        self.assertIn("медіана_мкДж=9", p.stdout)
        self.assertIn("FIB-CROSS-ENERGY-PASS", p.stdout)

    def test_verify_only_never_claims_energy(self):
        p = self.run_meter("--verify-only", mock=False)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("енергія=НЕ-ВИМІРЯНО", p.stdout)
        self.assertNotIn("медіана_мкДж", p.stdout)

    def test_wrong_result_never_publishes_numbers(self):
        p = self.run_meter(env_override={"FAKE_EXIT": "8"})
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")
        self.assertIn("FIB-CROSS-ВІДМОВА", p.stderr)

    def test_missing_meter_never_publishes(self):
        (self.zone / "energy_uj").unlink()
        p = self.run_meter(env_override={"FAKE_COUNTER": str(self.shadow)})
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")

    def test_missing_range_never_publishes(self):
        (self.zone / "max_energy_range_uj").unlink()
        p = self.run_meter()
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")

    def test_corrupt_counter_never_publishes(self):
        (self.zone / "energy_uj").write_text("not-a-number\n", encoding="ascii")
        p = self.run_meter(env_override={"FAKE_COUNTER": str(self.shadow)})
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")

    def test_undervoltage_domain_rejected(self):
        (self.zone / "name").write_text("core\n", encoding="ascii")
        p = self.run_meter()
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")

    def test_out_of_range_counter_rejected(self):
        (self.zone / "energy_uj").write_text("100\n", encoding="ascii")
        p = self.run_meter(env_override={"FAKE_COUNTER": str(self.shadow)})
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")

    def test_duplicate_label_rejected(self):
        p = self.run_meter("--program", f"SENS={self.bin}")
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")

    def test_bad_argv_rejected(self):
        p = self.run_meter(expected=256)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
