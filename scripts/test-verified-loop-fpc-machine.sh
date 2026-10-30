#!/usr/bin/env bash
# G6.259 — машинна перевірка FPC -O2 для чесного loop-близнюка.
# Тільки host-механіка. Exit-код не є доказом того, що цикл не згорнуто.
# Той самий loop.pas; новий компілятор чи SENS-закон тут НЕ створюється.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'LOOP-FPC-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for tool in fpc objdump objcopy cmp python3 mktemp timeout; do
  command -v "$tool" >/dev/null || {
    echo "LOOP-FPC-БЛОК: відсутній $tool" >&2; exit 127;
  }
done
TMP=$(mktemp -d)
trap 'rc=$?; if ((rc)); then for f in "$TMP"/*.log; do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 60 "$f" >&2; }
done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units"

# PASCALMAIN із власного loop.pas, а НЕ випадковий цикл glibc/FPC RTL.
# Мітки та offset-и — host-координати x86-64, не ідентичності SENS.
check_machine() {
  local dis="$1" expected="$2"
  python3 - "$dis" "$expected" <<'PY'
import re, sys
from pathlib import Path
source = Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace')
wanted = sys.argv[2] == 'yes'
lines = source.splitlines()
# Не приймати чужу runtime-функцію замість програмного тіла Pascal.
start = next((i for i, line in enumerate(lines)
              if re.search(r'<_?PASCALMAIN>:\s*$', line)), None)
assert start is not None, 'немає власного PASCALMAIN у дизасемблері'
rows = []
for line in lines[start+1:]:
    if re.match(r'^\s*[0-9a-f]+\s+<[^>]+>:\s*$', line):
        break
    m = re.match(r'^\s*([0-9a-f]+):\s+(?:[0-9a-f]{2}\s+)+([a-z][a-z0-9]*)\s*(.*)$', line)
    if m:
        rows.append((int(m[1], 16), m[2], m[3]))
assert rows, 'у PASCALMAIN немає машинного коду'
loops = []
for at, op, arg in rows:
    if not op.startswith('j'):
        continue
    target = re.match(r'^(?:0x)?([0-9a-f]+)(?:\s|$)', arg)
    if not target:
        continue
    begin = int(target.group(1), 16)
    if begin >= at:
        continue
    body = [name for address, name, _ in rows if begin <= address < at]
    alu = [name for name in body if name in ('add','inc','sub','dec','lea','imul')]
    if len(alu) >= 2 and any(name in ('add','lea','imul') for name in alu) \
            and any(name in ('cmp','test') for name in body):
        loops.append((begin, at, len(alu)))
if wanted:
    assert loops, 'немає зворотного переходу з арифметикою і перевіркою межі у PASCALMAIN'
else:
    assert not loops, 'негативний контроль неправдиво прийнятий як цикл'
print('LOOP-FPC-MACHINE-OK' if wanted else 'LOOP-FPC-CONTROL-OK',
      'detected=', len(loops), 'instructions=', len(rows))
PY
}

# Негативний контроль самого інспектора: правильний код виходу
# може утворитися без жодної ітерації, і такий код НЕ можна прийняти.
cat >"$TMP/folded.dis" <<'DIS'
0000000000401000 <PASCALMAIN>:
  401000: b8 40 00 00 00          mov    eax,0x40
  401005: c3                   ret
DIS
check_machine "$TMP/folded.dis" no >"$TMP/control.log"
grep -Fq 'LOOP-FPC-CONTROL-OK' "$TMP/control.log"

# Одна реальна FPC збірка з тими самими -B -O2, що і вимірювач.
# -Cr/-Co/-Ci вплинули б на машинне тіло, тому їх перевіряють інші тести.
timeout 180s fpc -B -O2 \
  -FU"$TMP/units" -FE"$TMP/bin" -oloop-fpc-machine \
  "$ROOT/benchmarks/cross-language/loop/loop.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
exe="$TMP/bin/loop-fpc-machine"
test -x "$exe"
# FPC-конфігурація runner може виконувати -Xs (strip): у точному
# бенчмарковому ELF немає PASCALMAIN у таблиці символів. Не підмінюємо
# вимірюваний ELF: окремий свідок -B -O2 -Xs- лише зберігає символи.
# Вимога: ВСЯ .text обох збірок має збігтися побайтово, інакше відмова.
mkdir -p "$TMP/symbol-bin" "$TMP/symbol-units"
timeout 180s fpc -B -O2 -Xs- \
  -FU"$TMP/symbol-units" -FE"$TMP/symbol-bin" -oloop-fpc-symbols \
  "$ROOT/benchmarks/cross-language/loop/loop.pas" >"$TMP/symbol-build.log" 2>&1 || {
    cat "$TMP/symbol-build.log" >&2; exit 1;
  }
symbol_exe="$TMP/symbol-bin/loop-fpc-symbols"
test -x "$symbol_exe"
objcopy --dump-section .text="$TMP/bench.text" "$exe"
objcopy --dump-section .text="$TMP/symbol.text" "$symbol_exe"
[[ -s "$TMP/bench.text" && -s "$TMP/symbol.text" ]] || {
  echo 'LOOP-FPC-БЛОК: відсутній виконуваний .text' >&2; exit 1;
}
cmp -s "$TMP/bench.text" "$TMP/symbol.text" || {
  echo 'LOOP-FPC-БЛОК: .text точного -O2 та -O2 -Xs- різні' >&2
  exit 1
}
timeout 20s objdump -d -M intel "$symbol_exe" >"$TMP/fpc.dis"
if ! check_machine "$TMP/fpc.dis" yes >"$TMP/machine.log" 2>"$TMP/inspector.log"; then
  echo 'LOOP-FPC-БЛОК: власний PASCALMAIN або його машинний цикл не доведено' >&2
  cat "$TMP/inspector.log" >&2
  echo '--- Символи свідка ---' >&2
  objdump -t "$symbol_exe" | grep -E 'PASCALMAIN|_main' >&2 || true
  echo '--- PASCALMAIN у дизасембляції свідка ---' >&2
  grep -E -A 8 '<_?PASCALMAIN>:' "$TMP/fpc.dis" >&2 || true
  exit 1
fi
grep -Fq 'LOOP-FPC-MACHINE-OK' "$TMP/machine.log"

for row in '1000000 1' '1000001 7'; do
  read -r n k <<< "$row"
  want=$(( (n % 256)*(k % 256) % 256 ))
  got=0
  if timeout 10s "$exe" "$n" "$k" >"$TMP/actual.out" 2>"$TMP/native.err"; then
    got=0
  else
    got=$?
  fi
  [[ "$got" -eq "$want" ]] && [[ ! -s "$TMP/actual.out" ]] || {
    echo "LOOP-FPC-БЛОК: N=$n K=$k exit=$got замість $want" >&2
    exit 1
  }
done
cat "$TMP/control.log" "$TMP/machine.log"
echo 'VERIFIED-LOOP-FPC-MACHINE-PASS FPC=real O2=exact-benchmark-flags native-loop=1 text=byte-identical folded-control=1 oracle=2 SENS-oracle=NOT-RUN joules=NOT-MEASURED'
