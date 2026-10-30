#!/usr/bin/env bash
# G6.233 — підроблений RAPL не може видати себе за фізичні джоулі.
# Python host-тест підхоплює наявний verified-all / fpc-headless:
# окремого Rust/Zig/FPC збирання чи нового workflow немає.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" = Linux && "$(uname -m)" = x86_64 ]] || {
  echo 'RAPL-ДЖЕРЕЛО-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in python3 timeout mktemp; do
  command -v "$tool" >/dev/null || {
    echo "RAPL-ДЖЕРЕЛО-БЛОК: немає $tool" >&2; exit 127;
  }
done
test -x /bin/echo
timeout 35s python3 - "$ROOT/scripts/vymir-native-elf.py" <<'PY'
import json
from pathlib import Path
import subprocess
import sys
import tempfile

meter = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='rapl-dzherelo-') as directory:
    root = Path(directory)
    expected = root / 'physical.expected.sens'
    # Цей host smoke НЕ є SENS oracle: /bin/echo — справжній ELF64,
    # перевіряється тільки чесність статусу вимірювача.
    expected.write_bytes(b'\n')
    common = [sys.executable, str(meter), '--машина', '/bin/echo',
              '--очікуване', str(expected), '--пакетів', '1',
              '--повторів', '2', '--прогрів', '1',
              '--ліміт-секунд', '2']

    def run(*extra):
        return subprocess.run([*common, *extra], capture_output=True,
                              text=True, timeout=9, check=False)

    good = run()
    assert good.returncode == 0 and good.stderr == '', (good.returncode, good.stderr)
    report = json.loads(good.stdout)
    assert report['енергія-статус'] == 'НЕ-ВИМІРЯНО'
    assert report['енергія-джоулі-пакети'] is None
    assert report['виконань-перевірено'] == 3

    fake = root / 'intel-rapl:0'
    fake.mkdir()
    (fake / 'name').write_text('package-0\n', encoding='ascii')
    energy = fake / 'energy_uj'
    border = fake / 'max_energy_range_uj'
    energy.write_text('99\n', encoding='ascii')
    border.write_text('1000\n', encoding='ascii')

    links = root / 'посилання'
    links.mkdir()
    alias_energy = links / 'energy_uj'
    alias_border = links / 'max_energy_range_uj'
    alias_energy.symlink_to(energy)
    alias_border.symlink_to(border)
    other = root / 'intel-rapl:1'
    other.mkdir()
    other_border = other / 'max_energy_range_uj'
    other_border.write_text('1000\n', encoding='ascii')

    negatives = [
        ('локальні-лічильники', energy, border),
        ('символьні-посилання', alias_energy, alias_border),
        ('різні-пакети', energy, other_border),
        ('неправильне-ім’я', fake / 'name', border),
    ]
    for label, source, maximum in negatives:
        bad = run('--rapl-енергія', str(source),
                  '--rapl-межа', str(maximum))
        assert bad.returncode == 2, (label, bad.returncode, bad.stderr)
        assert bad.stdout == '', (label, bad.stdout)
        assert 'RAPL-ВІДМОВА' in bad.stderr, (label, bad.stderr)
    print('VERIFIED-RAPL-ORIGIN-PASS positives=1 negatives=4 '
          'real-ELF=1 physical-energy=NOT_MEASURED oracle=NOT_RUN')
PY
