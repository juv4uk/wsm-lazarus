#!/usr/bin/env python3
"""Repeated cold-process D24 sum benchmark with raw Intel RAPL readings."""
import argparse
import hashlib
import json
import os
import pwd
import random
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / 'build/energy/native-d12-loop'
N = 8_388_361
EXPECTED = 173
sys.path.insert(0, str(ROOT / 'scripts/energy'))
import measure as rapl  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='новий шлях JSON звіту')
    parser.add_argument('--check-only', action='store_true',
                        help='перевірити збірки й вихід без датчиків')
    parser.add_argument('--rounds', type=int, default=30)
    parser.add_argument('--repetitions', type=int, default=50)
    parser.add_argument('--core', type=int, default=2)
    parser.add_argument('--seed', type=int, default=2904)
    args = parser.parse_args()

    user_name = os.environ.get('SUDO_USER') if os.geteuid() == 0 else pwd.getpwuid(os.getuid()).pw_name
    if not user_name or user_name == 'root':
        parser.error('запустіть звичайним користувачем або через sudo із SUDO_USER')
    user = pwd.getpwnam(user_name)
    binaries = {
        'sens-native-elf': [str(BIN / 'sens-native.elf')],
        'c-gcc-o2': [str(BIN / 'sum-c'), str(N)],
        'rust-opt2': [str(BIN / 'sum-rust'), str(N)],
        'fpc-o2': [str(BIN / 'sum-fpc'), str(N)],
        'cpp-clang18-o2': [str(BIN / 'sum-cpp'), str(N)],
        'zig-017-releasefast': [str(BIN / 'sum-zig'), str(N)],
        'fortran-gfortran13-o2': [str(BIN / 'sum-fortran'), str(N)],
        'swift-641-o': [str(BIN / 'sum-swift'), str(N)],
    }

    def run_one(command, expected=EXPECTED):
        def pin_core():
            os.sched_setaffinity(0, {args.core})
        options = {}
        if os.geteuid() == 0:
            options = {'user': user.pw_uid, 'group': user.pw_gid, 'extra_groups': []}
        result = subprocess.run(command, capture_output=True, timeout=15,
                                preexec_fn=pin_core, **options)
        if result.returncode != expected:
            raise RuntimeError(f'{command[0]}: очікувався код {expected}, отримано '
                               f'{result.returncode}; stderr={result.stderr!r}')

    if any(not Path(command[0]).is_file() for command in binaries.values()):
        parser.error('немає зібраних ELF; спочатку запустіть build.sh')
    for command in binaries.values():
        run_one(command)
    for _ in range(3):
        run_one(['/usr/bin/true'], 0)
    if args.check_only:
        print(f'D12-ЦИКЛ-ПЕРЕВІРКА-ГАРАЗД: {len(binaries)} ELF, спільний код завершення 173')
        return
    if args.output is None:
        parser.error('потрібен --output для нового JSON звіту')
    if args.rounds < 30 or args.repetitions < 1:
        parser.error('потрібно щонайменше 30 блоків і одне повторення')
    output = args.output.resolve()
    samples_path = output.with_name(output.stem + '.samples.jsonl')
    if output.exists() or samples_path.exists():
        parser.error('цільовий звіт або сирі вибірки вже існують')
    output.parent.mkdir(parents=True, exist_ok=True)

    zones = rapl.discover_zones('/sys/devices/virtual/powercap/intel-rapl')
    rng = random.Random(args.seed)
    samples = []
    start_utc = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    for block in range(args.rounds):
        order = list(binaries) + ['idle']
        rng.shuffle(order)
        for name in order:
            with rapl.Sampler(zones) as sampler:
                started = time.monotonic_ns()
                command = ['/usr/bin/true'] if name == 'idle' else binaries[name]
                expected = 0 if name == 'idle' else EXPECTED
                for _ in range(args.repetitions):
                    run_one(command, expected)
                host_seconds = (time.monotonic_ns() - started) / 1e9
            reading = sampler.result()
            sample = {
                'block': block, 'workload': name,
                'repetitions': args.repetitions,
                'iterations_per_program': 0 if name == 'idle' else N,
                'host_wall_seconds': host_seconds,
                'sampled_seconds': reading['seconds'],
                'energy_uj': reading['energy_uj'],
                'counter_readings': reading['counter_readings'],
                'temperatures': rapl.temperatures(),
            }
            samples.append(sample)
            with samples_path.open('a', encoding='utf-8') as stream:
                stream.write(json.dumps(sample, ensure_ascii=False) + '\n')
                stream.flush()
                os.fsync(stream.fileno())
        print(f'Блок {block + 1}/{args.rounds}', flush=True)

    summary = {}
    names = [*binaries, 'idle']
    for name in names:
        rows = [s for s in samples if s['workload'] == name]
        seconds = [s['host_wall_seconds'] for s in rows]
        summary[name] = {
            'samples': len(rows),
            'median_batch_seconds': statistics.median(seconds),
            'p10_batch_seconds': sorted(seconds)[int(.1 * len(seconds))],
            'p90_batch_seconds': sorted(seconds)[int(.9 * len(seconds))],
            'median_process_launches_per_second': args.repetitions / statistics.median(seconds),
            'zones': {},
        }
        if name != 'idle':
            summary[name]['median_nominal_iteration_equivalents_per_second'] = (
                args.repetitions * N / statistics.median(seconds))
        for zone in zones:
            joules = [s['energy_uj'][zone.name] / 1e6 for s in rows]
            summary[name]['zones'][zone.name] = {
                'median_joules_per_batch': statistics.median(joules),
                'p10_joules': sorted(joules)[int(.1 * len(joules))],
                'p90_joules': sorted(joules)[min(len(joules) - 1, int(.9 * len(joules)))],
            }

    paired = {}
    for name in binaries:
        differences = []
        for block in range(args.rounds):
            active = next(s for s in samples if s['block'] == block and s['workload'] == name)
            idle = next(s for s in samples if s['block'] == block and s['workload'] == 'idle')
            baseline = idle['energy_uj']['package-0'] * active['sampled_seconds'] / idle['sampled_seconds']
            differences.append((active['energy_uj']['package-0'] - baseline) / 1e6)
        differences.sort()
        paired[name] = {
            'median_scaled_idle_difference_joules': statistics.median(differences),
            'p10_joules': differences[int(.1 * len(differences))],
            'p90_joules': differences[min(len(differences) - 1, int(.9 * len(differences)))],
            'interpretation': 'діагностика; не є приписаною процесу енергією',
        }

    source_files = [
        BIN / 'sens-native.elf', BIN / 'sum-c', BIN / 'sum-rust', BIN / 'sum-fpc',
        BIN / 'sum-cpp', BIN / 'sum-zig', BIN / 'sum-fortran', BIN / 'sum-swift',
        ROOT / 'evidence/energy-native-d12-loop-20261029/build-sens-loop.pas',
        ROOT / 'evidence/energy-native-d12-loop-20261029/sum.c',
        ROOT / 'evidence/energy-native-d12-loop-20261029/sum.rs',
        ROOT / 'evidence/energy-native-d12-loop-20261029/sum.pas',
        ROOT / 'evidence/energy-native-d12-loop-20261029/sum.cpp',
        ROOT / 'evidence/energy-native-d12-loop-20261029/sum.zig',
        ROOT / 'evidence/energy-native-d12-loop-20261029/sum.f90',
        ROOT / 'evidence/energy-native-d12-loop-20261029/sum.swift',
        ROOT / 'evidence/energy-native-d12-loop-20261029/toolchains.json',
        ROOT / 'evidence/energy-native-d12-loop-20261029/build.sh', Path(__file__).resolve(),
        BIN / 'sens-native.sens',
    ]
    toolchain_path = os.pathsep.join([
        str(Path(user.pw_dir) / '.local/bin'),
        str(Path(user.pw_dir) / '.local/toolchains/swift-6.4.1/usr/bin'),
        str(Path(user.pw_dir) / '.cargo/bin'),
        os.environ.get('PATH', ''),
    ])
    def locate(variable, default):
        executable = shutil.which(os.environ.get(variable, default), path=toolchain_path)
        if not executable:
            parser.error(f'{default} не знайдено; додайте його до PATH або встановіть toolchain')
        return executable

    rustc = locate('RUSTC', 'rustc')
    cxx = locate('CXX', 'clang++-18')
    zig = locate('ZIG', 'zig')
    fortran = locate('FC', 'gfortran-13')
    swiftc = locate('SWIFTC', 'swiftc')
    report = {
        'schema': 'sens-native-d12-loop-benchmark/2',
        'scope': 'вузький ELF workload; не загальномовний рейтинг',
        'N': N, 'expected_exit_code': EXPECTED,
        'repetitions_per_sample': args.repetitions,
        'randomized_blocks': args.rounds, 'seed': args.seed,
        'cpu_core_affinity': args.core,
        'authority_sha': '1f1bf676eeac605e065035d9dd2adaae807f1788',
        'source_sha': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
        'source_dirty': subprocess.check_output(['git', '-C', str(ROOT), 'status', '--short'], text=True).strip(),
        'cpu_model': next((line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines()
                           if line.startswith('model name')), ''),
        'governor': Path('/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor').read_text().strip(),
        'turbo_disabled': Path('/sys/devices/system/cpu/intel_pstate/no_turbo').read_text().strip(),
        'versions': {
            'gcc': subprocess.check_output(['gcc', '--version'], text=True).splitlines()[0],
            'rustc': subprocess.check_output([rustc, '--version'], text=True).strip(),
            'fpc': subprocess.check_output(['/usr/bin/fpc', '-iV'], text=True).strip(),
            'clang++': subprocess.check_output([cxx, '--version'], text=True).splitlines()[0],
            'zig': subprocess.check_output([zig, 'version'], text=True).strip(),
            'gfortran': subprocess.check_output([fortran, '--version'], text=True).splitlines()[0],
            'swift': subprocess.check_output([swiftc, '--version'], text=True).splitlines()[0],
        },
        'flags': {
            'gcc': '-std=c11 -O2 -Wall -Wextra -Werror',
            'rustc': '--edition=2021 -C opt-level=2 -C codegen-units=1',
            'fpc': '-B -O2 -Mobjfpc',
            'clang++': '-std=c++20 -O2 -Wall -Wextra -Werror',
            'zig': 'build-exe -O ReleaseFast',
            'gfortran': '-std=f2018 -O2 -Wall -Wextra -Werror',
            'swift': '-O -whole-module-optimization -warnings-as-errors',
        },
        'zones': [{'name': z.name, 'path': str(z.path), 'maximum_uj': z.maximum} for z in zones],
        'workload': 'sum=0; for i=N downto 1: sum=(sum+i) modulo 2^32; exit(sum modulo 256)',
        'idle_control': 'same block, same number of /usr/bin/true launches; contextual only',
        'hashes': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in source_files},
        'sample_count': len(samples),
        'sample_log_sha256': hashlib.sha256(samples_path.read_bytes()).hexdigest(),
        'summary': summary,
        'paired_idle_diagnostics': paired,
        'started_utc': start_utc,
        'ended_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'limitations': [
            'SENS ELF — вузький BuildD12SumLoopELF backend, не загальний source-to-native compiler.',
            'Assembly для цього зразка показує, що GCC C і Clang C++ замінили цикл формулою; Fortran зберіг цикл.',
            'Швидкість ітерацій нормована на логічний обсяг вихідної програми; компілятор міг спростити або прибрати цикл.',
            'Час включає старт процесу, ELF loader і розбір аргументу у host-програмах; warm worker для SENS ELF відсутній.',
            'RAPL охоплює спільні апаратні зони і фон; жодне значення не приписується процесу.',
            'Один комп’ютер, одне навантаження й один N; загальномовних висновків немає.',
        ],
    }
    rapl.publish_report(output, report, (user.pw_uid, user.pw_gid))
    os.chown(samples_path, user.pw_uid, user.pw_gid)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f'ЗВІТ={output}')
    print(f'СИРІ_ВИБІРКИ={samples_path}')


if __name__ == '__main__':
    main()
