#!/usr/bin/env python3
"""GЕ.7: 30×4×3 повні блоки та fail-closed RAPL без вигаданих джоулів."""
import copy
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent
CODE = ROOT / "audit-compiled-elf.py"
spec = importlib.util.spec_from_file_location("sens_rapl_audit", CODE)
auditmod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auditmod)
K = "intel-rapl:0"
CHILD = "intel-rapl:0/intel-rapl:0:0"

def sample_report():
    rows = []
    watts = 100
    for block in range(30):
        for name in auditmod.CASES:
            for mode in auditmod.CHANNELS:
                # Знімки лише СИНТЕТИЧНІ для тесту парсера! НЕ фізична енергія.
                raw = ("RAPL-DELTA1\telapsed_us=50000\tmax_watts=100\n"
                       "intel-rapl:0\tpackage-0\t10\t40\t1000000000\t30\n"
                       "intel-rapl:0/intel-rapl:0:0\tcore\t1\t11\t1000000000\t10\n")
                rows.append({"режим": mode, "форма": name,
                             "повторів": 0 if mode == "idle" else 50,
                             "elapsed_us": 50000, "zones_uj": {K: 30, CHILD: 10},
                             "сирий_рапл": raw, "блок": block})
    artifacts = []
    for i, name in enumerate(auditmod.CASES):
        artifacts.append({"форма": name,
                          "джерело_sha256": format(i+1, "064x"),
                          "результат_sha256": format(i+11, "064x"),
                          "elf_sha256": format(i+21, "064x"),
                          "elf_байтів": 193})
    return {
        "схема": auditmod.SCHEMA, "SENS_pin": auditmod.PIN,
        "контракт": "12.0", "дата_utc": "2026-10-29T18:00:00+00:00",
        "ос": "Linux контрольний тест", "машина": "тестовий CPU",
        "метод": ("RAPL hardware-zone energy, cold separate process, ELF vs FPC; "
                  "excluded FPC compilation; includes startup, decoding in FPC, "
                  "sensor overhead and desktop background; never subtract idle; "
                  "no per-process attribution and no cross-language ranking"),
        "блоки": 30, "виконань_у_блоці": 50, "макс_ват": watts,
        "артефакти": artifacts, "сирі_виміри": rows,
    }

