#!/usr/bin/env bash
# Нові LCL-вікно і самотест, чинна FPC лабораторія D7 v2 є oracle механізму.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-Д7-БЛОК: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-Д7-БЛОК: немає Xvfb' >&2; exit 127; }
./scripts/check-pin.sh
# Справжній FPC і pinned 190 позитивних D7 проєкцій + негативи.
timeout 180 bash ./scripts/test-d7text.sh
mkdir -p build/lcl-d7-laboratoriia/units
timeout 120 lazbuild --ws=gtk2 --build-all gui/sens-d7-laboratoriia.lpi
BIN="$ROOT/build/lcl-d7-laboratoriia/sens-d7-laboratoriia"
test -x "$BIN" || { echo 'LCL-Д7-БЛОК: немає бінарника' >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf 'Це 0() №Їґ' > "$TMP/текст.txt"
timeout 15 "$ROOT/build/m0.2/d7text/bin/sensd7text" --кодувати-укр "$ROOT" \
  "$TMP/текст.txt" "$TMP/текст.sens"
test -s "$TMP/текст.sens"
printf '\363' > "$TMP/брак.sens"
printf 'НЕЗМІННИЙ-ПОПЕРЕДНІЙ' > "$TMP/існує.sens"
cp "$TMP/існує.sens" "$TMP/контроль"
ln -s "$TMP/немає-цілі.sens" "$TMP/висяче-посилання.sens"
test -L "$TMP/висяче-посилання.sens"
LC_ALL=C.UTF-8 timeout 45 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка "$TMP/текст.sens" "$TMP/брак.sens" \
  "$TMP/новий.sens" "$TMP/існує.sens" "$TMP/після-помилки.sens" \
  "$TMP/висяче-посилання.sens" | tee "$TMP/звіт"
grep -F 'LCL-Д7-ЛАБОРАТОРІЯ-ГАРАЗД' "$TMP/звіт"
grep -F 'LCL-Д7-ЗАПИС-ГАРАЗД' "$TMP/звіт"
grep -F 'symlink=не-перезаписано атомарно=fpLink' "$TMP/звіт"
cmp "$TMP/текст.sens" "$TMP/новий.sens"
cmp "$TMP/контроль" "$TMP/існує.sens"
test ! -e "$TMP/після-помилки.sens"
test -L "$TMP/висяче-посилання.sens"
test ! -e "$TMP/немає-цілі.sens"
if find "$TMP" -maxdepth 1 -name "d7p*" | grep -q .; then
  echo "LCL-Д7-БЛОК: залишився тимчасовий файл D7" >&2; exit 1
fi
echo 'LCL-Д7-ЗБІРКА-ГАРАЗД FPC=реальний Lazarus=реальний pinned-D7=так'
