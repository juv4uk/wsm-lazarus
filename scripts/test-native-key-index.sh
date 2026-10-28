#!/usr/bin/env bash
# G3.6 — реальний FPC доказ exact-key індексу нативного D3.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null 2>&1 || {
  echo 'ІНДЕКС-КЛЮЧІВ-БЛОК: Free Pascal відсутній' >&2
  exit 127
}
mkdir -p build/native-key-index/units build/native-key-index/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/native-key-index/units" \
  -FE"$ROOT/build/native-key-index/bin" \
  -otest-native-key-index "$ROOT/scripts/test-native-key-index.pas"
report=$("$ROOT/build/native-key-index/bin/test-native-key-index")
printf '%s\n' "$report"
[[ "$report" == *'ІНДЕКС-КЛЮЧІВ-ГАРАЗД ключів=32768'* ]] || {
  echo 'ІНДЕКС-КЛЮЧІВ-ПРОВАЛ: непідтверджені результати нативного тесту' >&2
  exit 1
}
echo 'ІНДЕКС-КЛЮЧІВ-ЗБІРКА-ГАРАЗД фізичний=FPC pinned=так semantics=не_змінено'
