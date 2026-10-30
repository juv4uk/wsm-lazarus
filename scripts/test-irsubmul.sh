#!/usr/bin/env bash
# G6.170 — один canonical nested .sens → verified WideIR → machine SUB+IMUL.
# Справжній pinned SENS виконує ТОЙ САМИЙ двійковий файл як oracle.
set -Eeuo pipefail
trap 'rc=$?; echo "D5-ВКЛАДЕНЕ-ELF-ПОМИЛКА code=$rc рядок=$LINENO команда=$BASH_COMMAND" >&2' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo "D5-ВКЛАДЕНЕ-БЛОК: лише Linux x86-64" >&2; exit 127;
}
for name in timeout fpc readelf objdump cmp grep mktemp; do
  command -v "$name" >/dev/null || {
    echo "D5-ВКЛАДЕНЕ-БЛОК: немає $name" >&2; exit 127;
  }
done
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || exit 127
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  test -x "$SENS_ORACLE_BIN"
  test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/cases"
for entry in \
 'scripts/test-irsubmul.pas test-irsubmul' \
 'src/sensirsubmulelf.lpr sensirsubmulelf' \
 'src/senschyslo.lpr senschyslo'; do
  read -r source filename <<<"$entry"
  if ! timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
     -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$filename" \
     "$ROOT/$source" >"$TMP/$filename.build.out" 2>"$TMP/$filename.build.err"; then
    cat "$TMP/$filename.build.out" "$TMP/$filename.build.err" >&2; exit 1
  fi
  test -x "$TMP/bin/$filename"
done
timeout 180s "$TMP/bin/test-irsubmul" external/sens "$TMP/cases" \
  >"$TMP/matrix.tsv" 2>"$TMP/fixtures.err"
if ! grep -Fq 'D5-SUB-IMUL-СВІДКИ-ГАРАЗД ELF=12 негативів=15' "$TMP/fixtures.err"; then
  echo 'D5-ВКЛАДЕНЕ-БЛОК: реальний stderr генератора:' >&2
  cat "$TMP/fixtures.err" >&2
  exit 1
fi
test "$(wc -l < "$TMP/matrix.tsv")" -eq 12
CLI="$TMP/bin/sensirsubmulelf"
PASS=0
ORACLE=0
WIDE=0
while IFS=$'\t' read -r label a b c width; do
  [[ "$width" == 12 || "$width" == 24 ]]
  timeout 15s "$CLI" --компілювати-вкладене-D5 \
    "$TMP/cases/$label.sens" "$TMP/$label.elf" \
    >"$TMP/status.out" 2>"$TMP/compiler.err"
  test ! -s "$TMP/compiler.err"
  grep -Fq 'D5-ВІДНЯТИ-МНОЖИТИ-ELF-ГОТОВО дії=SUB,IMUL' "$TMP/status.out"
  test -x "$TMP/$label.elf"
  cmp "$TMP/cases/$label.elf" "$TMP/$label.elf"
  readelf -h "$TMP/$label.elf" >"$TMP/$label.header"
  grep -Eq 'Type:.*DYN' "$TMP/$label.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$label.header"
  tail -c +121 "$TMP/$label.elf" >"$TMP/$label.code"
  objdump -D -b binary -m i386:x86-64 -M intel "$TMP/$label.code" \
    >"$TMP/$label.dis"
  grep -Eiq 'add[[:space:]]+eax,' "$TMP/$label.dis"
  grep -Eiq 'imul[[:space:]]+eax,' "$TMP/$label.dis"
  timeout 5s "$TMP/$label.elf" >"$TMP/$label.actual.sens"
  cmp "$TMP/cases/$label-expected.sens" "$TMP/$label.actual.sens"
  if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
    # Same packed canonical D2 source: no D24-default .lisp conversion.
    if ! timeout 60s "$SENS_ORACLE_BIN" "$TMP/cases/$label.sens" \
      >"$TMP/$label.oracle" 2>"$TMP/$label.oracle.err"; then
      echo "D5-SUB-IMUL-ОРАКУЛ-ВІДМОВА форма=$label a=$a b=$b c=$c" >&2
      cat "$TMP/$label.oracle.err" >&2
      exit 1
    fi
    if [[ -s "$TMP/$label.oracle.err" ]]; then
      echo "D5-SUB-IMUL-ОРАКУЛ-STDERR форма=$label" >&2
      cat "$TMP/$label.oracle.err" >&2
      exit 1
    fi
    "$TMP/bin/senschyslo" --в-укр "D$width" \
      "$TMP/$label.actual.sens" >"$TMP/$label.ukr"
    if ! cmp "$TMP/$label.ukr" "$TMP/$label.oracle"; then
      echo "D5-SUB-IMUL-ОРАКУЛ-РОЗБІЖНІСТЬ форма=$label" >&2
      cat "$TMP/$label.oracle" >&2
      exit 1
    fi
    ORACLE=$((ORACLE+1))
  fi
  if [[ "$width" == 24 ]]; then WIDE=$((WIDE+1)); fi
  PASS=$((PASS+1))
