#!/usr/bin/env bash
# G6.77: справжні x86-64 TEST/SETE/MOVZX, exact D12→D1 та pinned REPL.
set -euo pipefail
trap 'echo "D12-НУЛЬ-ЗБІЙ рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'D12-НУЛЬ-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
FPC_BIN=$(printenv FPC || echo fpc)
for tool in "$FPC_BIN" cmp timeout readelf objdump dd grep git mktemp; do
  command -v "$tool" >/dev/null || { echo "D12-НУЛЬ-БЛОК: немає $tool" >&2; exit 127; }
done
BUILD="$ROOT/build/m0.2/d12zero"
mkdir -p "$BUILD/units" "$BUILD/bin"
for pair in 'scripts/test-elfd12zero.pas test-elfd12zero' \
            'src/sensd12zeroelf.lpr sensd12zeroelf'; do
  read -r source executable <<< "$pair"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$BUILD/units" -FE"$BUILD/bin" \
    "-o$executable" "$ROOT/$source"
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/physical"
timeout 30s "$BUILD/bin/test-elfd12zero" "$TMP/physical"
test -s "$TMP/physical/cases.tsv"
PASS=0
while IFS=$'\t' read -r label number bit; do
  test -n "$label"
  input="$TMP/physical/$label.sens"
  expected="$TMP/physical/$label.expected.sens"
  elf="$TMP/$label.elf"
  timeout 10s "$BUILD/bin/sensd12zeroelf" --нуль-D12 "$input" "$elf" \
    >"$TMP/$label.compile" 2>"$TMP/$label.compiler.err"
  test ! -s "$TMP/$label.compiler.err"
  grep -Fq 'machine=TEST_SETE_MOVZX output=D1' "$TMP/$label.compile"
  test -x "$elf"
  readelf -h "$elf" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN([[:space:]]|$)' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  dd if="$elf" of="$TMP/$label.instructions" bs=1 skip=120 count=80 status=none
  objdump -D -b binary -m i386:x86-64 "$TMP/$label.instructions" >"$TMP/$label.dis"
  grep -Eiq 'test.*%eax' "$TMP/$label.dis"
  grep -Eiq 'sete' "$TMP/$label.dis"
  grep -Eiq 'movz[bw]' "$TMP/$label.dis"
  timeout 5s "$elf" >"$TMP/$label.result.sens"
  cmp "$expected" "$TMP/$label.result.sens"
  timeout 10s "$BUILD/bin/sensd12zeroelf" --нуль-D12 "$input" \
    "$TMP/$label-again.elf" >/dev/null
  cmp "$elf" "$TMP/$label-again.elf"
  if [[ -n "$(printenv SENS_ORACLE_BIN || true)" ]]; then
    test -x "$SENS_ORACLE_BIN"
    test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
    printf '(нуль? %s)\n' "$number" >"$TMP/$label.lisp"
    timeout 60s "$SENS_ORACLE_BIN" "$TMP/$label.lisp" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.stderr"
    test ! -s "$TMP/$label.oracle.stderr"
    if [[ "$bit" = 1 ]]; then printf 'ТАК\n' >"$TMP/$label.expected.ukr"
    else printf 'НІ\n' >"$TMP/$label.expected.ukr"; fi
    cmp "$TMP/$label.oracle" "$TMP/$label.expected.ukr"
  fi
  PASS=$((PASS+1))
done <"$TMP/physical/cases.tsv"
test "$PASS" -eq 10

NEG=0
reject() {
  local target="$TMP/rejected-$NEG.elf"
  if timeout 12s "$BUILD/bin/sensd12zeroelf" "$@" "$target" \
    >"$TMP/partial.stdout" 2>"$TMP/negative.stderr"; then
    echo "D12-НУЛЬ-ВІДМОВА: недійсне джерело прийнято $NEG" >&2; exit 1
  fi
  test ! -e "$target"
  test ! -s "$TMP/partial.stdout"
  grep -Fq 'ЕЛЬФ-Д12-НУЛЬ-ВІДМОВА:' "$TMP/negative.stderr"
  NEG=$((NEG+1))
}
MODE=--нуль-D12
reject "$MODE" "$TMP/physical/wrong-d24.sens"
reject "$MODE" "$TMP/physical/wrong-d1.sens"
reject "$MODE" "$TMP/physical/wrong-d7.sens"
reject "$MODE" "$TMP/physical/two-atoms.sens"
reject "$MODE" "$TMP/physical/trailing.sens"
reject "$MODE" "$TMP/physical/corrupt.sens"
reject "$MODE" "$TMP/physical/empty.sens"
reject "$MODE" "$TMP/physical/fake.lisp"
reject "$MODE" "$TMP/physical/missing.sens"
reject --вигаданий "$TMP/physical/01.sens"
test "$NEG" -eq 10

cp "$TMP/01.elf" "$TMP/occupied.elf"
if timeout 12s "$BUILD/bin/sensd12zeroelf" "$MODE" \
    "$TMP/physical/02.sens" "$TMP/occupied.elf" \
    >"$TMP/occupied.stdout" 2>"$TMP/occupied.stderr"; then
  echo 'D12-НУЛЬ-ПОМИЛКА: ELF перезаписано' >&2; exit 1
fi
cmp "$TMP/01.elf" "$TMP/occupied.elf"
test ! -s "$TMP/occupied.stdout"
timeout 12s "$BUILD/bin/sensd12zeroelf" "$MODE" \
  "$TMP/physical/01.sens" "$TMP/recovery.elf" >/dev/null
timeout 5s "$TMP/recovery.elf" >"$TMP/recovery.sens"
cmp "$TMP/physical/01.expected.sens" "$TMP/recovery.sens"
echo "D12-НУЛЬ-ГАРАЗД фізичних=$PASS негативів=$NEG ELF64=PIE machine=TEST_SETE_MOVZX T5M=D1 енергія=НЕ-ВИМІРЯНО"
