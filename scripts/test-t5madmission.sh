#!/usr/bin/env bash
# Перевірка фізичного двійкового допуску; це не виконання законів SENS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FPC_BIN=$(printenv FPC || printf fpc)
command -v "$FPC_BIN" >/dev/null || {
  echo 'ДВІЙКОВИЙ-ДОПУСК-ПОМИЛКА: Free Pascal відсутній' >&2
  exit 127
}
./scripts/check-pin.sh
mkdir -p build/m0.2/t5madmission-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/t5madmission-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-t5madmission "$ROOT/scripts/test-t5madmission.pas"
./build/m0.2/bin/test-t5madmission
echo 'ПОТІК-D2-W192-CI-ГАРАЗД FPC=справжній T5M=stream physical-адреси=точні heaptrc=увімкнено'