done <"$TMP/matrix.tsv"
test "$PASS" -eq 12 && test "$WIDE" -ge 2
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then test "$ORACLE" -eq 12; fi
# Два незалежні проходи компіляції дають байт-в-байт однаковий ELF.
timeout 15s "$CLI" --компілювати-вкладене-D5 "$TMP/cases/03.sens" \
  "$TMP/03-repeated.elf" >"$TMP/repeated.out"
cmp "$TMP/03.elf" "$TMP/03-repeated.elf"
NEG=0
reject() {
  local label=$1; shift
  local rc=0
  timeout 15s "$CLI" "$@" "$TMP/rejected-$NEG.elf" \
    >"$TMP/rejected.out" 2>"$TMP/rejected.err" || rc=$?
  test "$rc" -ne 0 && test "$rc" -ne 124
  test ! -e "$TMP/rejected-$NEG.elf" && test ! -s "$TMP/rejected.out"
  grep -Fq 'D5-ВІДНЯТИ-МНОЖИТИ-ELF-ВІДМОВА:' "$TMP/rejected.err"
  NEG=$((NEG+1))
}
for case in 'голий-атом' 'чужа-зовнішня-голова' \
  'чужа-вкладена-голова' 'плоска-форма' 'переставлені-аргументи' \
  'мало-аргументів' 'зайвий-аргумент' 'заміна-на-D1' \
  'заміна-на-D7' 'заміна-на-D24' 'порожній-D3' 'другий-корінь' \
  'пара-замість-списку' 'переповнення-різниці' 'пошкоджений-T5M'; do
  reject "$case" --компілювати-вкладене-D5 "$TMP/cases/bad-$case.sens"
done
test "$NEG" -eq 15
reject empty --компілювати-вкладене-D5 "$TMP/cases/empty.sens"
reject lisp --компілювати-вкладене-D5 "$TMP/cases/fake.lisp"
reject missing --компілювати-вкладене-D5 "$TMP/cases/absent.sens"
reject mode --хибний-режим "$TMP/cases/01.sens"
test "$NEG" -eq 19
cp "$TMP/01.elf" "$TMP/occupied.elf"
rc=0
timeout 15s "$CLI" --компілювати-вкладене-D5 "$TMP/cases/02.sens" \
  "$TMP/occupied.elf" >"$TMP/occupied.out" 2>"$TMP/occupied.err" || rc=$?
test "$rc" -ne 0 && test ! -s "$TMP/occupied.out"
cmp "$TMP/occupied.elf" "$TMP/01.elf"
NEG=$((NEG+1))
ln -s "$TMP/absent.elf" "$TMP/dangling.elf"
rc=0
timeout 15s "$CLI" --компілювати-вкладене-D5 "$TMP/cases/02.sens" \
  "$TMP/dangling.elf" >"$TMP/dangling.out" 2>"$TMP/dangling.err" || rc=$?
test "$rc" -ne 0 && test -L "$TMP/dangling.elf"
test ! -e "$TMP/absent.elf" && test ! -s "$TMP/dangling.out"
NEG=$((NEG+1))
test "$NEG" -eq 21
timeout 15s "$CLI" --компілювати-вкладене-D5 \
  "$TMP/cases/02.sens" "$TMP/after-negative.elf" >"$TMP/after.out"
timeout 5s "$TMP/after-negative.elf" >"$TMP/after.sens"
cmp "$TMP/after.sens" "$TMP/cases/02-expected.sens"
echo "D5-SUB-IMUL-ELF-ГАРАЗД exact-WideIR=так ELF=$PASS wide-D24=$WIDE negatives=$NEG pinned-oracle=$ORACLE machine=SUB,IMUL T5M=точний energy=НЕ_ВИМІРЯНО"
