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
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if ! LC_ALL=C.UTF-8 timeout 60 xvfb-run -a -s '-screen 0 1440x900x24' \
  "$GUI" --самоперевірка "$ROOT" "$CHILD" >"$TMP/out" 2>"$TMP/err"; then
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
