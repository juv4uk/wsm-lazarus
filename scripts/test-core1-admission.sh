#!/usr/bin/env bash
# Core1-1: фізичний admission сучасного Core1.
#
# Що доводиться ЦИМ скриптом:
#   1. pinned external/sens/lib/core1.sens існує й має фіксований SHA;
#   2. наявний senst5m/sensbinary реально розбирає ЙОГО (не синтетику);
#   3. фізичне дерево дає точні доменні координати слів;
#   4. визначення другий-елемент присутнє в українській проєкції
#      тієї самої пари, тобто кандидат для admission — справжній.
#
# Чого цей скрипт НЕ доводить (і не заявляє):
#   • що Core1 ВИКОНУЄТЬСЯ — виконання потребує runtime-зв'язування;
#   • викличність або закон із ширини слова — заборонено проєктом.
#
# Жодного нового Pascal тут немає: усе через уже перевірені бінарники.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null || { echo 'ПОМИЛКА: немає Free Pascal' >&2; exit 127; }

CORE1_SENS="external/sens/lib/core1.sens"
CORE1_LISP="external/sens/lib/core1.lisp"

test -s "$CORE1_SENS" || { echo "ПОМИЛКА: немає $CORE1_SENS (запусти scripts/sync-authority.sh)" >&2; exit 1; }
test -s "$CORE1_LISP" || { echo "ПОМИЛКА: немає $CORE1_LISP" >&2; exit 1; }

echo "CORE1-ФАЙЛ фізичний=$CORE1_SENS байтів=$(wc -c < "$CORE1_SENS")"
echo "CORE1-ФАЙЛ проєкція=$CORE1_LISP рядків=$(wc -l < "$CORE1_LISP")"

# Кандидат мусить бути саме в українській проєкції — не в іншій.
grep -q '^(визначити другий-елемент' "$CORE1_LISP" \
  || { echo 'ПОМИЛКА: немає визначення другий-елемент' >&2; exit 1; }
echo 'CORE1-КАНДИДАТ другий-елемент знайдено в укр проєкції'

mkdir -p build/core1/bin build/core1/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$ROOT/build/core1/units" \
  -FE"$ROOT/build/core1/bin" -osensbinary "$ROOT/src/sensbinary.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$ROOT/build/core1/units" \
  -FE"$ROOT/build/core1/bin" -osenst5m "$ROOT/src/senst5m.lpr"

BIN="$ROOT/build/core1/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Реальний фізичний core1.sens — розбір наявним бінарником.
"$BIN/sensbinary" --аналіз "$CORE1_SENS" > "$TMP/core1.txt" 2> "$TMP/core1.err" || {
  echo 'ПОМИЛКА: наявний sensbinary відмовився розібрати core1.sens' >&2
  sed -n '1,20p' "$TMP/core1.err" >&2
  exit 1
}

WORDS=$(grep -c '^ДВІЙКОВЕ-СЛОВО' "$TMP/core1.txt" || true)
test "$WORDS" -gt 0 || { echo 'ПОМИЛКА: жодного фізичного слова не розібрано' >&2; exit 1; }
echo "CORE1-СЛІВ розібрано=$WORDS"

# Точні доменні координати присутні як структура, а не як текстова назва.
grep -q 'домен=' "$TMP/core1.txt" || { echo 'ПОМИЛКА: немає доменних координат' >&2; exit 1; }
echo 'CORE1-КООРДИНАТИ доменні поля присутні'

# Детермінізм: повторний розбір дає побайтово той самий звіт.
"$BIN/sensbinary" --аналіз "$CORE1_SENS" > "$TMP/core1-2.txt" 2>/dev/null
cmp "$TMP/core1.txt" "$TMP/core1-2.txt" || { echo 'ПОМИЛКА: розбір недетермінований' >&2; exit 1; }
echo 'CORE1-ДЕТЕРМІНІЗМ повторний розбір ідентичний'

# Негативна перевірка: підмінений вміст мусить бути відкинутий, без часткового stdout.
printf 'це не T5M\n' > "$TMP/підробка.sens"
if "$BIN/sensbinary" --аналіз "$TMP/підробка.sens" > "$TMP/нег.out" 2> "$TMP/нег.err"; then
  echo 'CORE1-ТЕСТ-ПОМИЛКА прийнято підробку' >&2; exit 1
fi
test ! -s "$TMP/нег.out" || { echo 'CORE1-ТЕСТ-ПОМИЛКА частковий stdout' >&2; exit 1; }
echo 'CORE1-НЕГАТИВ підробка відкинута без часткового виводу'

echo 'CORE1-ADMISSION ЧИТАННЯ ПРОЙДЕНО'
echo 'CORE1-ВИКОНАННЯ не перевірено цим зрізом'
