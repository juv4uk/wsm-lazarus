#!/usr/bin/env bash
# G5.35 — справжня Lazarus GTK2-вітрина до існуючого двійкового D3 процесу.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-D3-БЛОКЕР: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-D3-БЛОКЕР: немає Xvfb' >&2; exit 127; }
command -v timeout >/dev/null || { echo 'LCL-D3-БЛОКЕР: немає timeout' >&2; exit 127; }
./scripts/check-pin.sh
# Потрібні реальні pinned фізичні fixtures, а не вигаданий Lisp oracle.
timeout 180 bash ./scripts/test-potikd3.sh
mkdir -p build/lcl-d3-kanal/units
timeout 120 lazbuild --ws=gtk2 --build-all gui/d3-kanal.lpi
GUI="$ROOT/build/lcl-d3-kanal/d3-kanal"
CHILD="$ROOT/build/potikd3/bin/senspotikd3"
test -x "$GUI" && test -x "$CHILD"
# G5.51: реальна FPC-клієнтська збірка із перевірками діапазонів і
# пам'яті; контрольований FPC-процес псує ЛИШЕ приватний host wire.
# Дійсні D3 відповіді надходять тільки від уже зібраного senspotikd3.
FPC_BIN=${FPC:-fpc}
mkdir -p "$ROOT/build/d3wireclient/units" "$ROOT/build/d3wireclient/bin"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/d3wireclient/units" -FE"$ROOT/build/d3wireclient/bin" \
  -otest-d3wireclient "$ROOT/scripts/test-d3wireclient.pas"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 75 "$ROOT/build/d3wireclient/bin/test-d3wireclient" \
  "$CHILD" "$ROOT/external/sens" >"$TMP/wire-out" 2>"$TMP/wire-err" || {
  cat "$TMP/wire-out" >&2
  cat "$TMP/wire-err" >&2
  exit 1
}
cat "$TMP/wire-out"
grep -Fq 'D3-КАНАЛ-ОТРУЄННЯ-ГАРАЗД' "$TMP/wire-out"
if ! LC_ALL=C.UTF-8 timeout 60 xvfb-run -a -s '-screen 0 1440x900x24' \
  "$GUI" --самоперевірка "$ROOT/external/sens" "$CHILD" >"$TMP/out" 2>"$TMP/err"; then
  cat "$TMP/out" >&2
  cat "$TMP/err" >&2
  exit 1
fi
cat "$TMP/out"
cat "$TMP/err" >&2
grep -Fq 'LCL-D3-КАНАЛ-ГАРАЗД' "$TMP/out"
grep -Fq '1/4/64=побайтово late=форма2-слово2' "$TMP/out"
grep -Fq 'lisp=відхилено відновлення=так REPL/Core4=ні' "$TMP/out"
echo 'LCL-D3-КАНАЛ-CI-ГАРАЗД FPC=реальний Lazarus=GTK2 процес=один'
