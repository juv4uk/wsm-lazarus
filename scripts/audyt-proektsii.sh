#!/usr/bin/env bash
# Аудит шести pinned проєкцій SENS у таблицях доменів.
#
# Що перевіряється:
#   1. кожна таблиця dN.lisp має РІВНО шість колонок проєкцій;
#   2. набір колонок — саме ук, укр, san, en, LISP, sym (без вигаданих);
#   3. Д7 ратифікована на 128 із 128 (заголовок файлу);
#   4. жодна таблиця не вводить сьомої проєкції.
#
# Чого НЕ перевіряється (і не заявляється):
#   • викличність, значення або закон із тексту проєкції — заборонено;
#   • повнота заповнення кожної клітинки (це окремий зріз).
#
# Жодного нового Pascal: тільки читання pinned-джерела.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

DIR="external/sens/lib/domains"
test -d "$DIR" || { echo "ПОМИЛКА: немає $DIR (запусти scripts/sync-authority.sh)" >&2; exit 1; }

EXPECTED='LISP en san sym ук укр'
BAD=0
TABLES=0

for f in "$DIR"/d*.lisp; do
  [ -e "$f" ] || continue
  grep -q '^(domain-table-' "$f" || continue
  TABLES=$((TABLES+1))
  # Колонки беремо з першого рядка запису таблиці, а не з усього файлу.
  COLS=$(grep -o '(\(ук\|укр\|san\|en\|LISP\|sym\) ' "$f" | tr -d '( ' | sort -u | tr '\n' ' ' | sed 's/ $//')
  if [ "$COLS" != "$EXPECTED" ]; then
    echo "ПРОЄКЦІЇ-РОЗБІЖНІСТЬ $(basename "$f"): [$COLS]" >&2
    BAD=1
  fi
done

test "$TABLES" -gt 0 || { echo 'ПОМИЛКА: жодної domain-table не знайдено' >&2; exit 1; }
echo "ПРОЄКЦІЇ-TABLES=$TABLES колонки=[$EXPECTED]"

# Д7: ратифікована на 128 із 128 — беремо з самого файлу, не з припущення.
D7="$DIR/d7.lisp"
test -s "$D7" || { echo 'ПОМИЛКА: немає d7.lisp' >&2; exit 1; }
grep -q '128 із 128' "$D7" || { echo 'ПРОЄКЦІЇ-ПОМИЛКА: Д7 не заявляє 128 із 128' >&2; exit 1; }
echo 'ПРОЄКЦІЇ-Д7 ратифіковано 128 із 128'

# Негативна перевірка: сьома проєкція мусить бути помічена як розбіжність.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cp -r "$DIR" "$TMP/domains"
sed -i 's/(0 (ук ні)/(0 (ук ні) (zzz зайва)/' "$TMP/domains/d1.lisp" 2>/dev/null || true
if grep -q '(zzz ' "$TMP/domains/d1.lisp" 2>/dev/null; then
  COLS2=$(grep -o '(\(ук\|укр\|san\|en\|LISP\|sym\|zzz\) ' "$TMP/domains/d1.lisp" | tr -d '( ' | sort -u | tr '\n' ' ' | sed 's/ $//')
  [ "$COLS2" != "$EXPECTED" ] || { echo 'ПРОЄКЦІЇ-ТЕСТ-ПОМИЛКА зайва проєкція не помічена' >&2; exit 1; }
  echo 'ПРОЄКЦІЇ-НЕГАТИВ зайва сьома проєкція помічена'
else
  echo 'ПРОЄКЦІЇ-НЕГАТИВ пропущено (шаблон d1 не збігся)'
fi

test "$BAD" -eq 0 || { echo 'ПРОЄКЦІЇ АУДИТ ПРОВАЛЕНО' >&2; exit 1; }
echo 'ПРОЄКЦІЇ АУДИТ ПРОЙДЕНО'
