#!/usr/bin/env bash
# G2.45 — окремий фізичний CLI допуск D10, старі режими незмінні.
# Усе вхідне .sens — канонічні T5M байти; .words лише host-fixture.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
: "${FPC:=fpc}"
mkdir -p build/m0.2/bin build/m0.2/test-units
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/test-units" -FE"$ROOT/build/m0.2/bin" \
  -osensbinary "$ROOT/src/sensbinary.lpr"
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/test-units" -FE"$ROOT/build/m0.2/bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"
BIN="$ROOT/build/m0.2/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pack() {
  local name=$1 words=$2
  printf '%s\n' "$words" > "$TMP/$name.words"
  "$BIN/senst5m" --pack-words "$TMP/$name.words" > "$TMP/$name.sens"
}
reject() {
  local mode=$1 file=$2 label=$3
  if "$BIN/sensbinary" "$mode" "$file" >"$TMP/відмова.out" 2>"$TMP/відмова.err"; then
    echo "Д10-КЛІ-ПОМИЛКА: прийнято $label" >&2; exit 1
  fi
  test ! -s "$TMP/відмова.out" || {
    echo "Д10-КЛІ-ПОМИЛКА: частковий stdout $label" >&2; exit 1;
  }
  grep -Fq 'ДВІЙКОВЕ-ПОМИЛКА' "$TMP/відмова.err" || {
    cat "$TMP/відмова.err" >&2
    echo "Д10-КЛІ-ПОМИЛКА: втрачено діагностику $label" >&2; exit 1;
  }
}

# Повний фізичний D2 список, D7 SYN як opaque data, а далі інший root.
# D10 low/high — різні повні 10-бітні ключі; індекси включають D2.
pack 'структура' '10 0000000000 00 0010110 01 00 1111111111'
"$BIN/sensbinary" --аналіз-д10 "$TMP/структура.sens" >"$TMP/д10.txt"
grep -Fxq 'ДВІЙКОВЕ-СЛОВО індекс=2 форма=0 домен=10 біти=0000000000 порожнє=ні ук=немає-можливості' "$TMP/д10.txt"
grep -Fxq 'ДВІЙКОВЕ-СЛОВО індекс=4 форма=0 домен=7 біти=0010110 порожнє=ні ук=немає' "$TMP/д10.txt"
grep -Fq 'ДВІЙКОВЕ-СЛОВО індекс=7 форма=1 домен=10 біти=1111111111 порожнє=ні ук=' "$TMP/д10.txt"
grep -Fxq 'ДВІЙКОВЕ-ПІДСУМОК слів=3 викличність=не-перевірено виконання=не-перевірено' "$TMP/д10.txt"
test "$(wc -l < "$TMP/д10.txt")" -eq 4
"$BIN/sensbinary" --аналіз-д10 "$TMP/структура.sens" >"$TMP/повтор.txt"
cmp "$TMP/д10.txt" "$TMP/повтор.txt"

# Жодна фізична ширина не має призводити до неявного вибору режиму.
reject '--аналіз' "$TMP/структура.sens" 'старий W1–W9 режим'
reject '--дерево' "$TMP/структура.sens" 'старе дерево W1–W9'

pack 'низький-д3' '000 00 0'
"$BIN/sensbinary" --аналіз-д10 "$TMP/низький-д3.sens" > "$TMP/низький-д3.txt"
grep -Fq 'домен=3 біти=000 порожнє=так' "$TMP/низький-д3.txt"
grep -Fq 'домен=1 біти=0 порожнє=ні' "$TMP/низький-д3.txt"
"$BIN/sensbinary" --аналіз "$TMP/низький-д3.sens" > "$TMP/старий.txt"
cmp "$TMP/низький-д3.txt" "$TMP/старий.txt"

pack 'одинадцять' '00000000000'
pack 'дванадцять' '000000000000'
pack 'пізній-дванадцять' '0000000000 00 000000000000'
pack 'незакритий' '10 0000000000'
reject '--аналіз-д10' "$TMP/одинадцять.sens" 'W11 не є D10'
reject '--аналіз-д10' "$TMP/дванадцять.sens" 'W12 без числового D12 закону'
reject '--аналіз-д10' "$TMP/пізній-дванадцять.sens" 'жодного partial stdout після W10'
reject '--аналіз-д10' "$TMP/незакритий.sens" 'D2 EOF після W10'
printf '\\363' > "$TMP/зіпсований.sens"
reject '--аналіз-д10' "$TMP/зіпсований.sens" 'пошкоджений T5M'
: > "$TMP/порожній.sens"
reject '--аналіз-д10' "$TMP/порожній.sens" 'порожній T5M'
printf '(за-умовою так)\n' > "$TMP/людина.lisp"
reject '--аналіз-д10' "$TMP/людина.lisp" '.lisp не фізичний ввід'
reject '--аналіз-д10' "$TMP/відсутній.sens" 'відсутній фізичний ввід'
if (cd "$TMP" && "$BIN/sensbinary" --аналіз-д10 "$TMP/структура.sens" \
  >"$TMP/відмова.out" 2>"$TMP/відмова.err"); then
  echo 'Д10-КЛІ-ПОМИЛКА: чужий cwd пройшов без pinned SENS' >&2
  exit 1
fi
test ! -s "$TMP/відмова.out"
grep -Fq 'ДВІЙКОВЕ-ПОМИЛКА' "$TMP/відмова.err"

# Регресія попереднього фізичного та шестипроєкційного дерева.
bash "$ROOT/scripts/test-binary-cli.sh"
echo 'Д10-КЛІ-ГАРАЗД: FPC=справжній T5M=фізичний D10=явний D7=SYN-дані старі-режими=незмінні W11/W12=відмова stdout=атомарний'
