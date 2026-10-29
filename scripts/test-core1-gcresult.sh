#!/usr/bin/env bash
# G3.45: реальний FPC + штатний GC + справжній upstream SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc git timeout python3 cmp grep; do
  command -v "$tool" >/dev/null || {
    echo "CORE1-GC-БЛОК: немає $tool" >&2; exit 127;
  }
done
./scripts/check-pin.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
test "$(git -C sens-oracle rev-parse HEAD)" = "$PIN"
test -x sens-oracle/target/debug/sens || {
  echo 'CORE1-GC-БЛОК: немає незалежного SENS' >&2; exit 127;
}
cmp external/sens/lib/core1.sens sens-oracle/lib/core1.sens
cmp external/sens/lib/core1.lisp sens-oracle/lib/core1.lisp
# Чинні FPC GC і незалежний upstream Core1 свідки залишаються активні.
timeout 240s bash scripts/test-gcclosure.sh
timeout 240s bash scripts/test-core1-first.sh
mkdir -p build/m0.2/core1-gcresult-units build/m0.2/core1-gcresult-bin
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core1-gcresult-units" \
  -FE"$ROOT/build/m0.2/core1-gcresult-bin" -otest-core1-gcresult \
  "$ROOT/scripts/test-core1-gcresult.pas"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 120s build/m0.2/core1-gcresult-bin/test-core1-gcresult \
  "$ROOT/external/sens" "$ROOT" >"$TMP/out" 2>"$TMP/err"
grep -Fq 'CORE1-GC-РЕЗУЛЬТАТ-ГАРАЗД перевірок=' "$TMP/out"
grep -Fq 'викликів=256 GC=wsm.gc корінь=захоплений' "$TMP/out"
grep -Fq '0 unfreed memory blocks' "$TMP/err"
cat "$TMP/out"
echo 'CORE1-GC-МЕЖА: фізичні результати=GC; private evaluator heap=поза-GC; REPL=не-повний; metadata tickets=ростуть'
