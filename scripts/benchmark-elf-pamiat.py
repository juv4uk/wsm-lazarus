#!/usr/bin/env python3
"""Пікова RSS окремих справжніх AOT/ELF процесів; жодного висновку про енергію."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import struct
import subprocess
import sys
import tempfile
import time

PIN = '1f1bf676eeac605e065035d9dd2adaae807f1788'
CASES = (('цитата', 'p01'), ('цитата', 'p02'),
         ('тотожність', 'p05'), ('тотожність', 'p06'))


def demand(condition, reason):
    if not condition:
        raise ValueError(reason)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def measured(argv, *, cwd, expected=None, timeout=20):
    """wait4 дає RUSAGE саме цього нащадка, не максимум усіх попередніх."""
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        started = time.perf_counter_ns()
        process = subprocess.Popen(argv, cwd=cwd, stdout=out, stderr=err)
        limit = time.monotonic() + timeout
        while True:
            pid, status, usage = os.wait4(process.pid, os.WNOHANG)
            if pid:
                break
            if time.monotonic() >= limit:
                process.kill()
                os.wait4(process.pid, 0)
                process.returncode = -9
                raise ValueError('Перевищено час очікування: ' + repr(argv))
            time.sleep(0.002)
        process.returncode = os.waitstatus_to_exitcode(status)
        elapsed = time.perf_counter_ns() - started
        out.seek(0)
        err.seek(0)
        actual, diagnostic = out.read(), err.read()
    demand(process.returncode == 0, 'Невдалий процес: ' + repr(argv) + ' ' + repr(diagnostic[:250]))
    demand(not diagnostic or b'0 unfreed memory blocks' in diagnostic,
           'Неочікувана діагностика: ' + repr(diagnostic[:250]))
    if expected is not None:
        demand(actual == expected, 'Порушено точну двійкову відповідь: ' + repr(argv))
    demand(usage.ru_maxrss > 0, 'Ядро не надало RSS')
    return {'rss_кіб': usage.ru_maxrss, 'час_нс': elapsed,
            'код': process.returncode, 'stdout_байтів': len(actual)}


def elf64_pie(path):
    payload = path.read_bytes()[:64]
    demand(len(payload) == 64 and payload[:6] == b'\x7fELF\x02\x01',
           'Результат не ELF64 little endian')
    demand(struct.unpack_from('<H', payload, 16)[0] == 3 and
           struct.unpack_from('<H', payload, 18)[0] == 62,
           'Результат не x86-64 ELF64 PIE (ET_DYN)')
    demand(os.access(path, os.X_OK), 'ELF не має права виконання')


def selftest():
    with tempfile.TemporaryDirectory() as directory:
        cwd = Path(directory)
        command = [sys.executable, '-c', 'import sys;sys.stdout.buffer.write(bytes([0,255,1]))']
        ok = measured(command, cwd=cwd, expected=b'\x00\xff\x01')
        demand(ok['rss_кіб'] > 0 and ok['stdout_байтів'] == 3, 'Позитивний пробій')
        rejected = 0
        for expected in (b'\x00\xff', b'\x00\xff\x02', b''):
            try:
                measured(command, cwd=cwd, expected=expected)
            except ValueError:
                rejected += 1
        try:
            measured([sys.executable, '-c', 'import time;time.sleep(1)'],
                     cwd=cwd, timeout=0.02)
        except ValueError:
            rejected += 1
        bogus = cwd / 'not-elf.elf'
        bogus.write_bytes(b'\x7fELF')
        try:
            elf64_pie(bogus)
        except ValueError:
            rejected += 1
        demand(rejected == 5, 'Негативи виміру або ELF допуску не спрацювали')
    return rejected


def main():
    parser = argparse.ArgumentParser(description='Вимір пікової RSS фізичного SENS AOT та ELF64')
    parser.add_argument('--самотест', action='store_true')
    parser.add_argument('--корінь', type=Path)
    parser.add_argument('--свідки', type=Path)
    parser.add_argument('--машина', type=Path)
    parser.add_argument('--вихід', type=Path)
    parser.add_argument('--повтори', type=int, default=3)
    args = parser.parse_args()
    demand(sys.platform == 'linux' and platform.machine() == 'x86_64',
           'Потрібні Linux x86-64 та wait4')
    neg = selftest()
    if args.самотест:
        print('ЕЛФ-ПАМ’ЯТЬ-САМОТЕСТ-ГАРАЗД негативи=' + str(neg))
        return
    demand(all((args.корінь, args.свідки, args.машина, args.вихід)),
           'Потрібні корінь, свідки, машина і вихід')
    demand(3 <= args.повтори <= 10, 'Кількість повторів поза [3,10]')
    root, fixtures, machine, destination = (args.корінь.resolve(),
        args.свідки.resolve(), args.машина.resolve(), args.вихід.resolve())
    demand((root / 'external/sens/contracts/language-contract-12.lisp').is_file(),
           'Немає pinned Contract 12.0')
    pin = subprocess.check_output(['git', '-C', str(root / 'external/sens'),
                                   'rev-parse', 'HEAD'], timeout=10).decode().strip()
    demand(pin == PIN, 'Дрейф pinned SENS')
    demand(machine.is_file() and os.access(machine, os.X_OK), 'Немає справжнього FPC CLI')
    demand(not destination.exists(), 'Заборонено перезапис існуючого звіту')
    report = {'схема': 'sens-elf-rss/1', 'pinned_SENS_SHA': PIN,
              'платформа': platform.platform(), 'енергія': 'ENERGY_NOT_MEASURED',
              'метод': 'Linux os.wait4: ru_maxrss (КіБ) окремого процесу; прогрів виключено',
              'повторів': args.повтори, 'негативів': neg, 'виміри': [], 'підсумки': {}}
    with tempfile.TemporaryDirectory(prefix='sens-rss-') as folder:
        temporary = Path(folder)
        for mode, label in CASES:
            source = fixtures / (label + '.sens')
            expected_file = fixtures / (label + '.expected.sens')
            demand(source.is_file() and expected_file.is_file(), 'Немає pinned фізичних свідків')
            initial = sha256(source)
            expected = expected_file.read_bytes()
            hashes = set()
            for i in range(args.повтори + 1):
                executable = temporary / (label + '-' + str(i) + '.elf')
                compile_result = measured([str(machine), '--' + mode,
                    str(root / 'external/sens'), str(source), str(executable)], cwd=root)
                demand(executable.is_file(), 'Компілятор не створив ELF')
                elf64_pie(executable)
                hashes.add(sha256(executable))
                executed = measured([str(executable)], cwd=root, expected=expected)
                if i:
                    report['виміри'].append({'форма': label, 'канал': 'компіляція_FPC_AOT',
                                               'повтор': i, **compile_result})
                    report['виміри'].append({'форма': label, 'канал': 'готовий_ELF64',
                                               'повтор': i, **executed})
            demand(len(hashes) == 1, 'ELF не побайтово відтворюваний: ' + label)
            demand(sha256(source) == initial, 'Компілятор змінив вхід: ' + label)
            for channel in ('компіляція_FPC_AOT', 'готовий_ELF64'):
                values = [x['rss_кіб'] for x in report['виміри']
                          if x['форма'] == label and x['канал'] == channel]
                report['підсумки'][label + '/' + channel] = {
                    'медіана_rss_кіб': statistics.median(values),
                    'мін_rss_кіб': min(values), 'макс_rss_кіб': max(values)}
    destination.mkdir(parents=True)
    (destination / 'виміри.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('ЕЛФ-ПАМ’ЯТЬ-ГАРАЗД форми=4 канали=2 повторів=' +
          str(args.повтори) + ' негативи=' + str(neg) + ' енергія=НЕ_ВИМІРЯНА')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print('ЕЛФ-ПАМ’ЯТЬ-ПОМИЛКА: ' + str(error), file=sys.stderr)
        sys.exit(2)
