#!/usr/bin/env bash
# G3.39: реальне Lazarus/GTK2 вікно з точними числами D12–D192.
# Відображення НЕ надає SENS законів і не виконує арифметики.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for bin in fpc lazbuild xvfb-run timeout python3; do
  command -v "$bin" >/dev/null || { echo "LCL-ЧИСЛА-БЛОК: бракує $bin" >&2; exit 127; }
done
./scripts/check-pin.sh
# Обов'язкові попередні механічні тести. Вони збирають checked FPC.
timeout 180s bash scripts/test-numericplane.sh
timeout 180s bash scripts/test-t5m-cli.sh >/dev/null
mkdir -p build/lcl-chysla-ogliad/bin build/lcl-chysla-ogliad/units
timeout 180s lazbuild --widgetset=gtk2 --build-all gui/sens-chysla-ogliad.lpi
BIN="$ROOT/build/lcl-chysla-ogliad/bin/sens-chysla-ogliad"
PACK="$ROOT/build/m0.2/bin/senst5m"
test -x "$BIN"
test -x "$PACK"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# На відміну від ширини Wn, Dn числовим робить лише явний selector.
printf '100000000000 000000000000 011111111111\n' > "$TMP/d12.words"
printf '100000000000000000000000 011111111111111111111111\n' > "$TMP/d24.words"
printf '100000000000 000000000000000000000000\n' > "$TMP/late.words"
"$PACK" --пакувати-слова "$TMP/d12.words" > "$TMP/d12.sens"
"$PACK" --пакувати-слова "$TMP/d24.words" > "$TMP/d24.sens"
"$PACK" --пакувати-слова "$TMP/late.words" > "$TMP/late.sens"
printf '\363' > "$TMP/bad.sens"
printf -- '-2048\n0\n2047\n' > "$TMP/ukr.lisp"
if ! timeout 45s xvfb-run -a -s '-screen 0 1280x900x24' "$BIN" \
  --самоперевірка "$TMP/d12.sens" "$TMP/d24.sens" \
  "$TMP/late.sens" "$TMP/bad.sens" "$TMP/ukr.lisp" \
  > "$TMP/gui.out" 2> "$TMP/gui.err"; then
  cat "$TMP/gui.out" >&2
  cat "$TMP/gui.err" >&2
  echo 'LCL-ЧИСЛА-ПРОВАЛ: реальний GTK2 самотест не пройдено' >&2
  exit 1
fi
test ! -s "$TMP/gui.err"
grep -Fq 'LCL-ЧИСЛА-ГАРАЗД' "$TMP/gui.out"
grep -Fq 'арифметика=НЕ-ДОВЕДЕНА' "$TMP/gui.out"
echo 'LCL-ЧИСЛА-ЗБІРКА-ГАРАЗД FPC=checked GTK2=Xvfb D12-D24=точні'
