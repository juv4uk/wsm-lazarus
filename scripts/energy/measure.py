#!/usr/bin/env python3
"""Дослідний зональний RAPL: root читає датчики, FPC працює як користувач.
Зони не додаються. Повний JSON публікується тільки після всіх перевірок.
"""
import argparse
import hashlib
import json
import os
import pwd
import random
import select
import signal
import statistics
import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path


def counter_delta(before, after, maximum):
    if maximum <= 0 or not (0 <= before < maximum and 0 <= after < maximum):
        raise ValueError('Некоректний лічильник RAPL')
    return (after-before) % maximum


def verify_response(text, count, byte_sum):
    if text.strip().split('\t') != ['OK', str(count), str(count*byte_sum)]:
        raise ValueError('Хибний результат або кількість фізичних виконань')


@dataclass
class Zone:
    path: Path
    name: str
    maximum: int

    def read(self):
        value = int(self.path.read_text())
        counter_delta(value, value, self.maximum)
        return value


def discover_zones(root):
    zones = []
    for path in sorted(Path(root).rglob('energy_uj')):
        z = Zone(path, (path.parent/'name').read_text().strip(),
                 int((path.parent/'max_energy_range_uj').read_text()))
        z.read()  # PermissionError не перетворюється на 0 J.
        zones.append(z)
    if not zones or not any(z.name.startswith('package-') for z in zones):
        raise ValueError('ENERGY_NOT_MEASURED: немає package зони RAPL')
    if len({z.name for z in zones}) != len(zones):
        raise ValueError('Неоднозначні назви зон; потрібен багатосокетний профіль')
    return zones


def publish_report(path, report, owner=None):
    """Лише повний JSON: fsync і атомарний hardlink без перезапису цілі."""
    data = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False)+'\n'
    path, temporary = Path(path), None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                         delete=False) as stream:
            temporary = stream.name
            stream.write(data)
            stream.flush()
            if owner is not None:
                os.fchown(stream.fileno(), *owner)
            os.fsync(stream.fileno())
        os.link(temporary, path)
    finally:
        if temporary is not None:
            os.unlink(temporary)


class Sampler:
    """50 ms опитування з повними сирими читаннями. Межа 1000 W для
    цього desktop стенда дозволяє відхилити неоднозначний пропуск обертів.
    Це межа протоколу, а не налаштування живлення. Потік закривається явно.
    """
    def __init__(self, zones):
        self.zones, self.readings, self.error = zones, [], None
        self.stop_event = threading.Event()

    def sample(self):
        self.readings.append({'monotonic_ns': time.monotonic_ns(),
                              'energy_uj': {z.name: z.read() for z in self.zones}})

    def loop(self):
        try:
            while not self.stop_event.wait(0.05):
                self.sample()
        except Exception as error:
            self.error = error

    def __enter__(self):
        self.sample()
        self.thread = threading.Thread(target=self.loop)
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.stop_event.set()
        self.thread.join()
        self.sample()

    def result(self):
        if self.error:
            raise self.error
        totals = {z.name: 0 for z in self.zones}
        for a, b in zip(self.readings, self.readings[1:]):
            elapsed = (b['monotonic_ns']-a['monotonic_ns'])/1e9
            for z in self.zones:
                if elapsed >= z.maximum/1e9:  # мкДж / (1000 W * 1e6)
                    raise ValueError('Пропуск допускає невідомі оберти RAPL')
                totals[z.name] += counter_delta(a['energy_uj'][z.name],
                                                b['energy_uj'][z.name], z.maximum)
        return {'energy_uj': totals, 'counter_readings': self.readings,
                'seconds': (self.readings[-1]['monotonic_ns']-
                            self.readings[0]['monotonic_ns'])/1e9}


def cpu_busy_ticks():
    v = list(map(int, Path('/proc/stat').read_text().splitlines()[0].split()[1:]))
    return sum(v[:8])-v[3]-v[4]  # без idle/iowait, без повторного guest


def process_ticks(pid):
    v = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    return int(v[11])+int(v[12])


def temperatures():
    return {str(p): p.read_text().strip()
            for p in Path('/sys/class/thermal').glob('thermal_zone*/temp')}


