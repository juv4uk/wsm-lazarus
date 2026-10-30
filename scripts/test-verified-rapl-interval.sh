#!/usr/bin/env bash
# G6.238 — host-метрологія: тільки однозначна RAPL-дельта для нативного ELF.
# Фізичні SENS закони, D7, D12+, ELF та .lisp тут НЕ інтерпретуються.
# Тест запускається у вже наявному fpc-headless verified-агрегаторі.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v python3 >/dev/null || { echo 'RAPL-ІНТЕРВАЛ-БЛОК: немає Python 3' >&2; exit 127; }
command -v timeout >/dev/null || { echo 'RAPL-ІНТЕРВАЛ-БЛОК: немає timeout' >&2; exit 127; }
timeout 15s python3 -B - "$ROOT/scripts/vymir-native-elf.py" <<'PY'
import importlib.util
from pathlib import Path
import sys

source = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("vymir_native_elf", source)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
delta = mod.rapl_delta

positive = (
    (100, 150, 1000, 999, 50),  # немає обертання
    (990, 10, 1000, 999, 20),   # рівно один wrap
    (42, 42, 1000, 999, 0),     # справжній нуль можливий лише в короткому вікні
    (0, 1, 1000000, 999999, 1), # близько до верхньої межі, але нижче
)
for before, after, maximum, ns, expected in positive:
    actual = delta(before, after, maximum, ns)
    assert actual == expected, (before, after, maximum, ns, actual, expected)

negative = (
    (100, 150, 1000, 0),     # нечинний clock
    (100, 150, 1000, -1),
    (-1, 150, 1000, 1),      # лічильник поза діапазоном
    (100, -1, 1000, 1),
    (1000, 150, 1000, 1),
    (100, 1000, 1000, 1),
    (0, 0, 0, 1),            # відсутня фізична межа
    (100, 150, 1000, 1000), # поріг = 1000 Вт envelope
    (100, 150, 1000, 1001), # два оберти вже можливі
    (42, 42, 1000, 10000),  # не видавати 0 Дж за довгий інтервал
)
for before, after, maximum, ns in negative:
    try:
        delta(before, after, maximum, ns)
    except ValueError as exc:
        assert 'RAPL-ВІДМОВА' in str(exc), str(exc)
    else:
        raise AssertionError(f'прийнято неоднозначний лічильник {(before, after, maximum, ns)}')

print(f'RAPL-INTERVAL-PASS positive={len(positive)} negative={len(negative)} '
      'multiwrap=reject simulated-joules=none energy=NOT-MEASURED')
PY
