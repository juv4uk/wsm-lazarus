#!/usr/bin/env python3
"""Чесний host-вимір Linux x86-64 ELF: фізичний stdout перед метриками.

Не інтерпретує SENS, не виводить мовних законів із назв, не є оракулом.
"""
import argparse
import hashlib
import json
import statistics
import struct
import subprocess
import sys
import time
from pathlib import Path


def pozitivne(text):
    value = int(text)
    if not 1 <= value <= 10000:
        raise argparse.ArgumentTypeError('потрібне ціле від 1 до 10000')
    return value


def dodatne(text):
    value = float(text)
    if not 0 < value <= 60:
        raise argparse.ArgumentTypeError('ліміт має бути >0 і <=60 секунд')
    return value


def perevir_elf(path):
    with path.open('rb') as stream:
        head = stream.read(64)
    if (len(head) < 64 or head[:6] != b'\x7fELF\x02\x01' or
            struct.unpack_from('<H', head, 16)[0] not in (2, 3) or
            struct.unpack_from('<H', head, 18)[0] != 62):
        raise ValueError('потрібен Linux x86-64 ELF64, не текст або інша архітектура')


def zapusk(machine, payload, expected, timeout):
    try:
        result = subprocess.run([str(machine)], input=payload, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=timeout, check=False)
    except subprocess.TimeoutExpired as exc:
        raise ValueError('native ELF перевищив ліміт часу') from exc
    if result.returncode != 0 or result.stderr or result.stdout != expected:
        raise ValueError('машинне виконання не збіглося з точним фізичним еталоном '
                         '(exit/stderr/stdout)')


def rapl_read(path, maximum):
    value = int(path.read_text(encoding='ascii').strip())
    if not 0 <= value < maximum:
        raise ValueError('RAPL-лічильник поза фізичною межею')
    return value


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--машина', required=True, type=Path)
    ap.add_argument('--очікуване', required=True, type=Path)
    ap.add_argument('--вхід', type=Path)
    ap.add_argument('--пакетів', type=pozitivne, default=3)
    ap.add_argument('--повторів', type=pozitivne, default=8)
    ap.add_argument('--прогрів', type=pozitivne, default=2)
    ap.add_argument('--ліміт-секунд', type=dodatne, default=5.0)
    ap.add_argument('--rapl-енергія', type=Path)
    ap.add_argument('--rapl-межа', type=Path)
    args = ap.parse_args()
    if (args.rapl_енергія is None) != (args.rapl_межа is None):
        raise ValueError('обидва RAPL шляхи потрібні разом')
    machine = args.машина.resolve(strict=True)
    expected = args.очікуване.read_bytes()
    payload = args.вхід.read_bytes() if args.вхід else b''
    if not expected:
        raise ValueError('фізичний еталон порожній')
    perevir_elf(machine)
    maximum = None
    if args.rapl_енергія is not None:
        maximum = int(args.rapl_межа.read_text(encoding='ascii').strip())
        if maximum <= 0:
            raise ValueError('RAPL-межа некоректна')
        rapl_read(args.rapl_енергія, maximum)  # відмовитися до першого запуску
    for _ in range(args.прогрів):
        zapusk(machine, payload, expected, args.ліміт_секунд)
    elapsed = []
    energy = []
    for _ in range(args.пакетів):
        first_energy = rapl_read(args.rapl_енергія, maximum) if maximum else None
        first = time.perf_counter_ns()
        for _ in range(args.повторів):
            zapusk(machine, payload, expected, args.ліміт_секунд)
        elapsed.append(time.perf_counter_ns() - first)
        if maximum:
            last_energy = rapl_read(args.rapl_енергія, maximum)
            energy.append(round(((last_energy - first_energy) % maximum) / 1e6, 9))
    report = {
        'формат': 'SENS-НАТИВНИЙ-ВИМІР-1',
        'машина-sha256': hashlib.sha256(machine.read_bytes()).hexdigest(),
        'еталон-sha256': hashlib.sha256(expected).hexdigest(),
        'вхід-sha256': hashlib.sha256(payload).hexdigest(),
        'пакетів': args.пакетів,
        'повторів-у-пакеті': args.повторів,
        'прогрівів': args.прогрів,
        'виконань-перевірено': args.прогрів + args.пакетів * args.повторів,
        'пакети-нс': elapsed,
        'медіана-нс-на-виклик': statistics.median(elapsed) / args.повторів,
        'енергія-статус': 'RAPL-СИСТЕМНИЙ-ПАКЕТ' if maximum else 'НЕ-ВИМІРЯНО',
        'енергія-джоулі-пакети': energy if maximum else None,
        'попередження': 'RAPL включає фонове навантаження ОС; це не енергія процесу.'
                        if maximum else 'Джоулі не виміряні: CI не має дозволеного RAPL.',
    }
    # Єдиний stdout лише після ВСІХ позитивів; відмова ніколи не видає звіт.
    sys.stdout.write(json.dumps(report, ensure_ascii=False, sort_keys=True) + '\n')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print('ВИМІР-ВІДМОВА:', exc, file=sys.stderr)
        sys.exit(2)
