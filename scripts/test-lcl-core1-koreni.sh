#!/usr/bin/env bash
# G1.49 — реальний FPC+Lazarus GTK2/Xvfb огляд pinned Core1.
# Без другого reader, власної семантики або виконання DEFINE.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for bin in fpc lazbuild xvfb-run timeout mktemp grep head; do
  command -v "$bin" >/dev/null || {
    echo "LCL-CORE1-БЛОК: немає $bin" >&2
    exit 127
  }
done
timeout 30s bash ./scripts/check-pin.sh
# Використовуємо вже чинний FPC admission з усіма його негативами.
timeout 180s bash ./scripts/test-core1-dopus.sh
mkdir -p build/lcl-core1-koreni/units
timeout 180s lazbuild --ws=gtk2 --build-all gui/core1-fizychni-koreni.lpi
APP="$ROOT/build/lcl-core1-koreni/core1-fizychni-koreni"
test -x "$APP"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
head -c 1 "$ROOT/external/sens/lib/core1.sens" >"$TMP/пошкоджений.sens"
printf '\300\257' >"$TMP/пошкоджений.lisp"
if ! timeout 90s xvfb-run -a "$APP" --самоперевірка "$ROOT" \
  "$TMP/пошкоджений.sens" "$TMP/пошкоджений.lisp" \
  >"$TMP/справжній.out" 2>"$TMP/справжній.err"; then
  cat "$TMP/справжній.out" >&2
  cat "$TMP/справжній.err" >&2
  echo 'LCL-CORE1-ПРОВАЛ: справжній GTK2 selftest не пройшов' >&2
  exit 1
fi
grep -Fq 'LCL-CORE1-КОРЕНІ-ГАРАЗД' "$TMP/справжній.out"
grep -Fq 'коренів=96 слів=31569' "$TMP/справжній.out"
grep -Fq 'D4=0011/0010 D7=exact укр=позиційна T5M=побайтово' \
  "$TMP/справжній.out"
grep -Fq 'негативні=3 очищення=так відновлення=так виконання=ні' \
  "$TMP/справжній.out"
echo 'LCL-CORE1-ЗБІРКА-ГАРАЗД FPC=3.2.2 Lazarus=GTK2/Xvfb pinned=так коренів=96 негативні=3'
# Типи: TExactWords — фізичні бітові рядки; TPhysicalNodeSpan —
# координати, а не закон. Doc/free лише в межах LoadPaths.
# Питання: чому T5M і укр не змішують? Чому W7 не є текстовий opcode?
# Чому не залишається старого вікна після пізнього відхилення?
