#!/usr/bin/env bash
# G6.269 — захист енергетичного FPC-бюджету від неврахованого YAML on:.
# Старий check-workflow-fpc-budget.sh рахує лише форму "on:" + ключі з
# двома пробілами. Тому короткий on: [push] може обійти бюджет.
# Цей перевірений контекст НЕ дублює підрахунок та НЕ змінює CI-hook:
# він вимагає для FPC-workflow форму, яку чинний бюджет справді бачить.
# Залежності: bash, Python3 stdlib, Linux/macOS; без Rust/Zig/FPC build.
#
# 1) Чому валідний YAML не обов'язково врахований бюджетним парсером?
# 2) Чому невідомий синтаксис треба відхилити, а не вгадувати тригер?
# 3) Чому перевірка стосується тільки workflow з ознакою fp-compiler?
# 4) Чому цей gate не доводить вимірювання енергії чи семантику SENS?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v python3 >/dev/null || {
  echo 'FPC-ТРИГЕР-БЛОК: відсутній Python3' >&2
  exit 127
}
python3 -B - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
workflows = root / '.github' / 'workflows'

def check_form(text):
    # Точно той самий маркер, за яким наявний бюджет визначає важкий job.
    if 'fp-compiler' not in text:
        return None
    lines = text.splitlines()
    keys = [(n, line) for n, line in enumerate(lines) if re.match(
        r"""^(?:on|"on"|'on')\s*:""", line)]
    if len(keys) != 1:
        return 'очікувався рівно один верхньорівневий ключ on:'
    at, header = keys[0]
    if not re.fullmatch(r'on:[ \t]*(?:#.*)?', header):
        return 'короткий/закавичений on: не враховується бюджетом'
    children = []
    for line in lines[at + 1:]:
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if re.match(r'^[^\s#]', line):
            break
        if re.match(r'^  [a-zA-Z_][a-zA-Z_0-9]*:', line):
            children.append(line.strip().split(':', 1)[0])
        elif line.startswith('  ') and not line.startswith('    '):
            return 'on: має невраховану форму дочірнього тригера'
    if not children:
        return 'on: не має жодного тригера у формі двох пробілів'
    return None

# Негативи є тестом самого guard, а не реальними SENS програмами.
samples = [
    ('правильний-ручний', 'on:\n  workflow_dispatch:\njobs:\n  a: fp-compiler\n', True),
    ('правильний-push', 'on:\n  push:\n    branches: [main]\njobs:\n  a: fp-compiler\n', True),
    ('коментар', '# on: [push]\non:\n  schedule:\n    - cron: "5 3 * * *"\njobs:\n  a: fp-compiler\n', True),
    ('короткий-список', 'on: [push, pull_request]\njobs:\n  a: fp-compiler\n', False),
    ('коротка-мапа', 'on: {push: {}}\njobs:\n  a: fp-compiler\n', False),
    ('закавичений-ключ', '"on":\n  push:\njobs:\n  a: fp-compiler\n', False),
    ('список-на-новому-рядку', 'on:\n  - push\njobs:\n  a: fp-compiler\n', False),
    ('порожній-список', 'on:\njobs:\n  a: fp-compiler\n', False),
    ('пробіл-перед-двокрапкою', 'on :\n  push:\njobs:\n  a: fp-compiler\n', False),
    ('без-on', 'jobs:\n  a: fp-compiler\n', False),
    ('легкий-workflow', 'on: [push]\njobs:\n  a: echo OK\n', True),
]
for label, fixture, should_pass in samples:
    actual = check_form(fixture) is None
    if actual != should_pass:
        raise SystemExit('FPC-ТРИГЕР-ТЕСТ-ПОМИЛКА ' + label)

files = sorted((*workflows.glob('*.yml'), *workflows.glob('*.yaml')))
checked = 0
bad = []
for file in files:
    data = file.read_text(encoding='utf-8')
    if 'fp-compiler' not in data:
        continue
    checked += 1
    problem = check_form(data)
    if problem is not None:
        bad.append((file.relative_to(root).as_posix(), problem))
for file, why in bad:
    print('FPC-ТРИГЕР-FAIL ' + file + ': ' + why, file=sys.stderr)
    if __import__('os').environ.get('GITHUB_ACTIONS') == 'true':
        print('::error file=' + file + ',title=FPC-тригер::' + why, file=sys.stderr)
if bad:
    raise SystemExit(1)
if checked == 0:
    raise SystemExit('FPC-ТРИГЕР-БЛОК: не знайдено жодного FPC-workflow')
print('VERIFIED-FPC-TRIGGER-SHAPE-PASS workflows=' + str(len(files)) +
      ' fpc=' + str(checked) + ' fixtures=' + str(len(samples)) +
      ' energy=NOT-MEASURED')
PY
