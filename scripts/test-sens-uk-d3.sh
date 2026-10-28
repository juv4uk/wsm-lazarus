#!/usr/bin/env bash
# Фізичний запуск FPC: кордон над уже перевіреним D3, не нові мовні закони.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$TMP/units" -FE"$TMP/bin" -osens-uk-d3 "$ROOT/src/sens_uk_d3.lpr"
BIN="$TMP/bin/sens-uk-d3"
test -x "$BIN"
CHECKS=0

uspikh() {
  local mode="$1" data="$2" expected="$3"
  printf '%s\n' "$expected" > "$TMP/expected"
  "$BIN" "$mode" "$data" >"$TMP/output" 2>"$TMP/errors"
  if ! cmp -s "$TMP/output" "$TMP/expected" || test -s "$TMP/errors"; then
    echo 'ПОМИЛКА-ТЕСТУ: байтовий результат або stderr' >&2
    cat "$TMP/output" "$TMP/errors" >&2
    exit 1
  fi
  CHECKS=$((CHECKS+1))
}

vidmova() {
  local status=0
  if "$BIN" "$@" >"$TMP/output" 2>"$TMP/errors"; then
    echo 'ПОМИЛКА-ТЕСТУ: помилковий запит прийнято' >&2
    exit 1
  else
    status=$?
  fi
  if test "$status" -ne 2 || test -s "$TMP/output" || \
     ! grep -q 'ПОМИЛКА-УК' "$TMP/errors"; then
    echo "ПОМИЛКА-ТЕСТУ: неатомарна відмова, статус=$status" >&2
    cat "$TMP/output" "$TMP/errors" >&2
    exit 1
  fi
  CHECKS=$((CHECKS+1))
}

pozytsiya() {
  vidmova "$@"
  grep -Eq 'рядок=[1-9][0-9]* колонка=[1-9][0-9]* байт=[1-9][0-9]*' "$TMP/errors" || {
    echo 'ПОМИЛКА-ТЕСТУ: немає фізичної позиції' >&2; exit 1;
  }
  CHECKS=$((CHECKS+1))
}

# Очікувані результати — з уже затвердженого G3.2 FPC/physical witness.
uspikh --вираз-ук '(сполучити так ())' '(1)'
uspikh --вираз-ук '(перше (сполучити ні ()))' '0'
uspikh --вираз-ук '(атом? ())' '1'
uspikh --вираз-ук '(як-є кіт)' '(1110010 1110011 1101110)'
uspikh --вираз-ук 'ні' '0'
uspikh --вираз-ук '()' '()'
printf '%s\n' '(сполучити ні ())' > "$TMP/приклад.lisp"
uspikh --файл-ук "$TMP/приклад.lisp" '(0)'
printf '%s\n' '(як-є (кіт))' > "$TMP/список.lisp"
uspikh --файл-ук "$TMP/список.lisp" '((1110010 1110011 1101110))'

# Негативи: жодного байта в stdout, позиційна помилка у stderr.
pozytsiya --вираз-ук '(перше ())'
pozytsiya --вираз-ук '(сполучити так)'
pozytsiya --вираз-ук '(car ())'
pozytsiya --вираз-ук 'невідома-змінна'
pozytsiya --вираз-ук 'так ні'
pozytsiya --вираз-ук '(перше'
pozytsiya --вираз-ук '(як-є (а . б))'
pozytsiya --вираз-ук ''
printf '\300\257' > "$TMP/зіпсований.lisp"
pozytsiya --файл-ук "$TMP/зіпсований.lisp"
printf 'ні\000так' > "$TMP/нуль.lisp"
pozytsiya --файл-ук "$TMP/нуль.lisp"
printf 'так ні\n' > "$TMP/дві-форми.lisp"
pozytsiya --файл-ук "$TMP/дві-форми.lisp"

# .sens — тільки фізична двійкова програма; текстовий режим відмовляє.
printf '\143\211\006\241' > "$TMP/двійкова.sens"
cp "$TMP/двійкова.sens" "$TMP/початкова.sens"
vidmova --файл-ук "$TMP/двійкова.sens"
cmp "$TMP/двійкова.sens" "$TMP/початкова.sens"
vidmova --файл-ук "$TMP/відсутній.lisp"
: > "$TMP/порожній.lisp"
vidmova --файл-ук "$TMP/порожній.lisp"
head -c 16777217 /dev/zero > "$TMP/завеликий.lisp"
vidmova --файл-ук "$TMP/завеликий.lisp"

if "$BIN" --виконати "$TMP/приклад.lisp" >"$TMP/output" 2>"$TMP/errors"; then
  echo 'ПОМИЛКА-ТЕСТУ: невідомий режим прийнято' >&2; exit 1
else
  test "$?" -eq 64
fi
test ! -s "$TMP/output"
grep -q 'Використання:' "$TMP/errors"
CHECKS=$((CHECKS+1))
echo "УКРАЇНСЬКА-ПРОЄКЦІЯ-D3-OK перевірок=$CHECKS FPC=виконано stdout=точні-біти хибні=відхилено фізичний-sens=окремий-формат повний-REPL=ні"