class Worker:
    def __init__(self, root, name, user, core):
        expected = root/'build/energy/fixtures'/(name+'.expected.sens')
        data = expected.read_bytes()
        if len(data) != 1:
            raise ValueError('Профіль вимагає однобайтову exact відповідь')
        self.byte_sum = sum(data)
        argv = [str(root/'build/energy/bin/runtime'), str(root/'external/sens'),
                str(root/'build/energy/fixtures'/(name+'.sens')), str(expected)]
        self.process = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, user=user.pw_uid,
                                        group=user.pw_gid, extra_groups=[], start_new_session=True)
        try:
            os.sched_setaffinity(self.process.pid, {core})
            if self.line() != 'READY':
                raise ValueError('Runtime не підтвердив exact відповідь')
        except Exception:
            self.close()
            raise

    def line(self):
        deadline, data = time.monotonic()+60, bytearray()
        while b'\n' not in data:
            remaining = deadline-time.monotonic()
            if remaining <= 0 or not select.select([self.process.stdout], [], [], remaining)[0]:
                raise TimeoutError('Runtime перевищив межу часу')
            part = os.read(self.process.stdout.fileno(), 256)
            if not part:
                raise ValueError('Runtime закрив неповну відповідь')
            data.extend(part)
            if len(data) > 1024:
                raise ValueError('Надмірна відповідь runtime')
        if data.count(b'\n') != 1 or not data.endswith(b'\n'):
            raise ValueError('Зайві байти протоколу runtime')
        return data.decode('ascii').strip()

    def request(self, count):
        if not 1 <= count <= 100000000:
            raise ValueError('Некоректна кількість повторів')
        self.process.stdin.write(f'{count}\n'.encode('ascii'))
        self.process.stdin.flush()
        verify_response(self.line(), count, self.byte_sum)

    def close(self):
        p = self.process
        try:
            p.stdin.close()
            p.wait(timeout=2)
        except (OSError, subprocess.TimeoutExpired):
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            p.wait()
        stderr = p.stderr.read().decode('utf-8', errors='replace')
        p.stdout.close()
        p.stderr.close()
        if p.returncode != 0 or stderr:
            raise ValueError('Помилка runtime: '+stderr[:1000])


