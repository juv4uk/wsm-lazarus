#!/usr/bin/env bash
# Core1.3: справжній FPC живий виклик другого визначення і незалежний pinned SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
for cmd in fpc git timeout python3; do
  command -v "$cmd" >/dev/null || {
    echo "CORE1-ТРЕТЄ-БЛОК: немає $cmd" >&2; exit 127;
  }
done
./scripts/check-pin.sh
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN" || {
  echo 'CORE1-ТРЕТЄ-БЛОК: невірний pinned SHA' >&2; exit 1;
}
test -s external/sens/lib/core1.sens
test -s external/sens/lib/core1.lisp
cmp external/sens/lib/core1.sens sens-oracle/lib/core1.sens
cmp external/sens/lib/core1.lisp sens-oracle/lib/core1.lisp
test -x sens-oracle/target/debug/sens || {
  echo 'CORE1-ТРЕТЄ-БЛОК: upstream SENS не зібрано' >&2; exit 127;
}
mkdir -p build/m0.2/core1-third-units build/m0.2/core1-third-bin
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core1-third-units" \
  -FE"$ROOT/build/m0.2/core1-third-bin" -otest-core1-third \
  "$ROOT/scripts/test-core1-third.pas"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 60s build/m0.2/core1-third-bin/test-core1-third \
  "$ROOT/external/sens" "$ROOT" >"$TMP/fpc.stdout" 2>"$TMP/fpc.stderr"
grep -Fq 'CORE1-ТРЕТЄ-ЗАМИКАННЯ-ГАРАЗД' "$TMP/fpc.stdout"
grep -Fq 'GC=не-інтегровано' "$TMP/fpc.stdout"
grep -Fq '0 unfreed memory blocks' "$TMP/fpc.stderr"
cat "$TMP/fpc.stdout"
printf '(ядро1-третій-елемент (список так ні так))\n' > "$TMP/проба.lisp"
timeout 120s sens-oracle/target/debug/sens --t5m-files \
  sens-oracle/lib/core1.lisp "$TMP/проба.lisp" >"$TMP/oracle.out" 2>"$TMP/oracle.err" || {
    cat "$TMP/oracle.err" >&2
    echo 'CORE1-ТРЕТЄ-ОРАКУЛ-БЛОК: upstream не виконав Core1' >&2; exit 1;
  }
test ! -s "$TMP/oracle.err" || { cat "$TMP/oracle.err" >&2; exit 1; }
# (список так ні так) → третій = так → D1:1 у t5m view
test "$(tr -d '\r\n' <"$TMP/oracle.out")" = '1' || {
  cat "$TMP/oracle.out" >&2
  echo 'CORE1-ТРЕТЄ-ОРАКУЛ-ПРОВАЛ: очікувалося D1:1' >&2; exit 1;
}
echo 'CORE1-ТРЕТЄ-ОРАКУЛ-ГАРАЗД pinned=Contract12 D1:1=співпадає FPC=збирався'
