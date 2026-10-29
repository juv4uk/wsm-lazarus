#!/usr/bin/env bash
# G4.35 — справжній Lazarus GTK2/Xvfb виконує pinned Core4 над
# канонічним .sens із атомом, складеним D2-списком та opaque W24.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for bin in fpc lazbuild xvfb-run timeout grep cmp mktemp stat readlink; do
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
# Наявні single-1/2/3.sens створює ВЖЕ ЗЛИТИЙ фізичний генератор,
# без людського переозначення законів Core4 або D12+.
for index in 1 2 3; do
  test -s "$TMP/single-$index.sens"
done
# G4.44: незалежний FPC свідок повного Core4 результату 64 коренів.
for name in large large-expected mixed mixed-expected late-64 too-many; do
  test -s "$TMP/$name.sens"
done
ln -s "$TMP/неіснуючий-фізичний-файл.sens" "$TMP/lcl-dangling-export.sens"
# G4.41: не дозволяємо масці runner (звичайно 0022) приховати помилку
# атомарного створення файлу: усі 6 фізичних виходів мають бути
# приватними 0600 навіть тоді, коли host дозволяє 0666.
umask 000
test "$(umask)" = 0000 || {
  echo 'LCL-КОРЕНІ-ПРОВАЛ: тест не встановив umask 000' >&2; exit 1;
}
if ! timeout 40s xvfb-run -a "$ROOT/build/lcl-core4-koreni/core4-koreni-okno" \
  --самоперевірка "$ROOT" \
  "$TMP/good.sens" "$TMP/expected.sens" \
  "$TMP/late.sens" "$TMP/broken.sens" \
  >"$TMP/lcl.out" 2>"$TMP/lcl.err"; then
  cat "$TMP/lcl.out" >&2
  cat "$TMP/lcl.err" >&2
  echo 'LCL-КОРЕНІ-ПРОВАЛ: справжній GTK2 selftest завершився з помилкою' >&2
  exit 1
fi
grep -Fq 'LCL-CORE4-КОРЕНІ-ГАРАЗД' "$TMP/lcl.out"
grep -Fq 'експорт=3 D2-рамка=так no-clobber=так' "$TMP/lcl.out"
for index in 1 2 3; do
  cmp "$TMP/single-$index.sens" "$TMP/lcl-export-$index.sens"
  test "$(stat -c %a "$TMP/lcl-export-$index.sens")" = 600 || {
    echo 'LCL-КОРЕНІ-ПРОВАЛ: приватний вихід не має прав 0600 при umask 000' >&2; exit 1;
  }
  test "$(stat -c %h "$TMP/lcl-export-$index.sens")" = 1 || {
    echo 'LCL-КОРЕНІ-ПРОВАЛ: після публікації залишився зайвий hardlink' >&2; exit 1;
  }
done
# G4.48: саме обраний вкладений фізичний W24 і D2-список
# отримують окремі канонічні T5M .sens, незалежні від підпису GUI.
cmp "$TMP/single-3.sens" "$TMP/lcl-node-w24.sens"
cmp "$TMP/single-2.sens" "$TMP/lcl-node-list.sens"
for name in lcl-node-w24 lcl-node-list; do
  test "$(stat -c %a "$TMP/$name.sens")" = 600 || {
    echo "LCL-КОРЕНІ-ПРОВАЛ: вибраний $name вузол не є приватним 0600" >&2
    exit 1
  }
  test "$(stat -c %h "$TMP/$name.sens")" = 1 || {
    echo "LCL-КОРЕНІ-ПРОВАЛ: вибраний $name вузол має зайвий hardlink" >&2
    exit 1
  }
done
grep -Fq 'вузол=вкладений-W24,D2-список заголовок=відмова' "$TMP/lcl.out"
for name in lcl-empty-node lcl-node-header lcl-node-stale; do
  test ! -e "$TMP/$name.sens"
done
test ! -e "$TMP/lcl-node-w24.lisp"
cmp "$TMP/single-2.sens" "$TMP/lcl-export-recovered.sens"
test "$(stat -c %a "$TMP/lcl-export-recovered.sens")" = 600 || {
  echo 'LCL-КОРЕНІ-ПРОВАЛ: відновлений корінь не приватний при umask 000' >&2; exit 1;
}
test "$(stat -c %h "$TMP/lcl-export-recovered.sens")" = 1 || {
  echo 'LCL-КОРЕНІ-ПРОВАЛ: відновлений корінь зберіг зайвий hardlink' >&2; exit 1;
}
# Повний пакет — не конкатенація тексту з GUI, а FAnswer canonical T5M.
for name in lcl-export-all lcl-export-all-recovered; do
  cmp "$TMP/expected.sens" "$TMP/$name.sens"
  test "$(stat -c %a "$TMP/$name.sens")" = 600 || {
    echo 'LCL-КОРЕНІ-ПРОВАЛ: повний пакет не приватний 0600 при umask 000' >&2; exit 1;
  }
  test "$(stat -c %h "$TMP/$name.sens")" = 1 || {
    echo 'LCL-КОРЕНІ-ПРОВАЛ: повний пакет зберіг зайвий hardlink' >&2; exit 1;
  }
