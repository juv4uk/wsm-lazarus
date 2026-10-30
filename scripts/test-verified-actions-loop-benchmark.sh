#!/usr/bin/env bash
# G6.263 — реальний GitHub Actions бенчмарк: фізичний SENS D12 → ELF64 проти C/GCC.
# Фізичний K5 походить тільки з наявного EncodeT5M у test-d12loop.pas;
# native lowering виконує лише наявний wsm.elfd12loop / sensd12loop.
# Результат: verified exit кожного процесу, медіана ns (старт + робота),
# SHA256 ELF, ::notice у Actions та Job Summary; джоулі НЕ вимірюються.
# Питання: 1) Чому exit не є SENS D12 значенням?
# 2) Чому час хмарного runner не можна називати джоулями?
# 3) Навіщо перевіряти кожний запуск і перемішувати порядок?
# 4) Чому GNU register barrier важливий для близнюка C?
# 5) Чому бенчмарк CLI/proc-start відмінний від чистого циклу?
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'CI-БЕНЧ-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in fpc gcc python3 objdump timeout mktemp grep sha256sum; do
  command -v "$tool" >/dev/null || {
    echo "CI-БЕНЧ-БЛОК: бракує $tool" >&2; exit 127;
  }
done

# Фіксоване навантаження: 20 000 001 додавань п'ятірки, exit=5.
# Це host workload, НЕ новий SENS закон. C GNU asm-barrier зберігає цикл.
N=20000001
K=5
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  echo "CI-БЕНЧ-БЛОК: невдалий запуск, exit=$rc" >&2
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
    echo "::error title=G6.263-БЕНЧ-FAIL::Помилка фізичного ELF, компіляції або точного оракула, exit=$rc" >&2
  fi
  for f in "$TMP"/*.log; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 24 "$f" >&2; }
  done
fi
rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/fixtures"

timeout 60s bash "$ROOT/scripts/check-pin.sh" >"$TMP/pin.log" 2>&1
# Існуючий тестовий генератор створює справжній packed k5.sens;
# FPC тут не повторює бібліотечні закони Core1/Core4.
timeout 180s fpc -B -Mobjfpc -Fu"$ROOT/src" -FU"$TMP/units" \
  -FE"$TMP/bin" -otest-d12loop "$ROOT/scripts/test-d12loop.pas" \
  >"$TMP/fixture-build.log" 2>&1
timeout 60s "$TMP/bin/test-d12loop" "$ROOT" "$TMP/fixtures" \
  >"$TMP/fixture.log" 2>&1
grep -Fxq 'SENS-D12LOOP-PASS checks=41' "$TMP/fixture.log"
test -s "$TMP/fixtures/k5.sens"

timeout 180s fpc -B -Mobjfpc -Fu"$ROOT/src" -FU"$TMP/units" \
  -FE"$TMP/bin" -osensd12loop "$ROOT/src/sensd12loop.lpr" \
  >"$TMP/native-build.log" 2>&1
timeout 30s "$TMP/bin/sensd12loop" --build \
  "$TMP/fixtures/k5.sens" "$N" "$TMP/bin/sens-native.elf" \
  >"$TMP/native-cli.log" 2>&1
grep -Fq "SENS-D12LOOP-BUILT bytes=151 iterations=$N" "$TMP/native-cli.log"
test -x "$TMP/bin/sens-native.elf"

# Лише GCC C-близнюк; жодної збірки Rust/Zig на кожний PR.
timeout 90s gcc -O2 -DLOOP_N="$N" -DLOOP_K="$K" \
  -o "$TMP/bin/loop-c" "$ROOT/benchmarks/cross-language/loop/loop.c" \
  >"$TMP/gcc-build.log" 2>&1
test -x "$TMP/bin/loop-c"

# G6.264: еталон малого, АЛЕ НЕ ПОРОЖНЬОГО навантаження.
# N=1 — одна операція та той самий шлях запуску, не «чисті витрати процесу».
timeout 30s "$TMP/bin/sensd12loop" --build \
  "$TMP/fixtures/k5.sens" 1 "$TMP/bin/sens-base.elf" \
  >"$TMP/native-base-cli.log" 2>&1
grep -Fq 'SENS-D12LOOP-BUILT bytes=151 iterations=1' "$TMP/native-base-cli.log"
test -x "$TMP/bin/sens-base.elf"
timeout 90s gcc -O2 -DLOOP_N=1 -DLOOP_K="$K" \
  -o "$TMP/bin/loop-c-base" "$ROOT/benchmarks/cross-language/loop/loop.c" \
  >"$TMP/gcc-base-build.log" 2>&1
test -x "$TMP/bin/loop-c-base"

# Незалежне машинне свідчення C main: не приймаємо правильний exit без циклу.
timeout 15s objdump -d -M intel "$TMP/bin/loop-c" >"$TMP/c-main.dis"

# У Python тільки host stopwatch і точна перевірка exit; жодної SENS
# семантики, енергетичної моделі чи прихованого перетворення .sens у текст.
timeout 120s python3 -B - "$TMP/bin/sens-native.elf" "$TMP/bin/loop-c" \
  "$TMP/bin/sens-base.elf" "$TMP/bin/loop-c-base" "$TMP/c-main.dis" "$N" "$K" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import struct
import subprocess
import sys
import time

# G6.264: шлях до виконуваного ELF — позичений і незмінний;
# hash — SHA256 фізичних байтів; жоден ELF не інтерпретується як закон.
paths = dict(zip(('SENS', 'C/GCC', 'SENS база', 'C/GCC база'),
                 (Path(value) for value in sys.argv[1:5])))
disassembly = Path(sys.argv[5])
n, k = int(sys.argv[6]), int(sys.argv[7])
want = ((n & 255) * (k & 255)) & 255
if want != 5:
    raise RuntimeError('неочікуваний контроль арифметики host')

hashes = {}
for label, path in paths.items():
    data = path.read_bytes()
    if (len(data) < 64 or data[:6] != b'\x7fELF\x02\x01'
            or struct.unpack_from('<H', data, 18)[0] != 62):
        raise RuntimeError(label + ': не x86-64 ELF64')
    hashes[label] = hashlib.sha256(data).hexdigest()

# Наявний SENS-компілятор має фіксований ET_EXEC header (120 B).
# Перевіряємо не рядок вихідного коду, а машинні ADD/DEC/JNZ і immediate K.
for label in ('SENS', 'SENS база'):
    image = paths[label].read_bytes()
    if (len(image) != 151 or image[130:135] != bytes((5, k, 0, 0, 0))
            or image[135:139] != bytes.fromhex('ff c9 75 f7')):
        raise RuntimeError(label + ': у фізичному ELF немає очікуваного циклу')
    count = n if label == 'SENS' else 1
    if image[126:130] != count.to_bytes(4, 'little'):
        raise RuntimeError(label + ': інше N у машинному образі')

# Перевіряємо сам main C/GCC, не випадковий цикл у glibc.
assembly = disassembly.read_text(encoding='utf-8', errors='replace')
start = re.search(r'(?m)^[0-9a-f]+ <main>:\s*$', assembly)
if not start:
    raise RuntimeError('C/GCC: відсутній власний main')
after = assembly[start.end():]
end = re.search(r'(?m)^[0-9a-f]+ <[^>]+>:\s*$', after)
block = after[:end.start()] if end else after
rows = []
for line in block.splitlines():
    match = re.match(
        r'^\s*([0-9a-f]+):\s+(?:[0-9a-f]{2}\s+)+([a-z][a-z0-9]*)\s*(.*)$',
        line)
    if match:
        rows.append((int(match[1], 16), match[2], match[3]))
if not rows:
    raise RuntimeError('C/GCC: main не дизасембльовано')
found = False
for at, op, args in rows:
    if not op.startswith('j'):
        continue
    target = re.match(r'^\s*([0-9a-f]+)(?:\s|$)', args)
    if not target:
        continue
    begin = int(target[1], 16)
    if begin >= at:
        continue
    body = [opcode for address, opcode, _ in rows if begin <= address < at]
    if ('add' in body and any(x in body for x in ('sub', 'dec', 'inc', 'cmp', 'test'))):
        found = True
        break
if not found:
    raise RuntimeError('C/GCC: main не містить зворотного машинного циклу')

def checked_run(label):
    # Фактичний результат — exit/порожні stdout+stderr кожного процесу.
    # Вимірюємо wall час, ВКЛЮЧНО зі стартом/синхронізацією subprocess.
    result = subprocess.run(
        [str(paths[label])], capture_output=True, check=False, timeout=10)
    if result.returncode != want or result.stdout or result.stderr:
        raise RuntimeError(
            label + ': exit=' + str(result.returncode) +
            ' замість ' + str(want) + ', stdout=' + str(len(result.stdout)) +
            ', stderr=' + str(len(result.stderr)))

def median_abs_deviation(values):
    center = statistics.median(values)
    return statistics.median(abs(x-center) for x in values)

def p10_p90(values):
    ordered = sorted(values)
    # Рангові квантилі без припущення про нормальний розподіл.
    return round(ordered[0]), round(ordered[-1])

warmups, rounds, per_round = 3, 9, 5
for _ in range(warmups):
    for label in paths:
        checked_run(label)

samples = {label: [] for label in paths}
# Змінюємо порядок, щоб дрейф runner не закріпився за одним компілятором.
for round_id in range(rounds):
    long_order = ['SENS', 'C/GCC'] if round_id % 2 == 0 else ['C/GCC', 'SENS']
    base_order = ['C/GCC база', 'SENS база'] if round_id % 2 == 0 else ['SENS база', 'C/GCC база']
    for label in long_order + base_order:
        beginning = time.perf_counter_ns()
        for _ in range(per_round):
            checked_run(label)
        elapsed = time.perf_counter_ns() - beginning
        if elapsed <= 0:
            raise RuntimeError('немонотонний таймер: ' + label)
        samples[label].append(elapsed / per_round)

medians = {label: round(statistics.median(values))
           for label, values in samples.items()}
mad = {label: round(median_abs_deviation(values))
       for label, values in samples.items()}
limits = {label: p10_p90(values) for label, values in samples.items()}
if not all(value > 0 for value in medians.values()):
    raise RuntimeError('нулева або відсутня тривалість')

# Корекція baseline — ОЦІНКА, не ізольована CPU latency.
# Від'ємне значення не обрізаємо: це можливий сигнал шуму runner.
delta = {
    'SENS': round(statistics.median(
        [a-b for a, b in zip(samples['SENS'], samples['SENS база'])])),
    'C/GCC': round(statistics.median(
        [a-b for a, b in zip(samples['C/GCC'], samples['C/GCC база'])]))
}

cpu = 'невідомо'
virtualized = False
try:
    for line in Path('/proc/cpuinfo').read_text(errors='replace').splitlines():
        if line.startswith('model name') and cpu == 'невідомо':
            cpu = line.split(':', 1)[1].strip()
        if line.startswith('flags') and ' hypervisor ' in (' '+line+' '):
            virtualized = True
except OSError:
    pass
cpu = cpu.replace('|', '/').replace('\r', ' ').replace('\n', ' ')[:96]

def version(program, arg):
    try:
        r = subprocess.run([program, arg], capture_output=True,
                           text=True, check=False, timeout=4)
        return ((r.stdout or r.stderr).strip().splitlines() or ['невідомо'])[0][:100]
    except (OSError, subprocess.SubprocessError):
        return 'недоступно'

versions = {'FPC': version('fpc', '-iV'),
            'GCC': version('gcc', '-dumpfullversion')}
report = {
    'формат': 'SENS-CI-БЕНЧ-2',
    'фізичне-походження': 'pinned D12 packed T5M / test-d12loop.pas',
    'навантаження': {'N': n, 'K': k, 'N-база': 1, 'exact-exit': want},
    'метод': 'девʼять парних чергованих серій, wall ns/процес, не CPU joules',
    'стенд': {'cpu': cpu, 'cpu_count': os.cpu_count(),
              'hypervisor_flag': virtualized,
              'runner_os': os.getenv('RUNNER_OS', 'unknown'),
              'runner_arch': os.getenv('RUNNER_ARCH', 'unknown'),
              'runner_image': os.getenv('ImageOS', 'unknown'),
              'runner_image_version': os.getenv('ImageVersion', 'unknown'),
              'github_sha': os.getenv('GITHUB_SHA', 'local'),
              'compiler_versions': versions},
    'прогрів-на-ELF': warmups,
    'серій': rounds,
    'виконань-у-серії': per_round,
    'виконань-на-ELF': warmups + rounds * per_round,
    'медіана-нс-на-виклик': medians,
    'MAD-нс': mad,
    'межі-спостережень-нс': limits,
    'усі-серії-нс-на-виклик': samples,
    'приблизна-різниця-long-мінус-N1-нс': delta,
    'перевірка-машинного-циклу': 'SENS ADD/DEC/JNZ bytes + C main backedge',
    'elf-sha256': hashes,
    'енергія-джоулі': None,
    'енергія-статус': 'НЕ-ВИМІРЯНО',
    'обмеження': 'Один GitHub-hosted run із шумом інших процесів; '
                 'N=1 не чистий startup; різниця є лише приблизною; '
                 'тіла x86-64 різні; RAPL не використовувався.'
}
summary = os.getenv('GITHUB_STEP_SUMMARY')
if summary:
    with open(summary, 'a', encoding='utf-8') as out:
        out.write('## G6.264 — повторні фізичні SENS/C бенчмарки без RAPL\n\n')
        out.write('CPU: ' + cpu + ' · FPC ' + versions['FPC'] +
                  ' · GCC ' + versions['GCC'] + '\n\n')
        out.write('N=' + str(n) + ', K=' + str(k) +
                  ', база N=1, exact exit=' + str(want) +
                  ', перевірено по ' + str(warmups + rounds * per_round) +
                  ' запусків на кожен ELF.\n\n')
        out.write('| Виконуваний ELF | Медіана, нс | MAD, нс | Мін.–макс., нс |\n'
                  '|---|---:|---:|---:|\n')
        for label in paths:
            out.write('| ' + label + ' | ' + str(medians[label]) + ' | ' +
                      str(mad[label]) + ' | ' + str(limits[label][0]) +
                      '–' + str(limits[label][1]) + ' |\n')
        out.write('\n**Орієнтовна різниця N=20000001 мінус N=1:** SENS ' +
                  str(delta['SENS']) + ' нс; C/GCC ' + str(delta['C/GCC']) +
                  ' нс. Це не ізольований вимір CPU, а парна оцінка шумного runner.\n\n')
        out.write('**Машинний доказ:** SENS ADD/DEC/JNZ по байтах ELF, '
                  'C/GCC — зворотний перехід з арифметикою у власному main.\n\n')
        out.write('**Енергія: НЕ ВИМІРЯНА, джоулі = null.** '
                  'Без датчика немає фізичного висновку про енергоефективність.\n\n')
        out.write('### Машинний звіт JSON\n\n')
        out.write(chr(96)*3 + 'json\n' +
                  json.dumps(report, ensure_ascii=False, sort_keys=True) +
                  '\n' + chr(96)*3 + '\n\n')

print('::notice title=G6.264-ПАРНИЙ-БЕНЧ-PASS::'
      'SENS=' + str(medians['SENS']) + 'ns MAD=' + str(mad['SENS']) +
      '; C=' + str(medians['C/GCC']) + 'ns MAD=' + str(mad['C/GCC']) +
      '; N1-baseline SENS=' + str(medians['SENS база']) +
      'ns C=' + str(medians['C/GCC база']) +
      'ns; baseline-adjusted SENS=' + str(delta['SENS']) +
      'ns C=' + str(delta['C/GCC']) +
      'ns; 48 runs/ELF; loop machine verified; joules=null '
      'energy=NOT-MEASURED', flush=True)
PY
