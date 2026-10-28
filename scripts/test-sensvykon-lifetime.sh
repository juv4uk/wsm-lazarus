#!/usr/bin/env bash
# Реальне FPC -gh/heaptrc: нативний виконавець звільняється і після помилок.
# Семантичні закони і оракул SENS не визначаються цим тестом.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -osensvykon "$ROOT/src/sensvykon.lpr"
PACK="$TMP/bin/senst5m"
BIN="$TMP/bin/sensvykon"
test -x "$BIN"
test -x "$PACK"
CHECKS=0

pack() {
  local name="$1" words="$2"
  printf '%s\n' "$words" > "$TMP/$name.words"
  "$PACK" --pack-words "$TMP/$name.words" > "$TMP/$name.sens"
}
pack "сполучення" '10 111 1 000 01'
pack "один" '1'
pack "порожнє" '000'
pack "цитата" '10 001 000 01'
pack "синтаксис" '10 111 1'
pack "непідтверджене" '10 110 1 01'
printf '\363' > "$TMP/неканонічний.sens"
: > "$TMP/порожній-файл.sens"
head -c 4194305 /dev/zero > "$TMP/завеликий.sens"
cp "$TMP/цитата.sens" "$TMP/цитата-до.sens"

no_leak() {
  if grep -Eiq 'heap dump|unfreed memory blocks|call trace for block|runtime error' "$TMP/stderr"; then
    echo 'ПОМИЛКА-ЖИТТЄВОГО-ЦИКЛУ: FPC heaptrc або runtime exception' >&2
    cat "$TMP/stderr" >&2
    exit 1
  fi
}

success() {
  local file="$1" value="$2" expected
  printf '%s\n' "$value" > "$TMP/expected"
  "$BIN" --виконати "$TMP/$file.sens" > "$TMP/stdout" 2> "$TMP/stderr"
  if ! cmp -s "$TMP/stdout" "$TMP/expected" || test -s "$TMP/stderr"; then
    echo 'ПОМИЛКА-ЖИТТЄВОГО-ЦИКЛУ: позитивний результат не byte-exact' >&2
    cat "$TMP/stdout" "$TMP/stderr" >&2
    exit 1
  fi
  no_leak
  CHECKS=$((CHECKS+1))
}
reject() {
  local status=0
  if "$BIN" --виконати "$1" > "$TMP/stdout" 2> "$TMP/stderr"; then
    echo 'ПОМИЛКА-ЖИТТЄВОГО-ЦИКЛУ: недопущений вхід прийнято' >&2
    exit 1
  else
    status=$?
  fi
  if test "$status" -ne 2 || test -s "$TMP/stdout" ||
     ! grep -q 'ПОМИЛКА-ДВІЙКОВОГО-ВИКОНАННЯ' "$TMP/stderr"; then
    echo "ПОМИЛКА-ЖИТТЄВОГО-ЦИКЛУ: status=$status або частковий stdout" >&2
    cat "$TMP/stdout" "$TMP/stderr" >&2
    exit 1
  fi
  no_leak
  CHECKS=$((CHECKS+1))
}
bad_usage() {
  local status=0
  if "$BIN" "$@" > "$TMP/stdout" 2> "$TMP/stderr"; then
    echo 'ПОМИЛКА-ЖИТТЄВОГО-ЦИКЛУ: помилковий режим прийнято' >&2
    exit 1
  else
    status=$?
  fi
  if test "$status" -ne 64 || test -s "$TMP/stdout" ||
     ! grep -q 'Використання:' "$TMP/stderr"; then
    echo "ПОМИЛКА-ЖИТТЄВОГО-ЦИКЛУ: помилковий статус використання $status" >&2
    cat "$TMP/stderr" >&2
    exit 1
  fi
  no_leak
  CHECKS=$((CHECKS+1))
}

# Ті самі вже засвідчені механізми D1/D3; тут тестуємо лише CLI cleanup.
for repetition in 1 2 3; do
  success "сполучення" '(1)'
  success "один" '1'
  success "порожнє" '()'
  reject "$TMP/цитата.sens"
  grep -q 'слово=2' "$TMP/stderr"
  CHECKS=$((CHECKS+1))
  reject "$TMP/непідтверджене.sens"
  grep -q 'слово=2' "$TMP/stderr"
  CHECKS=$((CHECKS+1))
  reject "$TMP/синтаксис.sens"
  reject "$TMP/неканонічний.sens"
  grep -q 'слово=0' "$TMP/stderr"
  CHECKS=$((CHECKS+1))
done

reject "$TMP/відсутній.sens"
reject "$TMP/порожній-файл.sens"
reject "$TMP/завеликий.sens"
bad_usage
bad_usage --невідомий "$TMP/один.sens"
bad_usage --виконати "$TMP/один.words"
bad_usage --виконати
cmp "$TMP/цитата.sens" "$TMP/цитата-до.sens"
CHECKS=$((CHECKS+1))
echo "ДВІЙКОВИЙ-КЛІ-ПАМ’ЯТЬ-ГАРАЗД перевірок=$CHECKS FPC-heaptrc=чисто коди=0,2,64 stdout=атомарний .sens=фізичний Core4=НЕ_ВИКОНУЄТЬСЯ"
