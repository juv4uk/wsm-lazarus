#!/usr/bin/env bash
# G2.15: справжня FPC діагностика фізичних .sens з ПОВНОЮ pinned укр проєкцією.
set -Eeuo pipefail
trap 'status=$?; echo "ГОЛОВИ-ТЕСТ-ПОМИЛКА: рядок=$LINENO команда=$BASH_COMMAND статус=$status" >&2; exit "$status"' ERR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
BIN_DIR="$ROOT/build/m0.2/bin"
UNIT_DIR="$ROOT/build/m0.2/test-units"
mkdir -p "$BIN_DIR" "$UNIT_DIR"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" \
  -osensholovy "$ROOT/src/sensholovy.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$UNIT_DIR" -FE"$BIN_DIR" \
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
grep -F 'ГОЛОВА список=0 форма=0 вид=точна перший-вузол=1 домен=3 біти=111 слово=2 трити=[3,6) байти=[0,2) ук=сполучити укр=сполучити' "$TMP/точна.out"
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

# У реальному pinned D4:0101 колонки ВІДРІЗНЯЮТЬСЯ:
# ук=порожнє?, укр=порожній?; точний ключ ніяк не змінюється.
echo 'ПЕРЕВІРКА-ГОЛІВ: pinned D4:0101' >&2
grep -F '(0101 (ук порожнє?) (укр порожній?)' \
  "$ROOT/external/sens/lib/domains/d4.lisp" > /dev/null
make_sens 'повна-українська' '10 0101 01'
"$BIN_DIR/sensholovy" --голови "$TMP/повна-українська.sens" \
  "$ROOT/external/sens" > "$TMP/повна-українська.out"
grep -F 'домен=4 біти=0101 слово=2 ' "$TMP/повна-українська.out" >/dev/null
grep -F ' ук=порожнє? укр=порожній?' "$TMP/повна-українська.out" >/dev/null
"$BIN_DIR/sensholovy" --голови "$TMP/повна-українська.sens" \
  "$ROOT/external/sens" > "$TMP/повна-повтор.out"
cmp "$TMP/повна-українська.out" "$TMP/повна-повтор.out"

echo 'ПЕРЕВІРКА-ГОЛІВ: повні укр назви D4 пройдено' >&2

# Фізичний свідок із СПРАВЖНЬОГО pinned SENS, не вигадана програма:
# читати без sparse checkout із точного gitlink upstream.
PIN=$(git -C "$ROOT/external/sens" rev-parse HEAD)
GITLINK=$(git ls-tree HEAD external/sens | awk '{print $3}')
test "$PIN" = "$GITLINK"
git -C "$ROOT/external/sens" show \
  "$PIN:examples/migrated/smoke-cond.sens" > "$TMP/умова-корінь.sens"
"$BIN_DIR/sensholovy" --голови "$TMP/умова-корінь.sens" \
  "$ROOT/external/sens" > "$TMP/умова-корінь.out"
grep -F 'домен=3 біти=110 ' "$TMP/умова-корінь.out" >/dev/null
grep -F ' ук=за-умовою укр=за-умовою' "$TMP/умова-корінь.out" >/dev/null
grep -F 'викличність=не-доведено' "$TMP/умова-корінь.out" >/dev/null

# Негатив: немає ратифікованого поля укр в ОДНІЙ таблиці.
# Вхід коректний T5M; вихід MUST бути порожнім при дефекті authority.
mkdir -p "$TMP/corrupt-pin/lib"
cp -a "$ROOT/external/sens/lib/domains" "$TMP/corrupt-pin/lib/"
sed -i 's/(укр порожній?)/(підміна порожній?)/' \
  "$TMP/corrupt-pin/lib/domains/d4.lisp"
grep -F '(підміна порожній?)' "$TMP/corrupt-pin/lib/domains/d4.lisp" >/dev/null
reject "$TMP/повна-українська.sens" "$TMP/corrupt-pin"
if ! grep -F 'помилка pinned укр проєкції:' "$TMP/відмова.err" >/dev/null ||
   ! grep -F 'D4: 0101' "$TMP/відмова.err" >/dev/null; then
  cat "$TMP/відмова.err" >&2
  echo 'ГОЛОВИ-ТЕСТ-ПОМИЛКА: відхилення не пов’язане з укр полем' >&2
  exit 1
fi

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
echo 'ДВІЙКОВІ-ГОЛОВИ-КЛІ-ГАРАЗД: FPC=так T5M=фізичний D2=дерево проєкція=ук+укр pinned-D4=0101 справжній-sens=так діагностика=байти-трити викличність=не-доведено'