def command(root, *argv):
    options = {}
    if os.geteuid() == 0:
        account = pwd.getpwnam(os.environ['SUDO_USER'])
        options = {'user': account.pw_uid, 'group': account.pw_gid, 'extra_groups': []}
    return subprocess.check_output(argv, cwd=root, text=True, **options).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=30)
    parser.add_argument('--seconds', type=float, default=1.0)
    parser.add_argument('--core', type=int, default=2)
    parser.add_argument('--seed', type=int, default=346)
    args = parser.parse_args()
    if args.rounds < 30 or not 0.5 <= args.seconds <= 5 or args.output.exists():
        parser.error('Потрібні ≥30 повторів, 0.5..5 секунд і новий вихідний файл')
    user = pwd.getpwnam(os.environ.get('SUDO_USER', pwd.getpwuid(os.getuid()).pw_name))
    if user.pw_uid == 0:
        parser.error('Виконуйте через sudo від звичайного користувача')
    root = args.root.resolve()
    zones = discover_zones('/sys/devices/virtual/powercap/intel-rapl')
    metadata = {
        'schema': 'sens-energy-baseline/1', 'scope': 'EXPLORATORY_SHARED_DESKTOP_ZONE_ENERGY',
        'measured_path': 'TBinaryExecutor.ExecutePhysicalT5M: decode+D2+bind+eval+encode',
        'excluded': ['process startup', 'authority load', 'file read', 'compilation', 'GUI'],
        'source_sha': command(root, 'git', 'rev-parse', 'HEAD'),
        'source_dirty': command(root, 'git', 'status', '--short'),
        'authority_sha': command(root, 'git', '-C', 'external/sens', 'rev-parse', 'HEAD'),
        'fpc': command(root, '/usr/bin/fpc', '-iV'), 'flags': '-B -O2 -Mobjfpc',
        'kernel': os.uname().release, 'cpuinfo': Path('/proc/cpuinfo').read_text(),
        'governor': Path('/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor').read_text().strip(),
        'no_turbo': Path('/sys/devices/system/cpu/intel_pstate/no_turbo').read_text().strip(),
        'user': user.pw_name, 'affinity': [args.core], 'rounds': args.rounds,
        'target_seconds': args.seconds, 'seed': args.seed,
        'zones': [{'name': z.name, 'path': str(z.path), 'maximum_uj': z.maximum} for z in zones],
        'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'load_before': Path('/proc/loadavg').read_text().strip(),
        'processes_before': command(root, 'ps', '-eo', 'pid,comm,pcpu', '--sort=-pcpu'),
        'hashes': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in [root/'build/energy/bin/runtime', root/'scripts/energy/runtime.lpr',
                             root/'scripts/energy/measure.py',
                             *sorted((root/'build/energy/fixtures').glob('*.sens'))]},
    }
    workers, counts, samples = {}, {}, []
    try:
        for name in ['eq', 'selector', 'cond32']:
            worker = workers[name] = Worker(root, name, user, args.core)
            worker.request(1)
            count = 10
            for _ in range(10):
                start = time.monotonic()
                worker.request(count)
                elapsed = time.monotonic()-start
                if elapsed >= args.seconds*0.8:
                    break
                count = min(100000000, max(count+1, int(count*min(10, args.seconds/elapsed))))
            counts[name] = count
            print(f'Калібрування {name}: {count} виконань за {elapsed:.3f} с', flush=True)
        metadata['iterations'] = counts
        rng, hz = random.Random(args.seed), os.sysconf('SC_CLK_TCK')
        for block in range(args.rounds):
            order = ['idle', *workers]
            rng.shuffle(order)
            for name in order:
                busy0 = cpu_busy_ticks()
                proc0 = {n: process_ticks(w.process.pid) for n, w in workers.items()}
                temp0 = temperatures()
                with Sampler(zones) as sampler:
                    if name == 'idle':
                        time.sleep(args.seconds)
                    else:
                        workers[name].request(counts[name])
                sample = sampler.result()
                child_ticks = sum(process_ticks(w.process.pid)-proc0[n] for n, w in workers.items())
                all_ticks = cpu_busy_ticks()-busy0
                sample.update(block=block, workload=name, iterations=counts.get(name, 0),
                              worker_cpu_seconds=child_ticks/hz,
                              background_cpu_seconds=max(0, all_ticks-child_ticks)/hz,
                              temperatures_before=temp0, temperatures_after=temperatures(),
                              rss_highwater_kib={n: next(line for line in
                                  Path(f'/proc/{w.process.pid}/status').read_text().splitlines()
                                  if line.startswith('VmHWM:')) for n, w in workers.items()})
                samples.append(sample)
            print(f'Завершено блок {block+1}/{args.rounds}', flush=True)
    finally:
        errors = []
        for worker in workers.values():
            try:
                worker.close()
            except Exception as error:
                errors.append(str(error))
        if errors:
            raise ValueError('; '.join(errors))
    summaries = {}
    for name in ['idle', *counts]:
        rows = [s for s in samples if s['workload'] == name]
        summaries[name] = {
            'samples': len(rows), 'median_seconds': statistics.median(s['seconds'] for s in rows),
            'median_background_cpu_cores': statistics.median(s['background_cpu_seconds']/s['seconds'] for s in rows),
            'zones': {z.name: {
                'median_joules': statistics.median(s['energy_uj'][z.name]/1e6 for s in rows),
                'median_watts': statistics.median(s['energy_uj'][z.name]/1e6/s['seconds'] for s in rows),
                'p10_joules': sorted(s['energy_uj'][z.name]/1e6 for s in rows)[int(len(rows)*0.1)],
                'p90_joules': sorted(s['energy_uj'][z.name]/1e6 for s in rows)[min(len(rows)-1,int(len(rows)*0.9))],
            } for z in zones},
        }
        if name != 'idle':
            summaries[name]['median_executions_per_second'] = statistics.median(s['iterations']/s['seconds'] for s in rows)
    metadata['ended_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    metadata['load_after'] = Path('/proc/loadavg').read_text().strip()
    publish_report(args.output, {'metadata': metadata, 'summary': summaries, 'samples': samples},
                   (user.pw_uid, user.pw_gid))
    print(json.dumps(summaries, ensure_ascii=False, indent=2), flush=True)


if __name__ == '__main__':
    main()

# Питання: 1) Чому package і core не додаються? 2) Чому без датчика немає
# 0 J? 3) Що змінює desktop фон? 4) Навіщо сирі читання? 5) Чому це не рейтинг мов?
