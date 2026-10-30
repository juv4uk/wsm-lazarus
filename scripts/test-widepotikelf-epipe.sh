#!/usr/bin/env bash
# G6.179 — фізичний pinned SENS→WideIR→ELF64, закритий stdout.
# Host SIGPIPE/EPIPE не є законом SENS, а енергію цей тест не вимірює.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc timeout git cmp grep readelf python3 mktemp chmod; do
  command -v "$tool" >/dev/null || { echo "ШИРОКИЙ-ЕПАЙП-БЛОК: немає $tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "ШИРОКИЙ-ЕПАЙП-БЛОК: потрібен Linux x86-64" >&2; exit 127;
}
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
finish() {
  local rc=$? f
  if ((rc)); then
    echo "ШИРОКИЙ-ЕПАЙП-ПРОВАЛ код=$rc" >&2
    for f in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 12 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap finish EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidepotikelf.lpr senswidepotikelf'; do
  read -r source name <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>"$TMP/$name.err" || {
      cat "$TMP/$name.build" "$TMP/$name.err" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 40s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generator.out"
SOURCE="$TMP/physical/09.sens"
EXPECTED="$TMP/physical/09.expected.sens"
test -s "$SOURCE" && test -s "$EXPECTED"
MODE=--скомпілювати-фізичний-потік
timeout 30s "$TMP/bin/senswidepotikelf" "$MODE" \
  <"$SOURCE" >"$TMP/reference.elf" 2>"$TMP/reference.err"
test -s "$TMP/reference.elf"
readelf -h "$TMP/reference.elf" >"$TMP/readelf.txt"
grep -Eq 'Type:[[:space:]]+DYN' "$TMP/readelf.txt"
grep -Fq 'Advanced Micro Devices X86-64' "$TMP/readelf.txt"
chmod 700 "$TMP/reference.elf"
timeout 5s "$TMP/reference.elf" >"$TMP/actual.sens" 2>"$TMP/machine.err"
test ! -s "$TMP/machine.err"
cmp "$EXPECTED" "$TMP/actual.sens"

# Bytes у stdin/stdout — власність child pipe; їх не слід декодувати
# як UTF-8/проєкцію D7. Вихідний ELF перевіряється повним порівнянням.
python3 - "$TMP/bin/senswidepotikelf" "$SOURCE" "$TMP/reference.elf" <<'PY'
import os
from pathlib import Path
import subprocess
import sys

compiler, source, expected = sys.argv[1:]
physical = Path(source).read_bytes()
elf = Path(expected).read_bytes()
argv = [compiler, '--скомпілювати-фізичний-потік']

def run(**kwargs):
    return subprocess.run(argv, input=physical, stderr=subprocess.PIPE,
                          timeout=30, check=False, **kwargs)

# Позитивний контроль: stdout під'єднаний до звичайного справжнього pipe.
ok = run(stdout=subprocess.PIPE)
assert ok.returncode == 0, (ok.returncode, ok.stderr)
assert ok.stdout == elf, (len(ok.stdout), len(elf))
assert b'ШИРОКИЙ-ПОТІК-ВІДМОВА:' not in ok.stderr

# 0 читачів ДО fork/exec: write гарантовано отримує SIGPIPE або EPIPE.
read_fd, write_fd = os.pipe()
os.close(read_fd)
try:
    broken = run(stdout=write_fd)
finally:
    os.close(write_fd)
assert broken.returncode != 0, (
    'НЕБЕЗПЕКА: повний ELF було помилково визнано записаним')
# Free Pascal може завершитися SIGPIPE або вивести host EPIPE-діагностику.
# Статус != 0 — перевірювана вимога; не прив'язуємося до libc/signal ABI.
assert broken.returncode not in (124, 137), broken.returncode

# Відхилення до компіляції не має права публікувати жоден байт ELF.
wrong = subprocess.run(argv, input=b'\xff', stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=30, check=False)
assert wrong.returncode == 2, (wrong.returncode, wrong.stderr)
assert wrong.stdout == b'', wrong.stdout[:32]
assert 'ШИРОКИЙ-ПОТІК-ВІДМОВА:'.encode() in wrong.stderr

# Окрема наступна компіляція після EPIPE і негативу має відновитися.
recovered = run(stdout=subprocess.PIPE)
assert recovered.returncode == 0, (recovered.returncode, recovered.stderr)
assert recovered.stdout == elf, (len(recovered.stdout), len(elf))
print('G6.179-EPІPE-ПЕРЕВІРЕНО pipe=1 no-reader=1 reject=1 recovered=1')
PY
echo 'G6.179-ШИРОКИЙ-ЕЛЬФ-ЕПАЙП-ГАРАЗД fpc=checked t5m=physical native=executed energy=NOT_MEASURED oracle=NOT_RUN'

# Власність та типи: SOURCE — borrowed immutable T5M; elf — owned bytes
# у Python; pipe FD закриває власник (parent) у finally, ОС прибирає child.
# 1) Чому stdout з нулем читачів — перевірка Linux, а не мовного закону?
# 2) Чому згенерований ELF потрібно реально виконати?
# 3) Чому збіг двох ELF не замінює незалежний SENS REPL?
# 4) Яким сигналом або errno ОС повідомляє про закритий pipe?
# 5) Чому енергоспоживання не можна вивести з exit code?
