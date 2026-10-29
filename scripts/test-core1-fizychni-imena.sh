#!/usr/bin/env bash
# G2.52 — незалежна звірка повних фізичних Core1 D7-імен.
# Не редагує чужий scripts/pokryttia-core1.sh.
# Канон .sens, .lisp лише українська проєкція, викликуваність не доводиться.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
for tool in "$FPC_BIN" timeout comm cmp sort grep sed mktemp; do
  command -v "$tool" >/dev/null || {
    echo "CORE1-ФІЗ-ІМЕНА-БЛОК: немає $tool" >&2; exit 127;
  }
done
./scripts/check-pin.sh
LISP=external/sens/lib/core1.lisp
SENS=external/sens/lib/core1.sens
test -s "$LISP" && test -s "$SENS" || {
  echo 'CORE1-ФІЗ-ІМЕНА-БЛОК: pinned пара .sens/.lisp неповна' >&2; exit 1;
}
OUT="${CORE1_NAMES_OUT:-build/core1-fiz-imena}"
mkdir -p "$OUT/bin" "$OUT/units"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/$OUT/units" \
  -FE"$ROOT/$OUT/bin" -osenscore1imena \
  "$ROOT/src/senscore1imena.lpr"
CLI="$ROOT/$OUT/bin/senscore1imena"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Явне людське джерело: заголовки DEFINE лише для порівняння
# повної проєкції. Не використовується як ратифікований закон.
LC_ALL=C grep -E '^\(визначити [^[:space:]()]+' "$LISP" \
  | sed -E 's/^\(визначити ([^[:space:]()]+).*/\1/' \
  | LC_ALL=C sort -u >"$TMP/lisp.txt"

# Фізичне джерело: перевірений T5M/D2/Core1Index з exact D7
# та pinned D7 Surface[укр] у новому FPC CLI.
timeout 90s "$CLI" "$ROOT" >"$TMP/fiz.txt"
LC_ALL=C sort -u "$TMP/fiz.txt" >"$TMP/fiz-ukr.txt"
DEFINED=$(wc -l <"$TMP/lisp.txt")
PHYSICAL=$(wc -l <"$TMP/fiz-ukr.txt")
PHYSICAL_RAW=$(wc -l <"$TMP/fiz.txt")
test "$DEFINED" -gt 0 && test "$PHYSICAL" -gt 0 &&
test "$PHYSICAL_RAW" -eq "$PHYSICAL" || {
  echo 'CORE1-ФІЗ-ІМЕНА-БЛОК: порожні або колізійні імена' >&2; exit 1;
}
comm -12 "$TMP/lisp.txt" "$TMP/fiz-ukr.txt" >"$TMP/peretyn.txt"
PRESENT=$(wc -l <"$TMP/peretyn.txt")
MISSING=$((DEFINED-PRESENT))
EXTRA=$((PHYSICAL-PRESENT))

# Навіть у випадку розбіжності залишаємо повні артефакти.
cp "$TMP/fiz-ukr.txt" "$OUT/fizychni-ukr.txt"
cp "$TMP/lisp.txt" "$OUT/ogolosheni.txt"
cp "$TMP/peretyn.txt" "$OUT/peretyn.txt"
echo "CORE1-ФІЗ-ІМЕНА фізичних=$PHYSICAL оголошених=$DEFINED збігів=$PRESENT"

# Негативи: вигадане ім'я і зіпсоване фізичне джерело без stdout.
echo 'CORE1-НЕГАТИВ-1: перевірка вигаданого імені'
if grep -Fxq 'вигадане-ім-я-якого-немає' "$TMP/fiz-ukr.txt"; then
  echo 'CORE1-ФІЗ-ІМЕНА-ПРОВАЛ: вигадане ім’я стало фізичним' >&2; exit 1
fi
mkdir -p "$TMP/пошкоджено/external/sens/lib"
printf '\377' >"$TMP/пошкоджено/external/sens/lib/core1.sens"
if timeout 10s "$CLI" "$TMP/пошкоджено" >"$TMP/помилка.out" 2>"$TMP/помилка.err"; then
  echo 'CORE1-ФІЗ-ІМЕНА-ПРОВАЛ: зіпсований T5M прийнято' >&2; exit 1
fi
if test -s "$TMP/помилка.out"; then
  echo 'CORE1-ФІЗ-ІМЕНА-ПРОВАЛ: частковий stdout після зіпсованого T5M' >&2
  cat "$TMP/помилка.out" >&2
  exit 1
fi
if ! grep -Fq 'CORE1-ФІЗИЧНІ-ІМЕНА-ВІДМОВА:' "$TMP/помилка.err"; then
  echo 'CORE1-ФІЗ-ІМЕНА-ПРОВАЛ: невідповідна діагностика зіпсованого T5M' >&2
  cat "$TMP/помилка.err" >&2
  exit 1
fi
echo 'CORE1-НЕГАТИВ-2: зіпсований T5M відхилено без часткового stdout'

if [ "$MISSING" -ne 0 ] || [ "$EXTRA" -ne 0 ]; then
  echo "CORE1-ФІЗ-ІМЕНА-СТОП: людських без фізичного=$MISSING фізичних без людського=$EXTRA" >&2
  echo 'Людські імена без фізичного відповідника:' >&2
  comm -23 "$TMP/lisp.txt" "$TMP/fiz-ukr.txt" | head -10 >&2
  echo 'Фізичні імена без людського відповідника:' >&2
  comm -13 "$TMP/lisp.txt" "$TMP/fiz-ukr.txt" | head -10 >&2
  exit 1
fi
echo "CORE1-ФІЗ-ІМЕНА-ГАРАЗД $PRESENT/$DEFINED exact-D7=так укр=так виконання=ні"
