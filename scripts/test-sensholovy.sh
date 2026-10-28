#!/usr/bin/env bash
# G2.13: справжня FPC діагностика фізичних .sens без семантичного dispatch.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
BIN_DIR="$ROOT/build/m0.2/bin"
UNIT_DIR="$ROOT/build/m0.2/test-units"
mkdir -p "$BIN_DIR" "$UNIT_DIR"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" \
  -osensholovy "$ROOT/src/sensholovy.lpr"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" \
  -osenst5m "$ROOT/src/senst5m.lpr"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
make_sens() {
  local name="$1" words="$2"
  printf '%s\n' "$words" > "$TMP/$name.words"
  "$BIN_DIR/senst5m" --пакувати-слова "$TMP/$name.words" > "$TMP/$name.sens"
}
reject() {
  local file="$1" authority="$2"
  if "$BIN_DIR/sensholovy" --голови "$file" "$authority" > "$TMP/відмова.out" 2> "$TMP/відмова.err"; then
    echo "ГОЛОВИ-ТЕСТ-ПОМИЛКА: недопустимий вхід прийнято: $file" >&2
    exit 1
  fi
  test ! -s "$TMP/відмова.out"
  grep -F 'ДВІЙКОВІ-ГОЛОВИ-ПОМИЛКА' "$TMP/відмова.err" >/dev/null
}
make_sens 'точна' '10 111 00 1 000 01'
"$BIN_DIR/sensholovy" --голови "$TMP/точна.sens" "$ROOT/external/sens" > "$TMP/точна.out"
grep -F 'ГОЛОВА список=0 форма=0 вид=точна перший-вузол=1 домен=3 біти=111 слово=2 трити=[3,6) байти=[0,2) ук=сполучити' "$TMP/точна.out"
grep -F 'ПІДСУМОК списків=1 точних=1 структурних=0 порожніх=0 викличність=не-доведено' "$TMP/точна.out"
"$BIN_DIR/sensholovy" --голови "$TMP/точна.sens" "$ROOT/external/sens" > "$TMP/повтор.out"
cmp "$TMP/точна.out" "$TMP/повтор.out"

make_sens 'вкладені' '10 10 1 01 000 01'
"$BIN_DIR/sensholovy" --голови "$TMP/вкладені.sens" "$ROOT/external/sens" > "$TMP/вкладені.out"
grep -F 'вид=структурна перший-вузол=1 структура=список-D2 слово=2' "$TMP/вкладені.out"
grep -F 'вид=точна перший-вузол=2 домен=1 біти=1' "$TMP/вкладені.out"
grep -F 'ПІДСУМОК списків=2 точних=1 структурних=1 порожніх=0' "$TMP/вкладені.out"

make_sens 'порожній-список' '10 01'
"$BIN_DIR/sensholovy" --голови "$TMP/порожній-список.sens" "$ROOT/external/sens" > "$TMP/порожній.out"
grep -F 'вид=без-голови перший-вузол=-1' "$TMP/порожній.out"
grep -F 'ПІДСУМОК списків=1 точних=0 структурних=0 порожніх=1' "$TMP/порожній.out"

make_sens 'порожня-структура' '10 000 01'
"$BIN_DIR/sensholovy" --голови "$TMP/порожня-структура.sens" "$ROOT/external/sens" > "$TMP/порожня-структура.out"
grep -F 'вид=структурна перший-вузол=1 структура=порожня-D3:000' "$TMP/порожня-структура.out"

make_sens 'домен-один' '10 0 01'
"$BIN_DIR/sensholovy" --голови "$TMP/домен-один.sens" "$ROOT/external/sens" > "$TMP/домен-один.out"
grep -F 'вид=точна перший-вузол=1 домен=1 біти=0' "$TMP/домен-один.out"

make_sens 'пара' '10 1 11 0 01'
"$BIN_DIR/sensholovy" --голови "$TMP/пара.sens" "$ROOT/external/sens" > "$TMP/пара.out"
grep -F 'ПІДСУМОК списків=0 точних=0 структурних=0 порожніх=0' "$TMP/пара.out"

make_sens 'дві-форми' '10 111 01 10 0 01'
"$BIN_DIR/sensholovy" --голови "$TMP/дві-форми.sens" "$ROOT/external/sens" > "$TMP/дві-форми.out"
grep -F 'ГОЛОВА список=0 форма=0 вид=точна' "$TMP/дві-форми.out"
grep -F 'ГОЛОВА список=2 форма=1 вид=точна' "$TMP/дві-форми.out"
grep -F 'ПІДСУМОК списків=2 точних=2' "$TMP/дві-форми.out"

printf '\363' > "$TMP/зіпсований.sens"
reject "$TMP/зіпсований.sens" "$ROOT/external/sens"
: > "$TMP/порожній.sens"
reject "$TMP/порожній.sens" "$ROOT/external/sens"
make_sens 'незакритий' '10 111'
reject "$TMP/незакритий.sens" "$ROOT/external/sens"
grep -F 'D2 слово=' "$TMP/відмова.err"

printf '(сполучити так)\n' > "$TMP/звичайна-укр.lisp"
reject "$TMP/звичайна-укр.lisp" "$ROOT/external/sens"
grep -F '.lisp є українською текстовою проєкцією' "$TMP/відмова.err"
reject "$TMP/точна.sens" "$ROOT/external/неіснує"
reject "$TMP/відсутній.sens" "$ROOT/external/sens"

if "$BIN_DIR/sensholovy" --невідомо "$TMP/точна.sens" "$ROOT/external/sens" > "$TMP/відмова.out" 2> "$TMP/відмова.err"; then
  echo 'ГОЛОВИ-ТЕСТ-ПОМИЛКА: невідома команда прийнята' >&2
  exit 1
fi
test ! -s "$TMP/відмова.out"
echo 'ДВІЙКОВІ-ГОЛОВИ-КЛІ-ГАРАЗД: FPC=так T5M=фізичний D2=дерево проєкція=укр діагностика=байти-трити викличність=не-доведено'
