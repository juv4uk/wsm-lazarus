#!/usr/bin/env bash
# G5.35 — реальний FPC + Lazarus GTK2 постійний D3 PID з канонічним T5M.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-D3-КАНАЛ-БЛОК: потрібен Lazarus' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-D3-КАНАЛ-БЛОК: потрібен Xvfb' >&2; exit 127; }
command -v timeout >/dev/null || { echo 'LCL-D3-КАНАЛ-БЛОК: потрібен timeout' >&2; exit 127; }
./scripts/check-pin.sh
# Усі негативні G3.17, G3.19, G5.34 залишені повністю активними.
timeout 180 bash ./scripts/test-potikd3.sh
mkdir -p build/lcl-d3-postiinyi-kanal/units
timeout 120 lazbuild --ws=gtk2 --build-all gui/d3-postiinyi-kanal.lpi
GUI="$ROOT/build/lcl-d3-postiinyi-kanal/d3-postiinyi-kanal"
CHILD="$ROOT/build/potikd3/bin/senspotikd3"
FIX="$ROOT/build/paketd3-cli/fixtures"
test -x "$GUI" && test -x "$CHILD"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LC_ALL=C.UTF-8 timeout 55 xvfb-run -a -s '-screen 0 1440x900x24' \
  "$GUI" --самоперевірка "$ROOT/external/sens" "$CHILD" "$FIX" >"$TMP/out" 2>"$TMP/err" || {
  cat "$TMP/out" >&2; cat "$TMP/err" >&2; exit 1;
}
cat "$TMP/out"
cat "$TMP/err" >&2
grep -Fq 'LCL-D3-ПОСТІЙНИЙ-КАНАЛ-ГАРАЗД Lazarus=GTK2 FPC=справжній PID=незмінний' "$TMP/out"
grep -Fq 'LCL-D3-ПОМИЛКИ-ГАРАЗД пізня-форма=2-слово=2 stale=відсутній' "$TMP/out"
grep -Fq 'lisp=відхилено відновлення=так Core4/REPL=НЕ-ДОВЕДЕНО' "$TMP/out"
echo 'LCL-D3-КАНАЛ-CI-ГАРАЗД фізичний-T5M=побайтовий Lazarus=реальний PID=один'
