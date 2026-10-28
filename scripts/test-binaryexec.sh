#!/usr/bin/env bash
# Фізичний FPC-тест підмножини: .sens T5M/D2 -> чинний D3-виконавець.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null 2>&1 || {
  echo 'ДВІЙКОВЕ-ВИКОНАННЯ-БЛОК: не знайдено Free Pascal' >&2
  exit 127
}
mkdir -p build/m0.2/binaryexec-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/binaryexec-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-binaryexec "$ROOT/scripts/test-binaryexec.pas"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/binaryexec-units" -FE"$ROOT/build/m0.2/bin" \
  -osensvykon "$ROOT/src/sensvykon.lpr"
./build/m0.2/bin/test-binaryexec
result=$(./build/m0.2/bin/sensvykon --виконати build/m0.2/binaryexec-valid.sens)
[[ "$result" == '(1)' ]] || { echo "ДВІЙКОВИЙ-КЛІ-ПОМИЛКА: $result" >&2; exit 1; }
if ./build/m0.2/bin/sensvykon --виконати build/m0.2/binaryexec-invalid.sens \
   >build/m0.2/binaryexec-invalid.out 2>build/m0.2/binaryexec-invalid.err; then
  echo 'ДВІЙКОВИЙ-КЛІ-ПОМИЛКА: непідтверджена цитата прийнята' >&2
  exit 1
fi
[[ ! -s build/m0.2/binaryexec-invalid.out ]] || {
  echo 'ДВІЙКОВИЙ-КЛІ-ПОМИЛКА: частковий stdout при помилці' >&2; exit 1;
}
grep -q 'слово=2' build/m0.2/binaryexec-invalid.err || {
  cat build/m0.2/binaryexec-invalid.err >&2; exit 1;
}
echo 'ДВІЙКОВИЙ-КЛІ-ОК фізичний=.sens вихід=тільки_після_перевірки'
