#!/usr/bin/env python3
"""Незалежні фізичні D12+ свідки: Python big-int vs реальні FPC CLI.

Лише тестова модель двійкового доповняльного коду та T5M, не SENS evaluator.
"""
from __future__ import annotations

import random
import subprocess
import sys
import tempfile
from pathlib import Path

DOMAINS = (12, 24, 48, 96, 192)
SEED = 0xD1202026


def pack_word(bits: str) -> bytes:
    """Пакує одне точне слово у фізичний T5M, 5 тритів на байт.

    bits: test-only MSB-first payload (str); result: owned immutable bytes.
    Padding=2 is transport only, neither value nor a numeric domain.
    Питання: чому збережено провідні нулі? Чому 2 не біт?
    Чому точна ширина надходить ззовні? Хто володіє bytes?
    """
    if not bits or any(bit not in '01' for bit in bits):
        raise ValueError('нефізичне двійкове слово')
    trits = [int(bit) for bit in bits]
    trits.extend([2] * (-len(trits) % 5))
    return bytes(sum(trits[pos + i] * (3 ** (4 - i)) for i in range(5))
                 for pos in range(0, len(trits), 5))


def physical_number(value: int, width: int) -> bytes:
    """Незалежно створює Wn двійковий атом, не host Int64 чи .lisp."""
    lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
    if value < lo or value > hi:
        raise ValueError(f'значення {value} поза D{width}')
    return pack_word(f'{value & ((1 << width) - 1):0{width}b}')


def expected_result(value: int, width: int) -> bytes | None:
    """None=очікуване fail-closed, не D1:0 або D3:000."""
    lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
    if lo <= value <= hi:
        return physical_number(value, width)
    if width == 192:
        return None
    return physical_number(value, width * 2)


def pairs(width: int) -> list[tuple[int, int]]:
    """Детерміновані межі та змішані знаки — не статистична оцінка."""
    lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
    edge = [(0, 0), (0, hi), (lo, 0), (1, -1), (-1, 1),
            (hi, 1), (lo, -1), (hi, hi), (lo, lo), (lo, hi),
            (hi, lo), (hi, -1), (lo, 1), (hi, -2), (lo, 2),
            (-1, lo), (-1, hi), (hi, 0), (1, lo), (1, hi)]
    rng = random.Random(SEED + width)
    for i in range(32):
        if i % 4 == 0:
            edge.append((rng.randint(lo, hi), rng.randint(lo, hi)))
        elif i % 4 == 1:
            edge.append((rng.randint(lo, hi), rng.randint(-3, 3)))
        elif i % 4 == 2:
            edge.append((rng.randint(max(lo, -32768), min(hi, 32767)),
                         rng.randint(max(lo, -32768), min(hi, 32767))))
        else:
            edge.append((rng.choice((lo, lo + 1, -1, 0, 1, hi - 1, hi)),
                         rng.randint(lo, hi)))
    assert all(lo <= a <= hi and lo <= b <= hi for a, b in edge)
    return edge


def invoke(binary: Path, width: int, left: Path, right: Path,
           expected: bytes | None, label: str) -> None:
    run = subprocess.run([str(binary), f'D{width}', str(left), str(right)],
                         capture_output=True, timeout=20, check=False)
    if expected is None:
        if run.returncode != 2 or run.stdout or b'\xd0\x9f\xd0\x9e\xd0\x9c\xd0\x98\xd0\x9b\xd0\x9a\xd0\x90' not in run.stderr:
            raise AssertionError(f'{label}: відмова без rc=2/порожнього stdout/діагностики: '
                                 f'rc={run.returncode} stdout={run.stdout.hex()} stderr={run.stderr[-250:]!r}')
    elif run.returncode != 0 or run.stdout != expected:
        raise AssertionError(f'{label}: rc={run.returncode}, очікуване={expected.hex()}, '
                             f'фактичне={run.stdout.hex()}, stderr={run.stderr[-250:]!r}')


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == '--самоперевірка':
        assert pack_word('0') == bytes([80])
        assert pack_word('1') == bytes([161])
        assert physical_number(1, 12) == bytes([0, 0, 53])
        assert physical_number(-1, 12) == bytes([121, 121, 134])
        assert expected_result(2048, 12) == physical_number(2048, 24)
        assert expected_result(1 << 191, 192) is None
        assert len(pairs(192)) == 52
        print('D12-МОДЕЛЬ-САМОПЕРЕВІРКА-ГАРАЗД T5M=base3/5 W12=точно домени=5')
        return 0
    if len(sys.argv) != 3:
        raise SystemExit('Виклик: test-chysla-d12-model.py додавання_FPC множення_FPC')
    addition, multiply = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    if not addition.is_file() or not multiply.is_file():
        raise SystemExit('D12-МОДЕЛЬ-БЛОК: потрібні зібрані FPC бінарники')

    tests = errors = 0
    with tempfile.TemporaryDirectory(prefix='фізичні числа Д12 ') as temporary:
        folder = Path(temporary)
        lhs, rhs = folder / 'ліве.sens', folder / 'праве.sens'
        for width in DOMAINS:
            for i, (a, b) in enumerate(pairs(width), 1):
                lhs.write_bytes(physical_number(a, width))
                rhs.write_bytes(physical_number(b, width))
                for binary, name, result in ((addition, 'додати', a + b),
                                             (multiply, 'помножити', a * b)):
                    expected = expected_result(result, width)
                    invoke(binary, width, lhs, rhs, expected,
                           f'D{width}/{name}/пара={i}/a={a}/b={b}')
                    tests += 1
                    errors += expected is None

        # Механічний захист: не можна перетворити чужий домен,
        # пошкоджений файл або людську проєкцію в числову відповідь.
        lhs.write_bytes(physical_number(1, 12))
        cases = ((b'\xff', 12, 'зіпсований T5M'),
                 (physical_number(1, 24), 12, 'змішані D12/D24'),
                 (b'1', 12, 'людська проєкція як байти'),
                 (b'', 12, 'порожній фізичний атом'))
        for binary in (addition, multiply):
            for physical, width, name in cases:
                rhs.write_bytes(physical)
                invoke(binary, width, lhs, rhs, None, name)
                tests += 1
                errors += 1
            # Після негативів той самий CLI працює з точними T5M байтами.
            rhs.write_bytes(physical_number(-1, 12))
            invoke(binary, 12, lhs, rhs,
                   physical_number(0 if binary == addition else -1, 12),
                   'відновлення')
            tests += 1

    print(f'D12-МОДЕЛЬ-ГАРАЗД FPC=реальний T5M=побайтово '
          f'домени=12,24,48,96,192 пар-на-домен=52 '
          f'операцій={tests} відмов={errors} відновлення=2 '
          'oracle=Python-big-int SENS-REPL=не-заявлено')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (AssertionError, subprocess.TimeoutExpired) as problem:
        print(f'D12-МОДЕЛЬ-ПРОВАЛ: {problem}', file=sys.stderr)
        sys.exit(1)
