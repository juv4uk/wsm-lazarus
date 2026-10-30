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


def perevir_dzherelo_rapl(shliakh_energii, shliakh_mezhi):
    """Лише реальний sysfs powercap PACKAGE, не підставні файли або symlink.

    Це перевірка host-метрології, а не закон SENS. Обидва файли позичені
    за шляхом; повертаються розв'язані Path до фізичного kernel sysfs.
    """
    energy = shliakh_energii.resolve(strict=True)
    border = shliakh_mezhi.resolve(strict=True)
    if (energy.name != 'energy_uj' or
            border.name != 'max_energy_range_uj' or
            energy.parent != border.parent or
            Path('/sys') not in energy.parents):
        raise ValueError('RAPL-ВІДМОВА: потрібні спільні фізичні sysfs energy_uj '
                         'та max_energy_range_uj у /sys')
    # Піддомен core/uncore не можна непомітно оголошувати системним пакетом.
    # Назва каталогу драйвера та його вміст — тільки host походження.
    zone = energy.parent.name.split(':')
    if (len(zone) != 2 or zone[0] not in ('intel-rapl', 'amd-rapl') or
            not zone[1].isdigit()):
        raise ValueError('RAPL-ВІДМОВА: потрібна коренева package-зона powercap')
    name = (energy.parent / 'name').read_text(encoding='ascii').strip()
    if not name.startswith('package-') or not name[8:].isdigit():
        raise ValueError('RAPL-ВІДМОВА: лічильник не належить фізичному package')
    return energy, border


def rapl_read(path, maximum):
    value = int(path.read_text(encoding='ascii').strip())
    if not 0 <= value < maximum:
        raise ValueError('RAPL-лічильник поза фізичною межею')
    return value


def rapl_delta(before, after, maximum, elapsed_ns):
    """Пакетна різниця тільки для однозначного інтервалу лічильника.

    Before/after — kernel package energy_uj; maximum — max_energy_range_uj
    з ТІЄЇ САМОЇ pinned host-зони. Elapsed_ns обрамлює обидва sysfs read.
    Host-профіль допускає не більш як 1000 Вт споживання пакета:
    1000 Вт * elapsed_ns / 1000 = elapsed_ns мкДж, тому elapsed_ns < maximum
    консервативно виключає повний оберт за фізичної межі цього стенда.
    За більшої тривалості відмовляємося замість вигадування джоулів.
    Це НЕ SENS-закон, НЕ доказ енергії PID і НЕ фізичний вимір у CI.
    1) Чому modulo без часової межі маскує два оберти?
    2) Чому часові мітки ставляться навколо обох sysfs read?
    3) Чому верхня межа ват — host-умова, а не D12?
    4) Чому навіть при before=after не можна видавати 0 Дж за довгий пакет?
    """
    if (maximum <= 0 or elapsed_ns <= 0 or
            not 0 <= before < maximum or not 0 <= after < maximum):
        raise ValueError('RAPL-ВІДМОВА: нечинний лічильник або монотонний час')
    if elapsed_ns >= maximum:
        raise ValueError('RAPL-ВІДМОВА: інтервал може приховувати повний оберт; '
                         'зменште --повторів або --ліміт-секунд')
    return (after - before) % maximum


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
    energy_path = None
    if args.rapl_енергія is not None:
        energy_path, range_path = perevir_dzherelo_rapl(
            args.rapl_енергія, args.rapl_межа)
        maximum = int(range_path.read_text(encoding='ascii').strip())
        if maximum <= 0:
            raise ValueError('RAPL-межа некоректна')
        rapl_read(energy_path, maximum)  # відмовитися до першого запуску
    for _ in range(args.прогрів):
        zapusk(machine, payload, expected, args.ліміт_секунд)
    elapsed = []
    energy = []
    for _ in range(args.пакетів):
        # Дві окремі clock-пари: тривалість машинних запусків не включає
        # sysfs, а RAPL interval охоплює ВСЕ між фізичними читаннями.
        # Обидва timestamp — локальні int ns, жодного lifetime поза пакетом.
        rapl_start_ns = time.perf_counter_ns() if maximum else None
        first_energy = rapl_read(energy_path, maximum) if maximum else None
        first = time.perf_counter_ns()
        for _ in range(args.повторів):
            zapusk(machine, payload, expected, args.ліміт_секунд)
        elapsed.append(time.perf_counter_ns() - first)
        if maximum:
            last_energy = rapl_read(energy_path, maximum)
            rapl_end_ns = time.perf_counter_ns()
            delta_uj = rapl_delta(first_energy, last_energy, maximum,
                                  rapl_end_ns - rapl_start_ns)
            energy.append(round(delta_uj / 1e6, 9))
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
        'попередження': 'RAPL включає фонове навантаження ОС; це не енергія процесу. Інтервали обмежено умовою до 1000 Вт на пакет.'
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
