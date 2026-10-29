#!/usr/bin/env bash
# G4.35 — справжній Lazarus GTK2/Xvfb виконує pinned Core4 над
# канонічним .sens із атомом, складеним D2-списком та opaque W24.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for bin in fpc lazbuild xvfb-run timeout grep cmp mktemp; do
  command -v "$bin" >/dev/null || { echo "LCL-КОРЕНІ-БЛОК: бракує $bin" >&2; exit 127; }
done
./scripts/check-pin.sh
# Повний попередній реальний FPC Core4 тест, без вимкнення негативів.
timeout 180s bash ./scripts/test-core4multiroot.sh
timeout 180s bash ./scripts/test-core4runtime.sh
mkdir -p build/lcl-core4-koreni/units
timeout 180s lazbuild --ws=gtk2 --build-all gui/core4-koreni-okno.lpi
test -x build/lcl-core4-koreni/core4-koreni-okno
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GEN="$ROOT/build/m0.2/core4-multiroot-bin/test-core4multiroot"
test -x "$GEN"
timeout 40s "$GEN" "$ROOT" "$TMP" >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fq 'CORE4-КОРЕНІ-ТЕСТ-ГАРАЗД' "$TMP/fixtures.out"
grep -Fq '0 unfreed memory blocks' "$TMP/fixtures.err"
timeout 40s xvfb-run -a "$ROOT/build/lcl-core4-koreni/core4-koreni-okno" \
  --самоперевірка "$ROOT" \
  "$TMP/good.sens" "$TMP/expected.sens" \
  "$TMP/late.sens" "$TMP/broken.sens" \
  >"$TMP/lcl.out" 2>"$TMP/lcl.err"
grep -Fq 'LCL-CORE4-КОРЕНІ-ГАРАЗД' "$TMP/lcl.out"
# G5.53: справжній GTK2 TTreeView збереженого вкладеного W24,
# координати 1-based, відмова/редагування очищає і дерево, і деталі.
grep -Fq 'дерево=вкладений-W24-адресований відновлення=так' "$TMP/lcl.out"
# Lazarus збирається своїм чинним LCL-профілем; heaptrc=0 доводить
# попередній FPC тест, а GTK2 selftest перевіряємо за процесом і stdout.
echo 'LCL-CORE4-КОРЕНІ-ЗБІРКА-ГАРАЗД FPC=так Lazarus=GTK2 фізичні-корені=3'
# Власність: LCL TForm володіє віджетами, Core4 runtime — власність TForm.
# Всі T5M .sens створені від наявного G4.34 генератора й очищені trap.
# Питання: Чому W24 не доказ D24? Чому кожен D2 корінь не сплющуємо?
# Чому обчислення йде в runtime, а не в обробнику кнопки?
# Чому помилка третьої форми очищує перші два рядки?