done
grep -Fq 'пакет=так' "$TMP/lcl.out"
grep -Fq 'межа=64 змішані=160 пізня-відмова=64' "$TMP/lcl.out"
# Байти GUI-експорту згодні з НЕЗАЛЕЖНИМ очікуваним T5M
# (не з текстом у TStringGrid, D7-проєкцією або D12 host-числом).
# G4.45: вибір ВКЛАДЕНОГО W24 в TTreeView міняє реальний
# TStringGrid.Row=2 або 64; той самий ExportRoot бере саме цей корінь.
for name in lcl-tree-selected-2 lcl-tree-selected-64; do
  cmp "$TMP/single-2.sens" "$TMP/$name.sens"
done
grep -Fq 'навігація=3,64' "$TMP/lcl.out"
cmp "$TMP/single-2.sens" "$TMP/lcl-export-64.sens"
cmp "$TMP/single-2.sens" "$TMP/lcl-export-mixed-63.sens"
cmp "$TMP/large-expected.sens" "$TMP/lcl-export-large.sens"
for name in lcl-export-mixed lcl-export-mixed-recovered; do
  cmp "$TMP/mixed-expected.sens" "$TMP/$name.sens"
done
for name in lcl-export-64 lcl-export-mixed-63 lcl-export-large \
            lcl-export-mixed lcl-export-mixed-recovered \
            lcl-tree-selected-2 lcl-tree-selected-64; do
  test "$(stat -c %a "$TMP/$name.sens")" = 600 || {
    echo "LCL-КОРЕНІ-ПРОВАЛ: $name не приватний при umask 000" >&2
    exit 1
  }
  test "$(stat -c %h "$TMP/$name.sens")" = 1 || {
    echo "LCL-КОРЕНІ-ПРОВАЛ: $name має зайвий hardlink" >&2
    exit 1
  }
done
test -L "$TMP/lcl-dangling-export.sens"
test "$(readlink "$TMP/lcl-dangling-export.sens")" = "$TMP/неіснуючий-фізичний-файл.sens"
test ! -e "$TMP/неіснуючий-фізичний-файл.sens"
for name in lcl-empty-export lcl-bad-zero lcl-bad-four lcl-stale-after-edit \
  lcl-stale-broken lcl-stale-late lcl-empty-all lcl-stale-all-edit \
  lcl-stale-all-broken lcl-stale-all-late lcl-export-65 \
  lcl-stale-late-64 lcl-stale-65; do
  test ! -e "$TMP/$name.sens"
done
test ! -e "$TMP/lcl-bad-extension.lisp"
test ! -e "$TMP/lcl-full-bad.lisp"
if find "$TMP" -maxdepth 1 -name 'c4e*' -print -quit | grep -q .; then
  echo 'LCL-КОРЕНІ-ПРОВАЛ: залишилися приватні тимчасові файли' >&2; exit 1;
fi
# G5.53: справжній GTK2 TTreeView збереженого вкладеного W24,
# координати 1-based, відмова/редагування очищає і дерево, і деталі.
grep -Fq 'дерево=вкладений-W24-адресований відновлення=так' "$TMP/lcl.out"
# Lazarus збирається своїм чинним LCL-профілем; heaptrc=0 доводить
# попередній FPC тест, а GTK2 selftest перевіряємо за процесом і stdout.
echo 'LCL-CORE4-КОРЕНІ-ЗБІРКА-ГАРАЗД FPC=так Lazarus=GTK2 фізичні-корені=64 змішані=160 експорт=15 0600=15/15 umask=000 hardlink=1'
# Власність: LCL TForm володіє віджетами, Core4 runtime — власність TForm.
# Всі T5M .sens створені від наявного G4.34 генератора й очищені trap.
# Питання: Чому W24 не доказ D24? Чому кожен D2 корінь не сплющуємо?
# Чому обчислення йде в runtime, а не в обробнику кнопки?
# Чому помилка третьої форми очищує перші два рядки?
