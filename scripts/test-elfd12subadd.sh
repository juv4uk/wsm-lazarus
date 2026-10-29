#!/usr/bin/env bash
# G6.83: РЕАЛЬНИЙ x86-64 SUB+ADD у ОДНОМУ ELF64; exact T5M результат.
set -euo pipefail
trap 'echo "D12-SUBADD-ПОМИЛКА рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'D12-SUBADD-БЛОК: лише Linux x86-64' >&2; exit 127;
}
for tool in fpc git timeout cmp readelf objdump dd od grep mktemp; do
  command -v "$tool" >/dev/null || {
    echo "D12-SUBADD-БЛОК: немає $tool" >&2; exit 127;
  }
done
ORACLE=$(printenv SENS_ORACLE_BIN || true)
[[ -n "$ORACLE" && -x "$ORACLE" ]] || {
  echo 'D12-SUBADD-БЛОК: незалежний SENS REPL обовʼязковий' >&2; exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/свідки"
FPC_BIN=$(printenv FPC || echo fpc)
for entry in \
  'src/sensd12subadd-elf.lpr sensd12subadd-elf' \
  'src/senschyslo.lpr senschyslo'; do
  read -r source executable <<< "$entry"
  if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$executable" \
    "$ROOT/$source" >"$TMP/$executable.build.out" 2>"$TMP/$executable.build.err"; then
    cat "$TMP/$executable.build.out" "$TMP/$executable.build.err" >&2
    exit 1
  fi
  test -x "$TMP/bin/$executable"
done
CLI="$TMP/bin/sensd12subadd-elf"
NUM="$TMP/bin/senschyslo"
MODE=--відняти-потім-додати-D12

# Числовий .lisp — лише укр-проєкція входу/оракула.
# Машинні operand/result файли завжди packed canonical T5M.
mint() {
  local value=$1 width=$2 dest=$3
  printf '%s\n' "$value" >"$dest.lisp"
  timeout 10s "$NUM" --з-укр "D$width" "$dest.lisp" "$dest.sens" \
    >"$TMP/mint.stdout"
  test ! -s "$TMP/mint.stdout"
  test -s "$dest.sens"
}
PASS=0
ORACLE_COUNT=0
# a b c: exact D12; проміжний (a-b) теж має лишатися D12,
# інакше цей вузький one-ELF backend обов'язково відхиляє.
for row in \
  '01:21:10:-3' '02:-7:7:14' '03:2047:0:-2047' \
  '04:-2048:0:2047' '05:-100:-200:-100' '06:0:0:0' \
  '07:31:42:11' '08:-1000:1000:1' '09:128:100:7' \
  '10:400:100:500' '11:-500:-700:-300' '12:2047:2047:-2048'; do
  IFS=: read -r label a b c <<< "$row"
  mint "$a" 12 "$TMP/свідки/$label-a"
  mint "$b" 12 "$TMP/свідки/$label-b"
  mint "$c" 12 "$TMP/свідки/$label-c"
  timeout 15s "$CLI" "$MODE" \
    "$TMP/свідки/$label-a.sens" \
    "$TMP/свідки/$label-b.sens" \
    "$TMP/свідки/$label-c.sens" "$TMP/$label.elf" \
    >"$TMP/$label.publish" 2>"$TMP/$label.err"
  test ! -s "$TMP/$label.err"
  grep -Fq 'D12-SUBADD-ОДИН-ELF-ГОТОВО' "$TMP/$label.publish"
  test -x "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" >"$TMP/$label.header"
  grep -Eq 'Type:.*DYN' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"

  # Точні 15 байтів прологу: MOV imm32; SUB imm32; ADD imm32.
  # Не приймаємо mere disassembly збіг у прикінцевій T5M таблиці.
  header_code=$(dd if="$TMP/$label.elf" bs=1 skip=120 count=15 status=none | od -An -tx1 | tr -d ' \n')
  [[ "$header_code" =~ ^b8[0-9a-f]{8}2d[0-9a-f]{8}05[0-9a-f]{8}$ ]]
  dd if="$TMP/$label.elf" bs=1 skip=120 of="$TMP/$label.code" status=none
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$label.code" \
    >"$TMP/$label.dis"
  grep -Eiq 'sub[[:space:]]+eax,' "$TMP/$label.dis"
  grep -Eiq 'add[[:space:]]+eax,' "$TMP/$label.dis"
  timeout 5s "$TMP/$label.elf" >"$TMP/$label.sens"
  test -s "$TMP/$label.sens"

  # Єдина семантична влада: INDEPENDENT pinned upstream SENS.
  printf '(додати (відняти %s %s) %s)\n' "$a" "$b" "$c" \
    >"$TMP/$label.oracle.lisp"
  timeout 60s "$ORACLE" "$TMP/$label.oracle.lisp" \
    >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"
  test ! -s "$TMP/$label.oracle.err"
  timeout 10s "$NUM" --в-укр D12 "$TMP/$label.sens" \
    >"$TMP/$label.machine.ukr"
  cmp "$TMP/$label.oracle" "$TMP/$label.machine.ukr"
  # Другий доказ: oracle-проєкція карбується до ФІЗИЧНОГО T5M,
  # і реальна машина збігається з нею байт за байтом.
  timeout 10s "$NUM" --з-укр D12 \
    "$TMP/$label.oracle" "$TMP/$label.expected.sens" \
    >"$TMP/$label.expected.mint"
  test ! -s "$TMP/$label.expected.mint"
  cmp "$TMP/$label.expected.sens" "$TMP/$label.sens"
  PASS=$((PASS+1)); ORACLE_COUNT=$((ORACLE_COUNT+1))
done
test "$PASS" -eq 12 && test "$ORACLE_COUNT" -eq 12
# Байтовий детермінізм одного й того ж machine AOT.
timeout 15s "$CLI" "$MODE" \
  "$TMP/свідки/01-a.sens" "$TMP/свідки/01-b.sens" \
  "$TMP/свідки/01-c.sens" "$TMP/repeat.elf" >"$TMP/repeat.out"
cmp "$TMP/01.elf" "$TMP/repeat.elf"
timeout 5s "$TMP/repeat.elf" >"$TMP/repeat.sens"
cmp "$TMP/01.sens" "$TMP/repeat.sens"

NEG=0
reject() {
  local label=$1; shift
  local target="$TMP/denied-$label.elf" code=0
  timeout 15s "$CLI" "$@" "$target" \
    >"$TMP/$label.denied.out" 2>"$TMP/$label.denied.err" || code=$?
  test "$code" -ne 0 && test "$code" -ne 124
  test ! -e "$target"
  test ! -s "$TMP/$label.denied.out"
  grep -Fq 'D12-SUBADD-ОДИН-ELF-ВІДМОВА:' "$TMP/$label.denied.err"
  NEG=$((NEG+1))
}
mint 2047 12 "$TMP/overflow-up"
mint -1 12 "$TMP/minus-one"
mint -2048 12 "$TMP/overflow-down"
mint 1 12 "$TMP/one"
mint 0 12 "$TMP/zero"
mint 1 24 "$TMP/d24"
printf '\377' >"$TMP/corrupt.sens"
printf '(відняти 7 -7)\n' >"$TMP/fake.lisp"
reject sub-upper "$MODE" "$TMP/overflow-up.sens" "$TMP/minus-one.sens" "$TMP/zero.sens"
reject sub-lower "$MODE" "$TMP/overflow-down.sens" "$TMP/one.sens" "$TMP/zero.sens"
reject add-upper "$MODE" "$TMP/overflow-up.sens" "$TMP/zero.sens" "$TMP/one.sens"
reject add-lower "$MODE" "$TMP/overflow-down.sens" "$TMP/zero.sens" "$TMP/minus-one.sens"
reject d24 "$MODE" "$TMP/d24.sens" "$TMP/zero.sens" "$TMP/zero.sens"
reject corrupt "$MODE" "$TMP/corrupt.sens" "$TMP/zero.sens" "$TMP/zero.sens"
reject projection "$MODE" "$TMP/fake.lisp" "$TMP/zero.sens" "$TMP/zero.sens"
reject missing "$MODE" "$TMP/missing.sens" "$TMP/zero.sens" "$TMP/zero.sens"
reject mode --невідомий-D12 "$TMP/zero.sens" "$TMP/zero.sens" "$TMP/zero.sens"
test "$NEG" -eq 9
cp "$TMP/01.elf" "$TMP/occupied.elf"
code=0
timeout 15s "$CLI" "$MODE" "$TMP/свідки/01-a.sens" \
  "$TMP/свідки/01-b.sens" "$TMP/свідки/01-c.sens" \
  "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || code=$?
test "$code" -ne 0 && test ! -s "$TMP/occupied.out"
cmp "$TMP/01.elf" "$TMP/occupied.elf"
echo "D12-SUBADD-ОДИН-ELF-ГАРАЗД ELF=$PASS pinned-SENS=$ORACLE_COUNT негативів=$NEG машинні=SUB,ADD фізичний=T5M no-clobber=так енергія=НЕ-ВИМІРЯНО"
