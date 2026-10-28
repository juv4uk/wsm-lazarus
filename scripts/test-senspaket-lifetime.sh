#!/usr/bin/env bash
# G5.14 — реальний Free Pascal heaptrc для пакетного CLI.
# Лише фізичне виконання вже допущених форм; .lisp — окрема укр-проєкція.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=$(printenv FPC || printf fpc)
command -v "$FPC_BIN" >/dev/null || {
  echo 'ПАКЕТ-ПАМ’ЯТЬ-БЛОКЕР: відсутній Free Pascal' >&2; exit 127;
}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osenspaket "$ROOT/src/senspaket.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osensvykon "$ROOT/src/sensvykon.lpr"
BIN="$TMP/bin/senspaket"
PACK="$TMP/bin/senst5m"
SINGLE="$TMP/bin/sensvykon"
test -x "$BIN" && test -x "$PACK" && test -x "$SINGLE"
CHECKS=0

pack() {
  local label="$1" words="$2"
  printf '%s\n' "$words" >"$TMP/$label.words"
  "$PACK" --pack-words "$TMP/$label.words" >"$TMP/$label.sens"
}
pack 'успіх' '1 10 111 00 1 000 01 0'
pack 'один' '1'
pack 'два' '0 1'
pack 'невиклична-голова' '1 10 000 00 1 01'
pack 'незакритий' '1 10 111'
pack 'крапка' '1 10 111 1 11 01'
printf '\363' >"$TMP/зіпсований.sens"
: >"$TMP/порожній.sens"
head -c 4194305 /dev/zero >"$TMP/надмірний.sens"
printf '(сполучити так ())\n' >"$TMP/звичайна_проєкція_укр.lisp"
{
  for ((i=0;i<1025;i++)); do
    if ((i)); then printf ' '; fi
    printf 1
  done
  printf '\n'
} >"$TMP/1025.words"
"$PACK" --pack-words "$TMP/1025.words" >"$TMP/1025.sens"

check_heap() {
  if grep -Eiq 'heap dump|unfreed memory blocks|call trace for block|runtime error' "$TMP/stderr"; then
    echo 'ПАКЕТ-ПАМ’ЯТЬ-ПОМИЛКА: heaptrc або runtime error' >&2
    cat "$TMP/stderr" >&2
    exit 1
  fi
}

success() {
  local file="$1" expectation="$2"
  printf '%b' "$expectation" >"$TMP/expected"
  "$BIN" --пакет "$TMP/$file.sens" >"$TMP/stdout" 2>"$TMP/stderr"
  if ! cmp -s "$TMP/stdout" "$TMP/expected" || test -s "$TMP/stderr"; then
    echo 'ПАКЕТ-ПАМ’ЯТЬ-ПОМИЛКА: успіх не byte-exact' >&2
    cat "$TMP/stdout" "$TMP/stderr" >&2
    exit 1
  fi
  check_heap
  CHECKS=$((CHECKS+1))
}
reject() {
  local filepath="$1" diagnostic="$2" code=0
  if "$BIN" --пакет "$filepath" >"$TMP/stdout" 2>"$TMP/stderr"; then
    echo "ПАКЕТ-ПАМ’ЯТЬ-ПОМИЛКА: хибний вхід прийнято ($filepath)" >&2
    exit 1
  else
    code=$?
  fi
  if test "$code" -ne 2 || test -s "$TMP/stdout" ||
    ! grep -F 'ПАКЕТ-SENS-ПОМИЛКА' "$TMP/stderr" >/dev/null; then
    echo "ПАКЕТ-ПАМ’ЯТЬ-ПОМИЛКА: статус=$code або частковий stdout" >&2
    cat "$TMP/stdout" "$TMP/stderr" >&2
    exit 1
  fi
  if [[ -n "$diagnostic" ]]; then
    grep -F "$diagnostic" "$TMP/stderr" >/dev/null || {
      echo "ПАКЕТ-ПАМ’ЯТЬ-ПОМИЛКА: немає $diagnostic" >&2
      cat "$TMP/stderr" >&2
      exit 1
    }
  fi
  check_heap
  CHECKS=$((CHECKS+1))
}
usage() {
  local code=0
  if "$BIN" "$@" >"$TMP/stdout" 2>"$TMP/stderr"; then
    echo 'ПАКЕТ-ПАМ’ЯТЬ-ПОМИЛКА: недопустимий режим прийнято' >&2
    exit 1
  else
    code=$?
  fi
  if test "$code" -ne 64 || test -s "$TMP/stdout" ||
     ! grep -F 'Використання:' "$TMP/stderr" >/dev/null; then
    echo "ПАКЕТ-ПАМ’ЯТЬ-ПОМИЛКА: код використання=$code" >&2
    cat "$TMP/stderr" >&2
    exit 1
  fi
  check_heap
  CHECKS=$((CHECKS+1))
}

for repetition in 1 2 3; do
  success 'успіх' '1\n(1)\n0\n'
  success 'один' '1\n'
  success 'два' '0\n1\n'
  reject "$TMP/невиклична-голова.sens" 'форма=2 слово=3'
  reject "$TMP/незакритий.sens" 'слово=4'
  reject "$TMP/крапка.sens" ''
  reject "$TMP/зіпсований.sens" ''
done
reject "$TMP/1025.sens" ''
reject "$TMP/відсутній.sens" ''
reject "$TMP/порожній.sens" ''
reject "$TMP/надмірний.sens" ''
usage
usage --невідомо "$TMP/один.sens"
usage --пакет "$TMP/звичайна_проєкція_укр.lisp"
usage --пакет
"$SINGLE" --виконати "$TMP/один.sens" >"$TMP/single"
printf '1\n' >"$TMP/single.expected"
cmp "$TMP/single" "$TMP/single.expected"
CHECKS=$((CHECKS+1))
echo "ПАКЕТ-ПАМ’ЯТЬ-ГАРАЗД перевірок=$CHECKS FPC=реальний heaptrc=без-витоків коди=0,2,64 фізичний_sens=так lisp=лише_проєкція"
