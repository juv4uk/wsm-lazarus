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
for tool in fpc gcc python3 timeout mktemp grep sha256sum; do
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

# У Python тільки host stopwatch і точна перевірка exit; жодної SENS
# семантики, енергетичної моделі чи прихованого перетворення .sens у текст.
timeout 120s python3 -B - "$TMP/bin/sens-native.elf" "$TMP/bin/loop-c" "$N" "$K" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import statistics
import struct
import subprocess
import sys
import time

sens, c_elf = (Path(sys.argv[1]), Path(sys.argv[2]))
n, k = int(sys.argv[3]), int(sys.argv[4])
expected = ((n & 255) * (k & 255)) & 255
executables = {'SENS': sens, 'C/GCC': c_elf}
hashes = {}
for language, path in executables.items():
    data = path.read_bytes()
    if (len(data) < 64 or data[:6] != b'\x7fELF\x02\x01'
            or struct.unpack_from('<H', data, 18)[0] != 62):
        raise RuntimeError(f'{language}: потрібен справжній x86-64 ELF64')
    hashes[language] = hashlib.sha256(data).hexdigest()

def run_checked(language):
    result = subprocess.run([str(executables[language])], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False, timeout=8)
    if result.returncode != expected or result.stdout or result.stderr:
        raise RuntimeError(
            f'{language}: не збігся exact exit/stdout/stderr: '
            f'code={result.returncode} expected={expected} '
            f'out={len(result.stdout)} err={len(result.stderr)}')

warmups = 3
batches = 5
per_batch = 7
for _ in range(warmups):
    for language in executables:
        run_checked(language)

times = {language: [] for language in executables}
for i in range(batches):
    order = ['SENS', 'C/GCC'] if i % 2 == 0 else ['C/GCC', 'SENS']
    for language in order:
        before = time.perf_counter_ns()
        for _ in range(per_batch):
            run_checked(language)
        elapsed = time.perf_counter_ns() - before
        if elapsed <= 0:
            raise RuntimeError(f'{language}: немонотонний host-годинник')
        times[language].append(elapsed / per_batch)
medians = {language: round(statistics.median(values))
           for language, values in times.items()}
if not all(value > 0 for value in medians.values()):
    raise RuntimeError('порожній/нульовий результат вимірювача')

cpu = 'невідомо'
try:
    for line in Path('/proc/cpuinfo').read_text(errors='replace').splitlines():
        if line.startswith('model name'):
            cpu = line.split(':', 1)[1].strip()
            break
except OSError:
    pass
cpu = cpu.replace('|', '/').replace('\r', ' ').replace('\n', ' ')[:96]
report = {
    'формат': 'SENS-CI-БЕНЧ-1',
    'фізичний-вхід': 'pinned D12 packed T5M через test-d12loop.pas',
    'навантаження': {'N': n, 'K': k, 'expected-exit': expected},
    'стенд': {'cpu': cpu, 'ci': os.getenv('GITHUB_ACTIONS', 'false'),
              'runner_os': os.getenv('RUNNER_OS', 'unknown'),
              'sha': os.getenv('GITHUB_SHA', 'local')},
    'прогрівів-на-машину': warmups,
    'пакетів': batches,
    'виконань-у-пакеті': per_batch,
    'перевірених-виконань-на-машину': warmups + batches * per_batch,
    'медіана-нс-на-виклик': medians,
    'усі-пакети-нс-на-виклик': times,
    'elf-sha256': hashes,
    'енергія-джоулі': None,
    'енергія-статус': 'НЕ-ВИМІРЯНО',
    'застереження': 'GitHub shared/virtual runner; measured process start + work, '
                   'not isolated instruction latency or physical joules; '
                   'results are not cross-run rankings.',
}

summary = os.getenv('GITHUB_STEP_SUMMARY')
if summary:
    with open(summary, 'a', encoding='utf-8') as stream:
        stream.write('## G6.263 — фізичний SENS ELF64 проти C/GCC (CI, без RAPL)\n\n')
        stream.write(f'Runner CPU: `{cpu}` · N={n}, K={k}, exact exit={expected}.\n\n')
        stream.write('| Машина | Медіана нс/виклик | ELF SHA256 |\n')
        stream.write('|---|---:|---|\n')
        for language in executables:
            stream.write(f'| {language} | {medians[language]} | '
                         f'`{hashes[language]}` |\n')
        stream.write(f'\nПрогрівів={warmups}, пакетів={batches}, запусків/пакет={per_batch}; '
                     f'на кожну машину {warmups + batches * per_batch} '
                     'фактично перевірених запусків.\n\n')
        stream.write('**Енергія: НЕ ВИМІРЯНА; джоулі = null.** '
                     'Немає фізичного виміру без датчика. '
                     'Час включає старт процесу; runner може бути віртуальним '
                     'та мати фонове навантаження. Жодного рейтингу '
                     'енергоефективності за цим прогоном.\n\n')
        stream.write('<details><summary>Машинний JSON-свідок</summary>\n\n```json\n')
        stream.write(json.dumps(report, ensure_ascii=False, sort_keys=True))
        stream.write('\n```\n</details>\n\n')

# Агрегатор test-verified-all.sh відтворює останній рядок із "-PASS".
# Саме тому GitHub command має "-PASS" у title і стоїть ОСТАННІМ.
# Анотація з'явиться лише ПІСЛЯ всіх перевірених машинних виконань.
print('::notice title=G6.263-SENS-БЕНЧ-PASS::'
      f'SENS median={medians["SENS"]} ns; C/GCC median={medians["C/GCC"]} ns; '
      f'N={n} K={k} exact-exit={expected}; '
      f'checked={warmups + batches * per_batch} per ELF; '
      'energy=NOT-MEASURED joules=null; див. Job Summary', flush=True)
PY
