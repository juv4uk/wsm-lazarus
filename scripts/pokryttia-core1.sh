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

FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null || { echo 'ПОМИЛКА: немає Free Pascal' >&2; exit 127; }

LISP="external/sens/lib/core1.lisp"
SENS="external/sens/lib/core1.sens"
test -s "$LISP" || { echo "ПОМИЛКА: немає $LISP" >&2; exit 1; }
test -s "$SENS" || { echo "ПОМИЛКА: немає $SENS" >&2; exit 1; }

mkdir -p build/core1pok/bin build/core1pok/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$ROOT/build/core1pok/units" \
  -FE"$ROOT/build/core1pok/bin" -osensbinary "$ROOT/src/sensbinary.lpr"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
"$ROOT/build/core1pok/bin/sensbinary" --аналіз "$SENS" > "$TMP/fiz.txt" 2>/dev/null

# Імена, оголошені в укр-проєкції.
grep -o '^(визначити [^ 	]*' "$LISP" | sed 's/^(визначити //' | sort -u > "$TMP/lisp.txt"
DEFINED=$(wc -l < "$TMP/lisp.txt")

# Фізичні ук-поверхні з розбору .sens.
grep -o 'ук=[^ ]*' "$TMP/fiz.txt" | sed 's/^ук=//' | sort -u > "$TMP/fiz-uk.txt"
PHYSICAL=$(wc -l < "$TMP/fiz-uk.txt")

test "$DEFINED" -gt 0 || { echo 'ПОМИЛКА: не знайдено жодного визначення' >&2; exit 1; }
test "$PHYSICAL" -gt 0 || { echo 'ПОМИЛКА: не знайдено жодної ук-поверхні' >&2; exit 1; }

# Скільки оголошених імен фізично присутні.
comm -12 "$TMP/lisp.txt" "$TMP/fiz-uk.txt" > "$TMP/спільні.txt"
PRESENT=$(wc -l < "$TMP/спільні.txt")
MISSING=$((DEFINED - PRESENT))

echo "CORE1-ПОКРИТТЯ оголошено=$DEFINED фізично-присутні=$PRESENT відсутні=$MISSING"

if [ "$MISSING" -gt 0 ]; then
  echo 'CORE1-ВІДСУТНІ (перші 10):'
  comm -23 "$TMP/lisp.txt" "$TMP/fiz-uk.txt" | head -10 | sed 's/^/  /'
fi

# Негативна перевірка: вигадане ім'я мусить бути відсутнім.
echo 'вигадане-ім-я-якого-немає' >> "$TMP/lisp.txt"
sort -u -o "$TMP/lisp.txt" "$TMP/lisp.txt"
if comm -12 "$TMP/lisp.txt" "$TMP/fiz-uk.txt" | grep -qx 'вигадане-ім-я-якого-немає'; then
  echo 'CORE1-ТЕСТ-ПОМИЛКА вигадане ім-я знайдено фізично' >&2; exit 1
fi
echo 'CORE1-НЕГАТИВ вигадане ім-я не знайдено фізично'

echo "CORE1-ПОКРИТТЯ-ЧИСЛО $PRESENT/$DEFINED"
echo 'CORE1-ВИКОНАННЯ не перевірено цим зрізом'