class ReportTests(unittest.TestCase):
    def test_full_positive_matrix(self):
        result = auditmod.audit(sample_report())
        self.assertEqual(result["записів"], 360)
        self.assertEqual(result["блоків"], 30)
        self.assertEqual(result["зон"], 2)
        self.assertEqual(len(result["результати"]), 4)
        self.assertEqual(result["результати"]["тотожні-00"]["готовий_ELF"]
                         ["package_медіана_сирих_мкДж"][K], 30)
        self.assertNotIn("джоулі_процесу", result)

    def test_many_corruptions_fail_closed(self):
        cases = []
        def changed(label, fn):
            bad = sample_report()
            fn(bad)
            cases.append((label, bad))
        changed("schema",lambda x:x.update({"схема":"other"}))
        changed("pin",lambda x:x.update({"SENS_pin":"0"*40}))
        changed("contract",lambda x:x.update({"контракт":"11.8"}))
        changed("method",lambda x:x.update({"метод":"process joules"}))
        changed("empty os",lambda x:x.update({"ос":"  "}))
        changed("29 blocks",lambda x:x.update({"блоки":29}))
        changed("bool blocks",lambda x:x.update({"блоки":True}))
        changed("zero repetitions",lambda x:x.update({"виконань_у_блоці":0}))
        changed("bad max watts",lambda x:x.update({"макс_ват":0}))
        changed("3 files",lambda x:x["артефакти"].pop())
        changed("duplicate artifact",lambda x:x["артефакти"][0].update(
            {"форма":"тотожні-11"}))
        changed("short hash",lambda x:x["артефакти"][0].update(
            {"elf_sha256":"f"*63}))
        changed("not elf",lambda x:x["артефакти"][0].update(
            {"elf_байтів":True}))
        changed("missing row",lambda x:x["сирі_виміри"].pop())
        changed("duplicated row",lambda x:x["сирі_виміри"].__setitem__(
            1, copy.deepcopy(x["сирі_виміри"][0])))
        changed("bad block",lambda x:x["сирі_виміри"][0].update({"блок":30}))
        changed("bad mode",lambda x:x["сирі_виміри"][0].update({"режим":"unknown"}))
        changed("bad form",lambda x:x["сирі_виміри"][0].update({"форма":"чужа"}))
        changed("short work",lambda x:x["сирі_виміри"][0].update({"повторів":49}))
        changed("idle work",lambda x:x["сирі_виміри"][2].update({"повторів":1}))
        changed("negative time",lambda x:x["сирі_виміри"][0].update({"elapsed_us":-1}))
        changed("time mismatch",lambda x:x["сирі_виміри"][0].update({"elapsed_us":40000}))
        changed("bad zone dictionary",lambda x:x["сирі_виміри"][0]["zones_uj"].update({K:31}))
        changed("bool energy",lambda x:x["сирі_виміри"][0]["zones_uj"].update({K:True}))
        changed("duplicate zones",lambda x:x["сирі_виміри"][0].update(
            {"сирий_рапл":x["сирі_виміри"][0]["сирий_рапл"]+
             "intel-rapl:0\tpackage-0\t10\t40\t1000000000\t30\n"}))
        changed("invalid zone",lambda x:x["сирі_виміри"][0].update(
            {"сирий_рапл":x["сирі_виміри"][0]["сирий_рапл"].replace(
                "intel-rapl:0\tpackage", "xintel-rapl:0\tpackage")}))
        changed("fake delta",lambda x:x["сирі_виміри"][0].update(
            {"сирий_рапл":x["сирі_виміри"][0]["сирий_рапл"].replace(
                "\t1000000000\t30", "\t1000000000\t31")}))
        changed("child disappears",lambda x:x["сирі_виміри"][0].update(
            {"сирий_рапл":x["сирі_виміри"][0]["сирий_рапл"].splitlines(True)[0]+
             x["сирі_виміри"][0]["сирий_рапл"].splitlines(True)[1]}))
        changed("no package",lambda x:x["сирі_виміри"][0].update(
            {"сирий_рапл":x["сирі_виміри"][0]["сирий_рапл"].replace(
                "\tpackage-0\t", "\tcore\t")}))
        changed("max range drift",lambda x:x["сирі_виміри"][0].update(
            {"сирий_рапл":x["сирі_виміри"][0]["сирий_рапл"].replace(
                "1000000000\t30", "500000000\t30")}))
        changed("bad range",lambda x:x["сирі_виміри"][0].update(
            {"сирий_рапл":x["сирі_виміри"][0]["сирий_рапл"].replace(
                "\t10\t40\t1000000000", "\t10\t1000000000\t1000000000")}))
        changed("noncanonical zeros",lambda x:x["сирі_виміри"][0].update(
            {"сирий_рапл":x["сирі_виміри"][0]["сирий_рапл"].replace(
                "\t10\t40\t", "\t010\t40\t")}))
        changed("missing LF",lambda x:x["сирі_виміри"][0].update(
            {"сирий_рапл":x["сирі_виміри"][0]["сирий_рапл"].rstrip("\n")}))
        changed("second wrap possible",lambda x:x["сирі_виміри"][0].update(
            {"elapsed_us":20000000,
             "сирий_рапл":x["сирі_виміри"][0]["сирий_рапл"].replace(
                 "elapsed_us=50000", "elapsed_us=20000000")}))
        changed("extra field",lambda x:x["сирі_виміри"][0].update({"джоулі_процесу":0}))
        self.assertGreaterEqual(len(cases), 30)
        for label, bad in cases:
            with self.subTest(label=label), self.assertRaises(ValueError):
                auditmod.audit(bad)

    def test_parse_wrap_and_one_range_only(self):
        raw = ("RAPL-DELTA1\telapsed_us=50000\tmax_watts=100\n"
               "intel-rapl:0\tpackage-0\t999999990\t20\t1000000000\t30\n")
        values, _ = auditmod.parse_rapl(raw, 50000, 100)
        self.assertEqual(values, {K: 30})
        with self.assertRaises(ValueError):
            auditmod.parse_rapl(raw, 10000000, 100)

    def test_atomic_publishing_and_json_trust_boundary(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            source, dest = root/"дані.json", root/"перевірений.json"
            source.write_text(json.dumps(sample_report(), ensure_ascii=False)+"\n", encoding="utf-8")
            run = subprocess.run([sys.executable, str(CODE), "--звіт", str(source),
                                  "--вихід", str(dest)], capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(json.loads(dest.read_text())["записів"], 360)
            original = dest.read_bytes()
            again = subprocess.run([sys.executable, str(CODE), "--звіт", str(source),
                                    "--вихід", str(dest)], capture_output=True)
            self.assertEqual(again.returncode, 2)
            self.assertEqual(dest.read_bytes(), original)
            self.assertFalse(any(p.name.startswith(".rapl-audit-") for p in root.iterdir()))
            for bad in (
                '{"схема":"x","схема":"y"}\n',
                '{"схема":NaN}\n', "{broken}\n", "",
                '{"схема":"x"}', '{"схема":"x"} trailing\n'
            ):
                source.write_text(bad, encoding="utf-8")
                missing = root/"немає.json"
                run = subprocess.run([sys.executable, str(CODE), "--звіт", str(source),
                                      "--вихід", str(missing)], capture_output=True)
                self.assertEqual(run.returncode, 2, bad)
                self.assertFalse(missing.exists())
                self.assertEqual(run.stdout, b"")

if __name__ == "__main__":
    unittest.main(verbosity=2)
