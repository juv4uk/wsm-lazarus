#!/usr/bin/env bash
# Покриття Core1: які визначення з укр-проєкції реально присутні у фізичному .sens.
#
# Навіщо: правило проєкту — «Не заявляй про повне виконання Core1, доки всі
# його потрібні визначення не проходять реальні тести». Цей скрипт дає ЧИСЛО,
# а не заяву: скільки імен визначено в .lisp і скільки з них фізично є в .sens.
#
# Чого НЕ доводить:
#   • що визначення ВИКЛИКАЮТЬСЯ — виклик потребує runtime (пункт 2, #490);
#   • що збіг імені означає збіг закону — це заборонено виводити з тексту.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh

FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null || { echo 'ПОМИЛКА: немає Free Pascal' >&2; exit 127; }

LISP="external/sens/lib/core1.lisp"
SENS="external/sens/lib/core1.sens"
test -s "$LISP" || { echo "ПОМИЛКА: немає $LISP" >&2; exit 1; }
test -s "$SENS" || { echo "ПОМИЛКА: немає $SENS" >&2; exit 1; }

mkdir -p build/core1pok/bin build/core1pok/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$ROOT/build/core1pok/units" \
  -FE"$ROOT/build/core1pok/bin" -osenscore1nazvy "$ROOT/src/senscore1nazvy.lpr"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BIN="$ROOT/build/core1pok/bin/senscore1nazvy"
"$BIN" "$ROOT" > "$TMP/fiz-ukr.txt"

# Імена, оголошені в укр-проєкції.
grep -o '^(визначити [^ 	]*' "$LISP" | sed 's/^(визначити //' | LC_ALL=C sort -u > "$TMP/lisp.txt"
DEFINED=$(wc -l < "$TMP/lisp.txt")

# Повні D7-ідентифікатори беруться з фізичного Core1-індексу.
# Порівнювати окремий glyph ук= з повним ім'ям DEFINE — хибна звірка.
LC_ALL=C sort -u "$TMP/fiz-ukr.txt" -o "$TMP/fiz-ukr.txt"
PHYSICAL=$(wc -l < "$TMP/fiz-ukr.txt")

test "$DEFINED" -gt 0 || { echo 'ПОМИЛКА: не знайдено жодного визначення' >&2; exit 1; }
test "$PHYSICAL" -gt 0 || { echo 'ПОМИЛКА: не знайдено жодної ук-поверхні' >&2; exit 1; }

# ЖОРСТКИЙ ГЕЙТ: якщо ВСІ ук-поверхні однакові (типово '()'), binder не дав
# проєкцій. Тоді «нуль перетину» — артефакт виклику, а не факт про файл.
# Саме цього не вистачило, коли 0/96 пройшло зеленим.
if [ "$PHYSICAL" -le 1 ]; then
  echo "ПОМИЛКА: усі повні укр-імена звелися до одного значення ($(head -1 "$TMP/fiz-ukr.txt"))" >&2
  echo 'ПОМИЛКА: це означає, що доменні проєкції не застосовані — перевір режим binder' >&2
  exit 1
fi

# Скільки оголошених імен фізично присутні.
LC_ALL=C comm -12 "$TMP/lisp.txt" "$TMP/fiz-ukr.txt" > "$TMP/спільні.txt"
PRESENT=$(wc -l < "$TMP/спільні.txt")
MISSING=$((DEFINED - PRESENT))

echo "CORE1-ПОКРИТТЯ оголошено=$DEFINED фізично-присутні=$PRESENT відсутні=$MISSING"

if [ "$MISSING" -gt 0 ]; then
  echo 'CORE1-ВІДСУТНІ (перші 10):'
  LC_ALL=C comm -23 "$TMP/lisp.txt" "$TMP/fiz-ukr.txt" | head -10 | sed 's/^/  /'
fi

# Негативна перевірка: вигадане ім'я мусить бути відсутнім.
cp "$TMP/lisp.txt" "$TMP/lisp-negative.txt"
echo 'вигадане-ім-я-якого-немає' >> "$TMP/lisp-negative.txt"
LC_ALL=C sort -u -o "$TMP/lisp-negative.txt" "$TMP/lisp-negative.txt"
if LC_ALL=C comm -12 "$TMP/lisp-negative.txt" "$TMP/fiz-ukr.txt" | grep -qx 'вигадане-ім-я-якого-немає'; then
  echo 'CORE1-ТЕСТ-ПОМИЛКА вигадане ім-я знайдено фізично' >&2; exit 1
