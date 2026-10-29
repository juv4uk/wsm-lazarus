#!/usr/bin/env bash
# G6.71: канонічний D12→D24, реальна машинна ADD, незалежний REPL oracle.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'Д24-ПРОСУВАННЯ-БЛОК: Linux x86-64' >&2; exit 127; }
FPC_BIN=$(printenv FPC || echo fpc)
for exe in "$FPC_BIN" timeout cmp readelf objdump dd od tr grep git; do
  command -v "$exe" >/dev/null || { echo "ВІДСУТНІЙ ІНСТРУМЕНТ: $exe" >&2; exit 127; }
done
UNIT="$ROOT/build/m0.2/d12-promote/units"
BIN="$ROOT/build/m0.2/d12-promote/bin"
mkdir -p "$UNIT" "$BIN"
for pair in "scripts/test-elfd12promote.pas test-elfd12promote" \
            "src/sensd12promoteelf.lpr sensd12promoteelf" \
            "src/senschyslo.lpr senschyslo"; do
  read -r source target <<< "$pair"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$UNIT" -FE"$BIN" "-o$target" "$ROOT/$source"
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/вхід"
timeout 30s "$BIN/test-elfd12promote" "$TMP/вхід"
PASS=0
MODE=--додати-розширено-D12
for row in '01:2047:1:2048' '02:-2048:-1:-2049' \
  '03:1800:450:2250' '04:-1500:-600:-2100' \
  '05:2047:2047:4094' '06:-2048:-2048:-4096' \
  '07:-1024:-1025:-2049'; do
  IFS=: read -r label left right expected <<< "$row"
  l="$TMP/вхід/$label-left.sens"
  r="$TMP/вхід/$label-right.sens"
  out="$TMP/$label.elf"
  timeout 12s "$BIN/sensd12promoteelf" "$MODE" "$l" "$r" "$out" >"$TMP/$label.compile"
  grep -Fq 'машина=ADD вихід=T5M' "$TMP/$label.compile"
  test -x "$out"
  readelf -h "$out" > "$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  # MOV EAX,imm32 має рівно 5 байтів; наступний opcode ADD EAX,imm32=05.
  opcode=$(dd if="$out" bs=1 skip=125 count=1 status=none | od -An -tu1 | tr -d ' \n')
  test "$opcode" = 5
  dd if="$out" of="$TMP/$label.instructions" bs=1 skip=120 count=25 status=none
  objdump -D -b binary -m i386:x86-64 "$TMP/$label.instructions" >"$TMP/$label.disassembly"
  grep -Eiq 'add.*%eax' "$TMP/$label.disassembly"
  timeout 5s "$out" > "$TMP/$label.result.sens"
  cmp "$TMP/вхід/$label-expected.sens" "$TMP/$label.result.sens"
  timeout 10s "$BIN/senschyslo" --в-укр D24 "$TMP/$label.result.sens" > "$TMP/$label.ukr"
  printf '%s\n' "$expected" > "$TMP/$label.expected.ukr"
  cmp "$TMP/$label.expected.ukr" "$TMP/$label.ukr"
  timeout 12s "$BIN/sensd12promoteelf" "$MODE" "$l" "$r" "$TMP/$label-again.elf" >/dev/null
  cmp "$out" "$TMP/$label-again.elf"
  if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
    printf '(додати %s %s)\n' "$left" "$right" > "$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      > "$TMP/$label.oracle" 2> "$TMP/$label.oracle.stderr"
    test ! -s "$TMP/$label.oracle.stderr"
    cmp "$TMP/$label.oracle" "$TMP/$label.ukr"
  fi
  PASS=$((PASS+1))
done
test "$PASS" -eq 7

NEG=0
reject() {
  local target="$TMP/rejected-$NEG.elf"
  if timeout 12s "$BIN/sensd12promoteelf" "$@" "$target" \
    >"$TMP/partial.stdout" 2>"$TMP/negative.stderr"; then
    echo "Д24-ПРОСУВАННЯ-ПОМИЛКА: невірний випадок $NEG прийнято" >&2; exit 1
  fi
  test ! -e "$target"
  test ! -s "$TMP/partial.stdout"
  grep -Fq 'ЕЛЬФ-Д24-ДОДАВАННЯ-ВІДМОВА:' "$TMP/negative.stderr"
  NEG=$((NEG+1))
}
reject "$MODE" "$TMP/вхід/fits-left.sens" "$TMP/вхід/fits-right.sens"
reject "$MODE" "$TMP/вхід/mixed-left.sens" "$TMP/вхід/mixed-right.sens"
reject "$MODE" "$TMP/вхід/invalid-d24.sens" "$TMP/вхід/01-right.sens"
reject "$MODE" "$TMP/вхід/invalid-d1.sens" "$TMP/вхід/01-right.sens"
reject "$MODE" "$TMP/вхід/invalid-d7.sens" "$TMP/вхід/01-right.sens"
reject "$MODE" "$TMP/вхід/corrupt.sens" "$TMP/вхід/01-right.sens"
reject "$MODE" "$TMP/вхід/empty.sens" "$TMP/вхід/01-right.sens"
cp "$TMP/вхід/01-left.sens" "$TMP/вхід/підроблений.lisp"
reject "$MODE" "$TMP/вхід/підроблений.lisp" "$TMP/вхід/01-right.sens"
reject --вигаданий "$TMP/вхід/01-left.sens" "$TMP/вхід/01-right.sens"
reject "$MODE" "$TMP/вхід/відсутній.sens" "$TMP/вхід/01-right.sens"
test "$NEG" -eq 10

# Наявна ціль зберігається, stdout відсутній, новий наступний ELF працює.
cp "$TMP/01.elf" "$TMP/зайнятий.elf"
if timeout 12s "$BIN/sensd12promoteelf" "$MODE" \
  "$TMP/вхід/02-left.sens" "$TMP/вхід/02-right.sens" "$TMP/зайнятий.elf" \
  >"$TMP/occupied.stdout" 2>"$TMP/occupied.stderr"; then
  echo 'Д24-ПРОСУВАННЯ-ПОМИЛКА: перезапис ELF' >&2; exit 1
fi
cmp "$TMP/01.elf" "$TMP/зайнятий.elf"
test ! -s "$TMP/occupied.stdout"
timeout 12s "$BIN/sensd12promoteelf" "$MODE" \
  "$TMP/вхід/02-left.sens" "$TMP/вхід/02-right.sens" "$TMP/відновлений.elf" >/dev/null
timeout 5s "$TMP/відновлений.elf" > "$TMP/відновлений.sens"
cmp "$TMP/вхід/02-expected.sens" "$TMP/відновлений.sens"
echo "Д24-ПРОСУВАННЯ-ГАРАЗД ELF=$PASS негативів=$NEG machine=ADD D24=T5M енергія=НЕ-ВИМІРЯНО"
