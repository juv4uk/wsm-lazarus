"""Механічні перевірки колектора; не семантичний оракул SENS."""
import json
import tempfile
import unittest
from unittest import mock
from pathlib import Path
import measure


class EnergyTests(unittest.TestCase):
    def test_forward_and_wrap(self):
        self.assertEqual(measure.counter_delta(10, 25, 100), 15)
        self.assertEqual(measure.counter_delta(95, 4, 100), 9)
        self.assertEqual(measure.counter_delta(7, 7, 100), 0)

    def test_invalid_counter_is_not_zero_energy(self):
        for values in [(-1, 1, 100), (1, 100, 100), (1, 2, 0)]:
            with self.assertRaises(ValueError):
                measure.counter_delta(*values)

    def test_exact_protocol(self):
        measure.verify_response('OK\t3\t21', 3, 7)
        for text in ['OK\t2\t21', 'OK\t3\t20', '', 'FAIL', 'OK\t3\t21\textra']:
            with self.assertRaises(ValueError):
                measure.verify_response(text, 3, 7)

    def test_missing_and_damaged_zones_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaises(ValueError):
                measure.discover_zones(root)
            zone = root / 'intel-rapl:0'
            zone.mkdir()
            (zone / 'name').write_text('package-0')
            (zone / 'max_energy_range_uj').write_text('100')
            (zone / 'energy_uj').write_text('broken')
            with self.assertRaises(ValueError):
                measure.discover_zones(root)
            (zone / 'energy_uj').write_text('2')
            zones = measure.discover_zones(root)
            self.assertEqual(len(zones), 1)
            self.assertEqual(zones[0].read(), 2)

    def test_atomic_report_never_overwrites(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'report.json'
            measure.publish_report(path, {'стан': 'виміряно'})
            original = path.read_bytes()
            self.assertEqual(json.loads(original), {'стан': 'виміряно'})
            with self.assertRaises(FileExistsError):
                measure.publish_report(path, {'стан': 'підміна'})
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(sorted(p.name for p in Path(tmp).iterdir()), ['report.json'])

    def test_nonfinite_report_is_not_published(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'report.json'
            with self.assertRaises(ValueError):
                measure.publish_report(path, {'energy': float('nan')})
            self.assertFalse(path.exists())
            self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_sampler_preserves_raw_reads_and_wrap(self):
        zone = measure.Zone(Path('/unused'), 'package-0', 1000000000)
        sampler = measure.Sampler([zone])
        sampler.readings = [
            {'monotonic_ns': 0, 'energy_uj': {'package-0': 999999990}},
            {'monotonic_ns': 1000000, 'energy_uj': {'package-0': 10}},
        ]
        result = sampler.result()
        self.assertEqual(result['energy_uj']['package-0'], 20)
        self.assertEqual(result['counter_readings'], sampler.readings)

    def test_ambiguous_sampling_gap_is_rejected(self):
        sampler = measure.Sampler([measure.Zone(Path('/unused'), 'package-0', 1000000000)])
        sampler.readings = [
            {'monotonic_ns': 0, 'energy_uj': {'package-0': 10}},
            {'monotonic_ns': 2000000000, 'energy_uj': {'package-0': 20}},
        ]
        with self.assertRaises(ValueError):
            sampler.result()

    def test_sensor_failure_is_not_ignored(self):
        sampler = measure.Sampler([])
        sampler.error = PermissionError('немає доступу')
        with self.assertRaises(PermissionError):
            sampler.result()

    def test_missing_permission_propagates(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'name').write_text('package-0')
            (root/'max_energy_range_uj').write_text('1000')
            (root/'energy_uj').write_text('10')
            with mock.patch.object(measure.Zone, 'read', side_effect=PermissionError):
                with self.assertRaises(PermissionError):
                    measure.discover_zones(root)


if __name__ == '__main__':
    unittest.main()
