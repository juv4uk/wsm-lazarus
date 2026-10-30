#!/usr/bin/env bash
# G1.21: порівняти справжній Free Pascal transport з pinned Python SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v python3 >/dev/null
command -v git >/dev/null

# Файл upstream може не належати до 28 sparse-файлів.
# Дістаємо за pinned gitlink, НЕ з main/HEAD незафіксованого SENS.
PIN=2c498b35af53c085450eac6f51b87facf7f9aa47
BLOB=e8b92ced6fb1b8d7c18ab397ed2a1a00432e923e
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
timeout 75s git -C external/sens show "$PIN:scripts/sens_t5_t5m_codec.py" \
  > "$TEMP/sens_t5_t5m_codec.py"
test "$(git hash-object "$TEMP/sens_t5_t5m_codec.py")" = "$BLOB" || {
  echo 'Т5М-UPSTREAM-ПАРИТЕТ-БЛОК: upstream codec blob SHA не збігається' >&2
  exit 1
}

mkdir -p build/m0.2/t5m-upstream/units build/m0.2/t5m-upstream/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/t5m-upstream/units" \
  -FE"$ROOT/build/m0.2/t5m-upstream/bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"
timeout 150s python3 -B "$ROOT/scripts/test-t5m-upstream-parity.py" \
  --oracle "$TEMP/sens_t5_t5m_codec.py" \
  --cli "$ROOT/build/m0.2/t5m-upstream/bin/senst5m"