fi
echo 'CORE1-НЕГАТИВ вигадане ім-я не знайдено фізично'

# Дві справжні негативні перевірки нового FPC механізму:
# пошкоджений canonical .sens або pinned D7 не може видати частковий stdout.
BADROOT="$TMP/пошкоджений"
mkdir -p "$BADROOT/external/sens/lib/domains"
cp "$SENS" "$BADROOT/external/sens/lib/core1.sens"
cp external/sens/lib/domains/d7.lisp "$BADROOT/external/sens/lib/domains/d7.lisp"
reject_names() {
  if "$BIN" "$BADROOT" > "$TMP/частковий.stdout" 2> "$TMP/помилка.stderr"; then
    echo 'CORE1-ТЕСТ-ПОМИЛКА: зіпсований pinned файл прийнято' >&2
    exit 1
  fi
  if [ -s "$TMP/частковий.stdout" ]; then
    echo 'CORE1-ТЕСТ-ПОМИЛКА: частковий stdout при відмові' >&2
    exit 1
  fi
  grep -Fq 'CORE1-НАЗВИ-ВІДМОВА:' "$TMP/помилка.stderr"
}
: > "$BADROOT/external/sens/lib/core1.sens"
reject_names
cp "$SENS" "$BADROOT/external/sens/lib/core1.sens"
: > "$BADROOT/external/sens/lib/domains/d7.lisp"
reject_names
echo 'CORE1-НЕГАТИВ зіпсовані фізичний файл і D7 відхилено без stdout'

# ПРИКЛАДИ З ОБОХ БОКІВ: без них число нечитабельне, і «0/96» неможливо
# відрізнити від хибної звірки. Саме на цьому я двічі злив незрозуміле число.
echo 'CORE1-ПРИКЛАД-оголошені (3):'
head -3 "$TMP/lisp.txt" | sed 's/^/  /'
echo 'CORE1-ПРИКЛАД-фізичні-укр (3):'
head -3 "$TMP/fiz-ukr.txt" | sed 's/^/  /'
echo "CORE1-УНІКАЛЬНИХ-укр=$PHYSICAL"

# ПОВНИЙ СПИСОК фізичних ук-поверхонь. Без нього число «0 збігів» неможливо
# ні підтвердити, ні відкинути — саме на цьому я застряг тричі.
echo 'CORE1-УСІ-фізичні-укр:'
cat "$TMP/fiz-ukr.txt" | sed 's/^/  /'
echo 'CORE1-УСІ-оголошені (перші 20):'
head -20 "$TMP/lisp.txt" | sed 's/^/  /'

# ГЕЙТ: нуль збігу при багатьох поверхнях — це НЕ результат, це сигнал,
# що звірка хибна. Не друкуємо число як висновок, а падаємо.
# ЗБЕРЕЖЕННЯ СПИСКІВ: лог прогону може бути недоступний (я на це вже
# натрапив). Тому обидва списки завжди пишуться у файли поруч зі звітом,
# а CI їх підбирає артефактом — навіть якщо прогін червоний.
OUT="${CORE1_OUT:-build/core1pok}"
mkdir -p "$OUT"
cp "$TMP/fiz-ukr.txt" "$OUT/fizychni-ukr.txt"
cp "$TMP/lisp.txt"   "$OUT/ogolosheni.txt"
LC_ALL=C comm -12 "$TMP/lisp.txt" "$TMP/fiz-ukr.txt" > "$OUT/peretyn.txt"
echo "CORE1-ЗБЕРЕЖЕНО $OUT/fizychni-ukr.txt ($PHYSICAL) · $OUT/ogolosheni.txt ($DEFINED) · $OUT/peretyn.txt ($PRESENT)"

if [ "$PRESENT" -eq 0 ] && [ "$PHYSICAL" -gt 10 ]; then
  echo 'CORE1-СТОП: нуль збігу при багатьох фізичних поверхнях.' >&2
  echo 'CORE1-СТОП: це сигнал хибної звірки, а не факт про файл. Дивись списки вище.' >&2
  exit 1
fi

echo "CORE1-ПОКРИТТЯ-ЧИСЛО $PRESENT/$DEFINED"
echo 'CORE1-ВИКОНАННЯ не перевірено цим зрізом'
