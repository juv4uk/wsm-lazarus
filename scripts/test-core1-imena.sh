#!/usr/bin/env bash
# Core1.5: перевірка ПОВНИХ фізичних імен, а не окремих glyph-проєкцій.
# .sens — єдиний фізичний вхід; .lisp порівнюється тільки як людський свідок.
set -euo pipefail
export LC_ALL=C
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'CORE1-ІМЕНА-БЛОК: немає Free Pascal' >&2; exit 127; }
for exe in timeout grep sed sort cmp wc mktemp cp; do
  command -v "$exe" >/dev/null || { echo "CORE1-ІМЕНА-БЛОК: немає $exe" >&2; exit 127; }
done

mkdir -p build/core1imena/units build/core1imena/bin
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/core1imena/units" \
  -FE"$ROOT/build/core1imena/bin" \
  -osenscore1imena "$ROOT/src/senscore1imena.lpr"
CLI="$ROOT/build/core1imena/bin/senscore1imena"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Відновлюємо ПОВНІ назви з кожного D7-списку точного DEFINE у .sens.
timeout 60s "$CLI" "$ROOT" >"$TMP/fizychni-ukr.txt" 2>"$TMP/err"
test ! -s "$TMP/err"
timeout 60s "$CLI" "$ROOT" >"$TMP/povtor.txt"
cmp "$TMP/fizychni-ukr.txt" "$TMP/povtor.txt"

# Звірка проєкції: не робить .lisp фізичним або семантичним oracle.
grep -o '^(визначити [^[:space:]]*' external/sens/lib/core1.lisp \
  | sed 's/^(визначити //' | sort -u >"$TMP/ogolosheni.txt"
sort -u "$TMP/fizychni-ukr.txt" >"$TMP/fizychni-sorted.txt"
PHYSICAL=$(wc -l <"$TMP/fizychni-ukr.txt")
UNIQUE=$(wc -l <"$TMP/fizychni-sorted.txt")
DEFINED=$(wc -l <"$TMP/ogolosheni.txt")
test "$PHYSICAL" -eq 129
test "$UNIQUE" -eq "$PHYSICAL"
test "$DEFINED" -eq 129
grep -Fxq 'другий-елемент' "$TMP/fizychni-sorted.txt"
if ! cmp -s "$TMP/ogolosheni.txt" "$TMP/fizychni-sorted.txt"; then
  echo "CORE1-ІМЕНА-РОЗБІЖНІСТЬ фізично=$PHYSICAL укр=$DEFINED" >&2
  diff -u "$TMP/ogolosheni.txt" "$TMP/fizychni-sorted.txt" >&2 || true
  exit 1
fi

# Негативи: пошкоджені фізичні байти, зламана pinned D7 і відсутній root.
reject() {
  if timeout 60s "$CLI" "$1" >"$TMP/chastkovyi.stdout" 2>"$TMP/pomylka.stderr"; then
    echo 'CORE1-ІМЕНА-ПРОВАЛ: хибний вхід допущено' >&2; exit 1
  fi
  test ! -s "$TMP/chastkovyi.stdout" || {
    echo 'CORE1-ІМЕНА-ПРОВАЛ: частковий stdout' >&2; exit 1;
  }
  grep -Fq 'CORE1-ІМЕНА-ВІДМОВА:' "$TMP/pomylka.stderr" || {
    cat "$TMP/pomylka.stderr" >&2; exit 1;
  }
}
reject "$TMP/відсутній"
mkdir -p "$TMP/підміна/external/sens/lib/domains"
cp external/sens/lib/domains/d7.lisp "$TMP/підміна/external/sens/lib/domains/d7.lisp"
cp external/sens/lib/core1.sens "$TMP/підміна/external/sens/lib/core1.sens"
printf '\377' >"$TMP/підміна/external/sens/lib/core1.sens"
reject "$TMP/підміна"
cp external/sens/lib/core1.sens "$TMP/підміна/external/sens/lib/core1.sens"
printf '\300\257' >"$TMP/підміна/external/sens/lib/domains/d7.lisp"
reject "$TMP/підміна"
timeout 60s "$CLI" "$ROOT" >"$TMP/vidnovleno.txt"
cmp "$TMP/fizychni-ukr.txt" "$TMP/vidnovleno.txt"
echo "CORE1-ІМЕНА-ГАРАЗД фізичних=$PHYSICAL укр=$DEFINED точний-D7=так зворотність=так негативні=3 виконання=не-доведено"
