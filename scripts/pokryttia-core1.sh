#!/usr/bin/env bash
# Core1: ЩО НАСПРАВДІ лежить у фізичному core1.sens — і чому «покриття
# через поле ук=» НЕ МІРЯЄТЬСЯ.
#
# ІСТОРІЯ ПОМИЛКИ (щоб її не повторили):
#   Перша версія цього скрипта брала `ук=` з `sensbinary --аналіз` і
#   звіряла з іменами `(визначити ...)`. Результат був 0/96, і його
#   двічі злили як «покриття». Артефакт показав справжній вміст:
#       fizychni-uk.txt = "-", "1", "?", І, А, В, Г, Д, Е, З, И, Й …
#   Тобто `ук=` — це Д7-проєкція ОКРЕМОГО СИМВОЛА, а не ім'я визначення.
#   Порівнювати їх — категоріальна помилка. 0/96 не означає нічого.
#
# Що цей скрипт робить тепер:
#   • доводить, що фізичний файл читається й дає слова (це вже доведено);
#   • доводить, що `ук=` — СИМВОЛЬНИЙ рівень, а не ідентифікатори;
#   • НЕ друкує жодного числа «покриття», бо правильного способу тут немає.
#
# Що потрібно для справжнього покриття:
#   не плоский список слів, а СТРУКТУРА дерева — `--дерево-д10` або
#   BindT5MBinary із зібраними іменами визначень. Це окрема задача.
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
"$ROOT/build/core1pok/bin/sensbinary" --аналіз-д10 "$SENS" > "$TMP/fiz.txt" 2>/dev/null

WORDS=$(grep -c '^ДВІЙКОВЕ-СЛОВО' "$TMP/fiz.txt" || true)
test "$WORDS" -gt 0 || { echo 'ПОМИЛКА: жодного слова не розібрано' >&2; exit 1; }
echo "CORE1-СЛІВ=$WORDS"

grep -o 'ук=[^ ]*' "$TMP/fiz.txt" | sed 's/^ук=//' | sort -u > "$TMP/surf.txt"
SURF=$(wc -l < "$TMP/surf.txt")

# ГЕЙТ КАТЕГОРІЇ: якщо майже всі ук-поверхні — один-два СИМВОЛИ,
# це Д7-рівень, а не ідентифікатори. Тоді «покриття» тут не міряється,
# і жодного числа друкувати не можна.
LONG=$(awk 'length($0)>3' "$TMP/surf.txt" | wc -l)
echo "CORE1-УНІКАЛЬНИХ-ук=$SURF · довших-за-3-символи=$LONG"

if [ "$LONG" -eq 0 ]; then
  echo 'CORE1-РІВЕНЬ: ук= — СИМВОЛЬНИЙ (Д7), не ідентифікатори'
  echo 'CORE1-ПОКРИТТЯ: НЕ МІРЯЄТЬСЯ через ук= — потрібна структура дерева'
  echo 'CORE1-ЖОДНОГО-ЧИСЛА: навмисно, щоб 0/N не прийняли за результат'
  exit 0
fi

# Якщо раптом зʼявляться довгі поверхні — це вже інший рівень, і тоді
# звірка з іменами має сенс. Але такого ще не спостерігалось.
echo 'CORE1-РІВЕНЬ: знайдено довгі ук-поверхні — звірка можлива'
comm -12 <(grep -o '^(визначити [^ 	]*' "$LISP" | sed 's/^(визначити //' | sort -u) \
         "$TMP/surf.txt" > "$TMP/peretyn.txt"
echo "CORE1-ПЕРЕТИН=$(wc -l < "$TMP/peretyn.txt")"
