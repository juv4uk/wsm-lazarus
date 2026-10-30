#!/usr/bin/env bash
# Доказ реального фізичного D1/D3 виконання з коренями штатного GC.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v fpc >/dev/null || {
  echo 'CORE1-GC-БЛОК: потрібен реальний Free Pascal' >&2; exit 127;
}
./scripts/check-pin.sh
# Наявний real binary executor; не відключаємо його позитиви та негативи.
bash scripts/test-binaryexec.sh
mkdir -p build/m0.2/gcexecution-units build/m0.2/bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/gcexecution-units" \
  -FE"$ROOT/build/m0.2/bin" -otest-gcexecution \
  "$ROOT/scripts/test-gcexecution.pas"
OUTPUT=$(./build/m0.2/bin/test-gcexecution)
printf '%s\n' "$OUTPUT"
grep -F 'CORE1-GC-МЕЖА-ГАРАЗД' <<< "$OUTPUT"
grep -F 'Core1=НЕ_ВИКОНАНО GC-evaluator=НЕ_ІНТЕГРОВАНО' <<< "$OUTPUT"
echo 'CORE1-GC-ПЕРЕВІРКИ-ГАРАЗД FPC=3.2 real-executor=так штатний-GC=так'
