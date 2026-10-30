#!/usr/bin/env bash
# Core1.2: справжній FPC живий виклик і незалежний pinned SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
for cmd in fpc git timeout python3; do
  command -v "$cmd" >/dev/null || {
    echo "CORE1-ПЕРШЕ-БЛОК: немає $cmd" >&2; exit 127;
  }
done
./scripts/check-pin.sh
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo 'CORE1-ПЕРШЕ-БЛОК: невірний pinned SHA' >&2; exit 1;
}
test -s external/sens/lib/core1.sens
test -s external/sens/lib/core1.lisp
# Точний byte-for-byte збіг між матеріалізованим canonical gitlink
# і незалежним GitHub checkout того самого SHA: без shadow source.
cmp external/sens/lib/core1.sens sens-oracle/lib/core1.sens
cmp external/sens/lib/core1.lisp sens-oracle/lib/core1.lisp
test -x sens-oracle/target/debug/sens || {
  echo 'CORE1-ПЕРШЕ-БЛОК: upstream SENS не зібрано' >&2; exit 127;
}
mkdir -p build/m0.2/core1-first-units build/m0.2/core1-first-bin
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core1-first-units" \
  -FE"$ROOT/build/m0.2/core1-first-bin" -otest-core1-first \
  "$ROOT/scripts/test-core1-first.pas"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 60s build/m0.2/core1-first-bin/test-core1-first \
  "$ROOT/external/sens" "$ROOT" >"$TMP/fpc.stdout" 2>"$TMP/fpc.stderr"
grep -Fq 'CORE1-ПЕРШЕ-ЗАМИКАННЯ-ГАРАЗД перевірок=1134' "$TMP/fpc.stdout"
grep -Fq 'GC=не-інтегровано' "$TMP/fpc.stdout"
grep -Fq '0 unfreed memory blocks' "$TMP/fpc.stderr"
cat "$TMP/fpc.stdout"
# Повна кількість: попередні 14 + (512 × 2 позитиви) +
# (16 × [4 негативи + 2 recovery-перевірки]) = 1134.
# Перший Core1 виконувався в одному об'єкті; це НЕ GC-інтеграція.
# Незалежний upstream виконує той самий ПЕРШИЙ визначений в pinned
# core1.lisp виклик у РЕАЛЬНОМУ CLI. Проєкція -- лише спосіб передати
# тестовий виклик; закон та результат належать upstream SENS.
printf '(ядро1-другий-елемент (список так ні так))\n' > "$TMP/проба.lisp"
timeout 120s sens-oracle/target/debug/sens --t5m-files \
  sens-oracle/lib/core1.lisp "$TMP/проба.lisp" >"$TMP/oracle.out" 2>"$TMP/oracle.err" || {
    cat "$TMP/oracle.err" >&2
    echo 'CORE1-ПЕРШЕ-ОРАКУЛ-БЛОК: upstream не виконав Core1' >&2; exit 1;
  }
test ! -s "$TMP/oracle.err" || { cat "$TMP/oracle.err" >&2; exit 1; }
test "$(tr -d '\r\n' <"$TMP/oracle.out")" = '0' || {
  cat "$TMP/oracle.out" >&2
  echo 'CORE1-ПЕРШЕ-ОРАКУЛ-ПРОВАЛ: очікувалося D1:0' >&2; exit 1;
}
echo 'CORE1-ПЕРШЕ-ОРАКУЛ-ГАРАЗД pinned=Contract12 D1:0=співпадає FPC=збирався'
