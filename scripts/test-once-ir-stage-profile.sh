#!/usr/bin/env bash
# G6 / #848 агент Б: справжній FPC stage-профіль без змін компілятора.
# 16 різних packed T5M програм, шість повторів і 16 виконуваних ELF64.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || exit 127
for exe in fpc git timeout python3 readelf cmp sha256sum mktemp chmod grep;do
  command -v "$exe" >/dev/null || {
    echo "ПРОФІЛЬ-БЛОК: відсутня команда $exe" >&2;exit 127;
  }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
finish(){
  local rc=$? f
  if ((rc!=0));then
    echo "ПРОФІЛЬ-ПРОВАЛ: код=$rc" >&2
    for f in "$TMP"/*.err "$TMP"/*.build;do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 28 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
REPORT="${PROFILE_OUT_DIR:-$TMP/report}"
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical" "$TMP/elf" "$REPORT"
for row in \
 'scripts/test-irwidefront.pas test-irwidefront' \
 'scripts/test-once-ir-stage-profile.pas test-once-ir-stage-profile';do
  read -r source name <<< "$row"
  timeout 200s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>"$TMP/$name.build.err" || {
      cat "$TMP/$name.build" "$TMP/$name.build.err" >&2;exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fq 'cases=16' "$TMP/generator.out"
timeout 180s "$TMP/bin/test-once-ir-stage-profile" \
 "$TMP/physical" "$TMP/elf" \
 >"$REPORT/etapy.tsv" 2>"$TMP/profile.err"
grep -Fq 'STAGE-NEGATIVES-OK count=2 recovery=1' "$TMP/profile.err"
# Heaptrc (прапор -gh) може друкувати успішний звіт навіть без витоків.
if grep -Fq 'unfreed memory blocks' "$TMP/profile.err";then
  grep -Fq '0 unfreed memory blocks' "$TMP/profile.err"
fi
RUN=0
for n in $(seq -w 1 16);do
  ELF="$TMP/elf/$n.elf"
  test -s "$ELF"
  readelf -h "$ELF" >"$TMP/elf.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/elf.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/elf.header"
  chmod u+x "$ELF"
  timeout 5s "$ELF" >"$TMP/$n.actual.sens" 2>"$TMP/$n.machine.err"
  test ! -s "$TMP/$n.machine.err"
  cmp "$TMP/physical/$n.expected.sens" "$TMP/$n.actual.sens"
  RUN=$((RUN+1))
done
test "$RUN" -eq 16
python3 - "$REPORT/etapy.tsv" "$REPORT/pidsumok.json" "$TMP/physical" "$PIN" <<'PY'
import collections
import csv
import hashlib
import json
import statistics
import sys
from pathlib import Path

raw, output, physical, pin = sys.argv[1:]
with open(raw, encoding='utf-8', newline='') as stream:
    rows = list(csv.DictReader(stream, delimiter='\t'))
phases = ['канонічність', 'pinned-домени', 'wideir', 'структура',
          'повна-компіляція', 'машинна-геометрія']
assert len(rows) == 16 * 6 * len(phases), len(rows)
per_phase = collections.defaultdict(list)
counts = collections.Counter()
for row in rows:
    assert set(row) == {'зразок', 'повтор', 'етап', 'наносекунди'}
    sample = row['зразок']
    repeat = int(row['повтор'])
    phase = row['етап']
    elapsed = int(row['наносекунди'])
    assert sample in [f'{n:02d}' for n in range(1, 17)]
    assert repeat in range(1, 7)
    assert phase in phases
    assert elapsed > 0
    counts[sample, repeat, phase] += 1
    per_phase[phase].append(elapsed)
assert len(counts) == 16 * 6 * len(phases)
assert set(counts.values()) == {1}
medians = {k: int(statistics.median(v)) for k, v in per_phase.items()}
files = {
    f'{n:02d}.sens': hashlib.sha256(
        (Path(physical) / f'{n:02d}.sens').read_bytes()
    ).hexdigest() for n in range(1, 17)
}
report = {
    'authority_pin': pin,
    'samples': 16, 'repeats': 6, 'raw_rows': len(rows),
    'clock': 'CLOCK_MONOTONIC', 'unit': 'ns',
    'mode': 'один-постійний-FPC-процес-без-ELF-кешу',
    'machine_elf_executed': 16,
    'rejected_inputs': 2,
    'median_stage_ns': medians,
    'physical_sha256': files,
    'cold_process_measured': False,
    'first_program_end_to_end_speedup_measured': False,
    'independent_sens_oracle': 'NOT_RUN',
    'energy': 'NOT_MEASURED',
    'limitations': [
        'Етап повна-компіляція повторює попередні обчислення.',
        'Медіани фаз не є взаємовиключними й не підлягають сумуванню.',
        'Перший процес і міжпрограмний ELF-кеш не вимірювалися.',
        'Вимірювання хостингового CI не доводять енергетичної переваги.'
    ],
}
Path(output).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n',
                        encoding='utf-8')
print('G6-848-ЕТАПИ-ПЕРЕВІРЕНО',
      f'physical=16 repeats=6 records={len(rows)}',
      'native=16 negatives=2', 'oracle=NOT_RUN', 'energy=NOT_MEASURED')
print('МЕДІАНИ-НАНОСЕКУНДИ', json.dumps(medians, ensure_ascii=False))
PY
echo "ПРОФІЛЬ-УСПІХ: FPC=checked main=native T5M=16 ELF=16 відмови=2 raw=$REPORT/etapy.tsv summary=$REPORT/pidsumok.json"
# 1. Чому backend має більший час, ніж лише побудова WideIR?
# 2. Чому 576 рядків не перетворюються на одну точну оцінку speedup?
# 3. Чому не можна складати виміри вкладених стадій?
# 4. Чому всі 16 ELF запускаються й порівнюються з фізичним stdout?
# 5. Яких свідків не вистачає для мовного й енергетичного висновку?
