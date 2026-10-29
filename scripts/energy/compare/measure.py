#!/usr/bin/env python3
"""Порівняльний мікрозамір фізичної D3-рівності та нативних викликів."""
import argparse
import hashlib
import json
import os
import pwd
import random
import select
import signal
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts/energy'))
import measure as rapl  # noqa: E402


class NativeWorker:
    def __init__(self, binary, user, core):
        self.p = subprocess.Popen([str(binary)], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  user=user.pw_uid, group=user.pw_gid,
                                  extra_groups=[], start_new_session=True)
        try:
            os.sched_setaffinity(self.p.pid, {core})
            if self.line() != 'READY':
                raise ValueError(f'{binary.name}: missing READY')
        except Exception:
            try:
                self.close()
            except Exception:
                pass
            raise

    def line(self):
        deadline, data = time.monotonic() + 30, bytearray()
        while b'\n' not in data:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.p.stdout], [], [], remaining)[0]:
                raise TimeoutError('Native worker timed out')
            part = os.read(self.p.stdout.fileno(), 256)
            if not part:
                raise ValueError('Native worker exited early')
            data.extend(part)
            if len(data) > 128:
                raise ValueError('Unexpected worker output')
        if data.count(b'\n') != 1:
            raise ValueError('Unexpected protocol bytes')
        return data.decode('ascii').strip()

    def request(self, count):
        self.p.stdin.write(f'{count}\n'.encode())
        self.p.stdin.flush()
        response = self.line()
        try:
            rapl.verify_response(response, count, 161)
        except ValueError as error:
            raise ValueError(f'{self.p.args[0]} returned {response!r} for count={count}') from error

    def close(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        try:
            self.p.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(self.p.pid, signal.SIGKILL)
            self.p.wait()
        error = self.p.stderr.read().decode(errors='replace')
        self.p.stdout.close()
        self.p.stderr.close()
        if self.p.returncode or error:
            raise ValueError(f'Native worker failed: {error[:500]}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--rounds', type=int, default=30)
    ap.add_argument('--seconds', type=float, default=1.0)
    ap.add_argument('--core', type=int, default=2)
    ap.add_argument('--seed', type=int, default=346)
    args = ap.parse_args()
    if args.rounds < 30 or not .5 <= args.seconds <= 5 or args.output.exists():
        ap.error('Потрібно ≥30 повторів, 0.5..5 с і новий файл звіту')
    user = pwd.getpwnam(os.environ.get('SUDO_USER', pwd.getpwuid(os.getuid()).pw_name))
    if user.pw_uid == 0:
        ap.error('Запустіть через sudo від звичайного користувача')
    rustc_path = shutil.which('rustc', path=f'{Path(user.pw_dir)/".local/bin"}:{os.environ.get("PATH", "")}')
    if not rustc_path:
        raise ValueError('Не знайдено rustc у PATH користувача або ~/.local/bin')
    zones = rapl.discover_zones('/sys/devices/virtual/powercap/intel-rapl')
    binaries = {
        'sens-fpc-runtime': ROOT/'build/energy/bin/runtime',
        'c-gcc': ROOT/'build/energy/compare/equal-c',
        'rust': ROOT/'build/energy/compare/equal-rust',
        'free-pascal': ROOT/'build/energy/compare/equal-fpc',
    }
    workers = {}
    try:
        for name, binary in binaries.items():
            if name == 'sens-fpc-runtime':
                workers[name] = rapl.Worker(ROOT, 'eq', user, args.core)
            else:
                workers[name] = NativeWorker(binary, user, args.core)
            workers[name].request(1)
        counts = {}
        for name, worker in workers.items():
            count = 100
            for _ in range(12):
                start = time.monotonic()
                worker.request(count)
                elapsed = time.monotonic() - start
                if elapsed >= args.seconds * .8:
                    break
                count = min(1_000_000_000, max(count + 1,
                               int(count * min(20, args.seconds / elapsed))))
            if elapsed < args.seconds * .5:
                raise ValueError(f'{name}: cannot calibrate to comparable sample duration')
            counts[name] = count
            print(f'Калібрування {name}: {count} повторів, {elapsed:.3f} с', flush=True)

        rng = random.Random(args.seed)
        samples = []
        hz = os.sysconf('SC_CLK_TCK')
        started_utc = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        for block in range(args.rounds):
            order = list(workers) + ['idle']
            rng.shuffle(order)
            for name in order:
                busy0 = rapl.cpu_busy_ticks()
                ticks0 = {n: rapl.process_ticks(w.p.pid if hasattr(w, 'p') else w.process.pid)
                          for n, w in workers.items()}
                with rapl.Sampler(zones) as sampler:
                    if name == 'idle':
                        time.sleep(args.seconds)
                    else:
                        workers[name].request(counts[name])
                ticks1 = {n: rapl.process_ticks(w.p.pid if hasattr(w, 'p') else w.process.pid)
                          for n, w in workers.items()}
                elapsed = sampler.result()
                child = sum(ticks1[n] - ticks0[n] for n in workers)
                all_busy = rapl.cpu_busy_ticks() - busy0
                samples.append({
                    **elapsed, 'block': block, 'workload': name,
                    'iterations': counts.get(name, 0),
                    'worker_cpu_seconds': child / hz,
                    'background_cpu_seconds': max(0, all_busy - child) / hz,
                    'temperatures': rapl.temperatures(),
                })
            print(f'Блок {block+1}/{args.rounds}', flush=True)
    finally:
        close_errors = []
        for worker in workers.values():
            try:
                worker.close()
            except Exception as error:
                close_errors.append(str(error))
        if close_errors:
            raise ValueError('; '.join(close_errors))

    summary = {}
    for name in [*workers, 'idle']:
        rows = [s for s in samples if s['workload'] == name]
        value = {'samples': len(rows),
                 'median_seconds': statistics.median(s['seconds'] for s in rows),
                 'median_background_cpu_cores': statistics.median(
                     s['background_cpu_seconds'] / s['seconds'] for s in rows)}
        value['zones'] = {}
        for zone in zones:
            joules = [s['energy_uj'][zone.name] / 1e6 for s in rows]
            value['zones'][zone.name] = {
                'median_joules_per_sample': statistics.median(joules),
                'p10_joules': sorted(joules)[int(len(joules)*.1)],
                'p90_joules': sorted(joules)[min(len(joules)-1, int(len(joules)*.9))],
                'median_watts': statistics.median(
                    s['energy_uj'][zone.name] / 1e6 / s['seconds'] for s in rows),
            }
        if name != 'idle':
            throughput = statistics.median(s['iterations']/s['seconds'] for s in rows)
            value.update(iterations=counts[name], median_operations_per_second=throughput)
        summary[name] = value

    def command(*argv):
        options = {}
        env = dict(os.environ)
        if os.geteuid() == 0:
            options = {'user': user.pw_uid, 'group': user.pw_gid, 'extra_groups': []}
            env['HOME'] = user.pw_dir
        return subprocess.check_output(argv, cwd=ROOT, text=True, env=env, **options).strip()
    files = [*binaries.values(), ROOT/'scripts/energy/compare/equal.c',
             ROOT/'scripts/energy/compare/equal.rs', ROOT/'scripts/energy/compare/equal.pas',
            ROOT/'scripts/energy/compare/measure.py', ROOT/'scripts/energy/compare/build.sh',
            ROOT/'scripts/energy/runtime.lpr', ROOT/'build/energy/fixtures/eq.sens']
    report = {
        'schema': 'sens-energy-language-comparison/1',
        'scope': 'D3 identity vs compiled host primitive; shared desktop RAPL zones',
        'authority_sha': command('git', '-C', 'external/sens', 'rev-parse', 'HEAD'),
        'source_sha': command('git', 'rev-parse', 'HEAD'),
        'source_dirty': command('git', 'status', '--short'),
        'versions': {'gcc': command('gcc', '--version').splitlines()[0],
                     'fpc': command('/usr/bin/fpc', '-iV'),
                     'rustc': command(rustc_path, '--version')},
        'flags': {'gcc': '-std=c11 -O2', 'rustc': '--edition=2021 -C opt-level=2 -C codegen-units=1',
                  'fpc': '-B -O2 -Mobjfpc'},
        'cpu': Path('/proc/cpuinfo').read_text(), 'kernel': os.uname().release,
        'governor': Path('/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor').read_text().strip(),
        'turbo_disabled': Path('/sys/devices/system/cpu/intel_pstate/no_turbo').read_text().strip(),
        'affinity': [args.core], 'rounds': args.rounds, 'target_seconds': args.seconds,
        'seed': args.seed, 'started_utc': started_utc,
        'zones': [{'name': z.name, 'path': str(z.path), 'maximum_uj': z.maximum} for z in zones],
        'workloads': {
            'sens-fpc-runtime': 'TBinaryExecutor.ExecutePhysicalT5M over exact physical D3:101 equality; each call decodes T5M/D2, binds, evaluates, encodes and checks expected byte 0xA1.',
            'c-gcc/rust/free-pascal': 'compiled non-inlined equality call over generated equal operands; checks one match per iteration and reports checksum 161*N matching the physical SENS output byte count.',
            'driver': 'one persistent process each; host sends iteration count; process startup and compilation excluded; all other workers remain alive during each sample.',
        },
        'hashes': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
        'summary': summary, 'samples': samples,
        'limitations': ['The SENS side measures interpreter/runtime decode-bind-eval-encode, not a native SENS backend.',
                        'The three compiled languages measure a primitive equality call, not parsers or equivalent language runtimes.',
                        'SENS lacks a supported source-level loop in this execution path; host repetition drives repeated physical forms.',
                        'RAPL covers shared package/core/dram domains including desktop background and collector; no per-process attribution.',
                        'This is one D3 microbenchmark on one machine, not a general language ranking or energy-minimality claim.'],
    }
    # Paired correction reduces slow drift but still cannot isolate process energy.
    paired = {}
    for name in workers:
        deltas = []
        for block in range(args.rounds):
            active = next(s for s in samples if s['block'] == block and s['workload'] == name)
            idle = next(s for s in samples if s['block'] == block and s['workload'] == 'idle')
            deltas.append((active['energy_uj']['package-0'] - idle['energy_uj']['package-0']) / 1e6)
        paired[name] = {'median_excess_package_joules_vs_same_block_idle': statistics.median(deltas),
                        'p10_excess_joules': sorted(deltas)[int(len(deltas)*.1)],
                        'p90_excess_joules': sorted(deltas)[min(len(deltas)-1, int(len(deltas)*.9))]}
    report['paired_idle_differences'] = paired
    report['ended_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    rapl.publish_report(args.output, report, (user.pw_uid, user.pw_gid))
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

# Питання: чому всі worker-процеси залишаються живими? Що означають зони?
# Навіщо рандомізувати порядок блоків? Чому цей звіт не порівнює всі мови?
