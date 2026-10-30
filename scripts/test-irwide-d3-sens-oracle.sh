#!/usr/bin/env bash
# G6.205: незалежний pinned SENS CLI проти фізичного D3→WideIR→ELF64.
# Вхід: borrowed canonical .sens у тимчасовому каталозі; власник tmp — цей shell.
# Результат: 6 порівнянь REPL oracle + 6 виконуваних ELF, 3 негативні перевірки.
# У жодному місці немає виводу SENS-закону з назви чи English dispatch.
# 1. Чому source та machine-result повинні йти через той самий pinned SENS?
# 2. Навіщо перевіряти точні packed .sens байти перед oracle?
# 3. Чому незалежний oracle НЕ можна замінити internal-D3 Pascal?
# 4. Чому stderr/exit/pin перевіряємо окремо від stdout?
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc git timeout cmp readelf mktemp chmod grep; do
  command -v "$tool" >/dev/null || { echo "Д3-ОРАКУЛ-БЛОК: немає $tool" >&2; exit 127; }
done
test "$(uname -s)" = Linux && test "$(uname -m)" = x86_64 || {
  echo 'Д3-ОРАКУЛ-БЛОК: тільки Linux x86-64' >&2; exit 127;
}
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN" || {
  echo 'Д3-ОРАКУЛ-БЛОК: pinned root не збігається' >&2; exit 1;
}
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo 'Д3-ОРАКУЛ-БЛОК: незалежний SENS не на pinned SHA' >&2; exit 1;
}
ORACLE=$(printenv SENS_ORACLE_BIN || true)
test -n "$ORACLE" || { echo 'Д3-ОРАКУЛ-БЛОК: потрібен SENS_ORACLE_BIN' >&2; exit 127; }
case "$ORACLE" in /*) ;; *) ORACLE="$ROOT/$ORACLE";; esac
test -x "$ORACLE" || { echo 'Д3-ОРАКУЛ-БЛОК: pinned oracle не виконуваний' >&2; exit 127; }
TMP=$(mktemp -d)
cleanup() {
  local rc=$?
  if test "$rc" -ne 0; then
    echo "Д3-ОРАКУЛ-ПРОВАЛ rc=$rc" >&2
    for f in "$TMP"/*.err "$TMP"/*.build; do
      test ! -s "$f" || { echo "--- $f" >&2; tail -n 15 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/physical"
FPC_BIN=$(printenv FPC || true)
test -n "$FPC_BIN" || FPC_BIN=fpc
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-irwide-d3-oracle "$ROOT/scripts/test-irwide-d3-elf.pas" \
  >"$TMP/fpc.build" 2>"$TMP/fpc.err"
test -x "$TMP/bin/test-irwide-d3-oracle"
timeout 45s "$TMP/bin/test-irwide-d3-oracle" \
  "$ROOT/external/sens" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fxq 'G6.168-WIDE-D3-ELF-OK positives=6 negatives=10 oracle=INTERNAL-D3 energy=NOT-MEASURED' \
  "$TMP/generator.out"

COUNT=0
for label in \
    цитата-д7 цитата-д1 рівність-ні рівність-так \
    перше-сполучення решта-сполучення; do
  SOURCE="$TMP/physical/$label.sens"
  EXPECTED="$TMP/physical/$label.expected.sens"
  ELF="$TMP/physical/$label.elf"
  test -s "$SOURCE" && test -s "$EXPECTED" && test -s "$ELF"
  readelf -h "$ELF" >"$TMP/$label.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$label.header"
  chmod u+x "$ELF"
  timeout 10s "$ELF" >"$TMP/$label.machine.sens" 2>"$TMP/$label.machine.err"
  test ! -s "$TMP/$label.machine.err"
  cmp "$EXPECTED" "$TMP/$label.machine.sens"
  # Незалежна SENS-машина виконує як вихідну фізичну форму, так і
  # машинний фізичний результат. Порівнюється її ПОВНИЙ stdout, а не
  # власноручна Pascal/English/decimal проєкція відповіді.
  timeout 45s "$ORACLE" "$SOURCE" \
    >"$TMP/$label.source.oracle" 2>"$TMP/$label.source.err"
  timeout 45s "$ORACLE" "$TMP/$label.machine.sens" \
    >"$TMP/$label.machine.oracle" 2>"$TMP/$label.result.err"
  test ! -s "$TMP/$label.source.err" && test ! -s "$TMP/$label.result.err"
  test -s "$TMP/$label.source.oracle" && test -s "$TMP/$label.machine.oracle"
  cmp "$TMP/$label.source.oracle" "$TMP/$label.machine.oracle"
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 6

# Негативи: незалежне виконання різних D1 значень не може мати один stdout,
# і навмисно підмінений результат не повинен пройти навіть за валідного T5M.
! cmp -s "$TMP/рівність-так.source.oracle" "$TMP/рівність-ні.source.oracle"
! cmp -s "$TMP/рівність-так.source.oracle" "$TMP/рівність-ні.machine.oracle"
! cmp -s "$TMP/цитата-д7.source.oracle" "$TMP/цитата-д1.source.oracle"
printf '\377' >"$TMP/corrupt.sens"
RC=0
timeout 45s "$ORACLE" "$TMP/corrupt.sens" \
  >"$TMP/corrupt.out" 2>"$TMP/corrupt.err" || RC=$?
test "$RC" -ne 0 && test ! -s "$TMP/corrupt.out" && test -s "$TMP/corrupt.err"

echo "Д3-НЕЗАЛЕЖНИЙ-SENS-ГОТОВО oracle=6 native=6 negatives=4 pin=$PIN energy=NOT-MEASURED"
