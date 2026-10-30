"""Механічні перевірки колектора; не семантичний оракул SENS."""
import json
import os
import tempfile
import unittest
from types import SimpleNamespace
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

    def test_host_response_is_exact_not_normalized(self):
        # Нечітке підтвердження виконання не може зараховуватися в джоулі.
        measure.verify_response('OK\t3\t21', 3, 7)
        for malformed in (
            ' OK\t3\t21', 'OK\t3\t21 ', 'OK\t3\t21\r',
            'OK\t3\t21\n', 'OK\t3\t21\x00',
            'OK\t3\t21\t', 'OK\t03\t21', 'OK 3 21',
            'OK\t3\t21\nOK\t3\t21', 'OK\t3\t21\u00a0',
        ):
            with self.subTest(malformed=repr(malformed)):
                with self.assertRaises(ValueError):
                    measure.verify_response(malformed, 3, 7)

    def test_worker_line_preserves_exact_bytes_before_lf(self):
        # Фізичний pipe-свідок зберігає пробіли та CR для верхнього guard.
        for payload, expected in (
            (b'READY\n', 'READY'),
            (b'READY \n', 'READY '),
            (b'READY\r\n', 'READY\r'),
            (b'OK\t3\t21 \n', 'OK\t3\t21 '),
        ):
            read_fd, write_fd = os.pipe()
            try:
                os.write(write_fd, payload)
                with os.fdopen(read_fd, 'rb', buffering=0) as stream:
                    worker = object.__new__(measure.Worker)
                    worker.process = SimpleNamespace(stdout=stream)
                    self.assertEqual(worker.line(), expected)
            finally:
                os.close(write_fd)

    def test_worker_line_rejects_extra_or_non_ascii(self):
        for payload in (b'READY\nnoise\n', b'READY\xff\n', b'READY'):
            read_fd, write_fd = os.pipe()
            os.write(write_fd, payload)
            os.close(write_fd)
            with os.fdopen(read_fd, 'rb', buffering=0) as stream:
                worker = object.__new__(measure.Worker)
                worker.process = SimpleNamespace(stdout=stream)
                with self.assertRaises((ValueError, UnicodeError)):
                    worker.line()

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

    def test_zero_or_one_reading_never_measures_zero_joules(self):
        zone = measure.Zone(Path('/unused'), 'package-0', 1000000000)
        for readings in ([], [{'monotonic_ns': 10,
                                'energy_uj': {'package-0': 123}}]):
            sampler = measure.Sampler([zone])
            sampler.readings = readings
            with self.assertRaisesRegex(ValueError, 'ENERGY_NOT_MEASURED'):
                sampler.result()

    def test_empty_sensor_set_is_not_a_valid_energy_measurement(self):
        sampler = measure.Sampler([])
        sampler.readings = [
            {'monotonic_ns': 10, 'energy_uj': {}},
            {'monotonic_ns': 20, 'energy_uj': {}},
        ]
        with self.assertRaisesRegex(ValueError, 'ENERGY_NOT_MEASURED'):
            sampler.result()

    def test_nonmonotonic_clock_never_publishes_energy(self):
        zone = measure.Zone(Path('/unused'), 'package-0', 1000000000)
        for later in (10, 9):
            sampler = measure.Sampler([zone])
            sampler.readings = [
                {'monotonic_ns': 10, 'energy_uj': {'package-0': 4}},
                {'monotonic_ns': later, 'energy_uj': {'package-0': 5}},
            ]
            with self.assertRaisesRegex(ValueError, 'ENERGY_NOT_MEASURED'):
                sampler.result()

    def test_exact_wrap_limit_rejects_but_one_nanosecond_below_passes(self):
        zone = measure.Zone(Path('/unused'), 'package-0', 1000000000)
        sampler = measure.Sampler([zone])
        sampler.readings = [
            {'monotonic_ns': 0, 'energy_uj': {'package-0': 999999999}},
            {'monotonic_ns': 999999999, 'energy_uj': {'package-0': 3}},
        ]
        result = sampler.result()
        self.assertEqual(result['energy_uj'], {'package-0': 4})
        self.assertEqual(result['seconds'], 0.999999999)
        sampler.readings[1]['monotonic_ns'] = 1000000000
        with self.assertRaisesRegex(ValueError, 'оберти'):
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
