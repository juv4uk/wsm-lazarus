#!/usr/bin/env bash
# G1.25: дві ЗЛИТІ реалізації D7 мають однакові exact W7 та трит/байт map.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ПАРИТЕТ-Д7-БЛОК: немає FPC' >&2; exit 127;
}
mkdir -p build/d7-codec-parity/bin build/d7-codec-parity/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/d7-codec-parity/units" \
  -FE"$ROOT/build/d7-codec-parity/bin" \
  -otest-d7-codec-parity "$ROOT/scripts/test-d7-codec-parity.pas"
timeout 60 "$ROOT/build/d7-codec-parity/bin/test-d7-codec-parity" \
  2>&1 | tee build/d7-codec-parity/fpc-evidence.log
# FPC stdout іноді друкує UTF-8 маркер як '?' за C locale.
# Не послаблюємо gates: exit-code під pipefail і ОБОВ'ЯЗКОВІ числові свідки.
grep -Fq '95/95' build/d7-codec-parity/fpc-evidence.log
grep -Fq '4096' build/d7-codec-parity/fpc-evidence.log
grep -Fq '11' build/d7-codec-parity/fpc-evidence.log
grep -Fq '0 unfreed memory blocks' build/d7-codec-parity/fpc-evidence.log
if grep -Eq '[1-9][0-9]* unfreed memory blocks' \
   build/d7-codec-parity/fpc-evidence.log; then
  echo 'ПАРИТЕТ-Д7-БЛОК: виявлено витік' >&2
  exit 1
fi
echo 'ПАРИТЕТ-Д7-ФІЗИЧНИЙ-ДОКАЗ-ГАРАЗД 95/95 4096W7 pin=2c498b35af53c085450eac6f51b87facf7f9aa47'
