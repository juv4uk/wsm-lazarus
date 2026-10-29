#!/usr/bin/env bash
# G2.8: реальний FPC build та фізичні позитивні/негативні .sens.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null || { echo 'ПОМИЛКА: немає Free Pascal' >&2; exit 127; }
mkdir -p build/m0.2/bin build/m0.2/test-units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/test-units" \
  -FE"$ROOT/build/m0.2/bin" -osensbinary "$ROOT/src/sensbinary.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/test-units" \
  -FE"$ROOT/build/m0.2/bin" -osenst5m "$ROOT/src/senst5m.lpr"
BIN="$ROOT/build/m0.2/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf '10 111 00 1 000 01\n' > "$TMP/форма.words"
"$BIN/senst5m" --pack-words "$TMP/форма.words" > "$TMP/форма.sens"
"$BIN/sensbinary" --аналіз "$TMP/форма.sens" > "$TMP/вихід.txt"
grep -Fx 'ДВІЙКОВЕ-СЛОВО індекс=2 форма=0 домен=3 біти=111 порожнє=ні ук=сполучити' "$TMP/вихід.txt"
grep -Fx 'ДВІЙКОВЕ-СЛОВО індекс=4 форма=0 домен=1 біти=1 порожнє=ні ук=так' "$TMP/вихід.txt"
grep -Fx 'ДВІЙКОВЕ-СЛОВО індекс=5 форма=0 домен=3 біти=000 порожнє=так ук=немає' "$TMP/вихід.txt"
grep -Fx 'ДВІЙКОВЕ-ПІДСУМОК слів=3 викличність=не-перевірено виконання=не-перевірено' "$TMP/вихід.txt"
"$BIN/sensbinary" --аналіз "$TMP/форма.sens" > "$TMP/повтор.txt"
cmp "$TMP/вихід.txt" "$TMP/повтор.txt"

printf '0 00 000\n' > "$TMP/корені.words"
"$BIN/senst5m" --pack-words "$TMP/корені.words" > "$TMP/корені.sens"
"$BIN/sensbinary" --аналіз "$TMP/корені.sens" > "$TMP/корені.txt"
grep -F 'індекс=1 форма=0 домен=1 біти=0 порожнє=ні' "$TMP/корені.txt"
grep -F 'індекс=3 форма=1 домен=3 біти=000 порожнє=так' "$TMP/корені.txt"

# Відмова не повинна вивести жодного часткового результату у stdout.
must_reject() {
  local label=$1 path=$2
  if "$BIN/sensbinary" --аналіз "$path" > "$TMP/негатив.out" 2> "$TMP/негатив.err"; then
    echo "ДВІЙКОВЕ-ТЕСТ-ПОМИЛКА прийнято: $label" >&2; exit 1
  fi
  test ! -s "$TMP/негатив.out" || { echo "ДВІЙКОВЕ-ТЕСТ-ПОМИЛКА частковий stdout: $label" >&2; exit 1; }
  grep -F 'ДВІЙКОВЕ-ПОМИЛКА' "$TMP/негатив.err"
}
printf '\363' > "$TMP/байт.sens"
must_reject 'поганий байт T5M' "$TMP/байт.sens"
printf '10 111\n' > "$TMP/незакрито.words"
"$BIN/senst5m" --pack-words "$TMP/незакрито.words" > "$TMP/незакрито.sens"
must_reject 'незакритий D2' "$TMP/незакрито.sens"
grep -F 'слово=3:' "$TMP/негатив.err"
printf '1111111111\n' > "$TMP/ширина.words"
"$BIN/senst5m" --pack-words "$TMP/ширина.words" > "$TMP/ширина.sens"
must_reject 'непідтриманий D10' "$TMP/ширина.sens"
: > "$TMP/порожній.sens"
must_reject 'порожній файл' "$TMP/порожній.sens"
must_reject 'відсутній файл' "$TMP/немає.sens"
must_reject 'не двійковий вхід' "$TMP/форма.words"
truncate -s $((4*1024*1024+1)) "$TMP/завеликий.sens"
must_reject 'фізичний ліміт' "$TMP/завеликий.sens"
if (cd "$TMP" && "$BIN/sensbinary" --аналіз "$TMP/форма.sens" > "$TMP/негатив.out" 2> "$TMP/негатив.err"); then
  echo 'ДВІЙКОВЕ-ТЕСТ-ПОМИЛКА прийнято неприкріплені таблиці' >&2; exit 1
fi
test ! -s "$TMP/негатив.out"
grep -F 'ДВІЙКОВЕ-ПОМИЛКА' "$TMP/негатив.err"

# G2.37 — ТОЙ САМИЙ фізичний T5M, тепер дерево з pinned шісткою проєкцій.
# Тестуємо справжню D2 структуру, точні адреси (не лише текстовий grep).
printf '10 111 00 1 000 01 00 0\n' > "$TMP/дерево.words"
"$BIN/senst5m" --pack-words "$TMP/дерево.words" > "$TMP/дерево.sens"
"$BIN/sensbinary" --дерево "$TMP/дерево.sens" > "$TMP/дерево.txt"
grep -Fq 'ДЕРЕВО-ВУЗОЛ номер=0 форма=0 батько=-1 дитина=-1 глибина=0 вид=список-D2 фізичне=так слово=1 трити=[0,2) байти=[0,1) домен=немає проєкції=немає' "$TMP/дерево.txt"
grep -Fq 'номер=1 форма=0 батько=0 дитина=0 глибина=1 вид=точне-слово фізичне=так слово=2 трити=[3,6) байти=[0,2) домен=D3 біти=111 ук=сполучити укр=сполучити san=saṃyuj en=cons LISP=CONS sym=+:' "$TMP/дерево.txt"
grep -Fq 'номер=2 форма=0 батько=0 дитина=1 глибина=1 вид=точне-слово фізичне=так слово=4 трити=[10,11) байти=[2,3) домен=D1 біти=1 ук=так укр=так san=ām en=yes LISP=T sym=()' "$TMP/дерево.txt"
grep -Fq 'номер=3 форма=0 батько=0 дитина=2 глибина=1 вид=порожнє-D3:000 фізичне=так слово=5 трити=[12,15) байти=[2,3) домен=D3 біти=000 ук=() укр=()' "$TMP/дерево.txt"
grep -Fq 'номер=4 форма=1 батько=-1 дитина=-1 глибина=0 вид=точне-слово фізичне=так слово=8 трити=[22,23) байти=[4,5) домен=D1 біти=0 ук=ні укр=ні' "$TMP/дерево.txt"
grep -Fxq 'ДЕРЕВО-ПІДСУМОК вузлів=5 викличність=не-перевірено виконання=не-перевірено' "$TMP/дерево.txt"
"$BIN/sensbinary" --дерево "$TMP/дерево.sens" > "$TMP/дерево-повтор.txt"
cmp "$TMP/дерево.txt" "$TMP/дерево-повтор.txt"

# Похідна крапкова пара не є ще одним фізичним словом/доменом.
printf '10 1 00 0 11 10 1 01 01\n' > "$TMP/пара.words"
"$BIN/senst5m" --pack-words "$TMP/пара.words" > "$TMP/пара.sens"
"$BIN/sensbinary" --дерево "$TMP/пара.sens" > "$TMP/пара.txt"
grep -Fq 'номер=0 форма=0 батько=-1 дитина=-1 глибина=0 вид=похідна-пара фізичне=ні опора=1 координата=немає домен=немає проєкції=немає' "$TMP/пара.txt"
grep -Fq 'вид=точне-слово фізичне=так слово=2 ' "$TMP/пара.txt"
grep -Fq 'вид=список-D2 фізичне=так слово=6 ' "$TMP/пара.txt"
grep -Fq 'ДЕРЕВО-ПІДСУМОК вузлів=6 ' "$TMP/пара.txt"

# D7 є даними, шість pinned колонок: керувальний SYN без ук/укр,
# а друкована точна W7 адреса не встановлює мовної викличності.
printf '0010110 0100001\n' > "$TMP/д7.words"
"$BIN/senst5m" --pack-words "$TMP/д7.words" > "$TMP/д7.sens"
"$BIN/sensbinary" --дерево "$TMP/д7.sens" > "$TMP/д7.txt"
grep -Fq 'домен=D7 біти=0010110 ук=() укр=()' "$TMP/д7.txt"
grep -Fq 'домен=D7 біти=0100001 ук=' "$TMP/д7.txt"
grep -Fq ' LISP=() sym=' "$TMP/д7.txt"

must_reject_tree() {
  local label=$1 path=$2
  if "$BIN/sensbinary" --дерево "$path" >"$TMP/дерево-відмова.out" 2>"$TMP/дерево-відмова.err"; then
    echo "ДЕРЕВО-CLI-ПОМИЛКА прийнято: $label" >&2; exit 1
  fi
  test ! -s "$TMP/дерево-відмова.out" ||
    { echo "ДЕРЕВО-CLI-ПОМИЛКА частковий stdout: $label" >&2; exit 1; }
  grep -Fq 'ДВІЙКОВЕ-ПОМИЛКА' "$TMP/дерево-відмова.err"
}
must_reject_tree 'неканонічний T5M' "$TMP/байт.sens"
must_reject_tree 'обрізане D2 закриття' "$TMP/незакрито.sens"
must_reject_tree 'недопущений D10' "$TMP/ширина.sens"
printf '000000000000\n' > "$TMP/д12.words"
"$BIN/senst5m" --pack-words "$TMP/д12.words" > "$TMP/д12.sens"
must_reject_tree 'D12 не в D1–D9 binder' "$TMP/д12.sens"
must_reject_tree 'українська проєкція не фізичний .sens' "$TMP/форма.words"
must_reject_tree 'неіснуючий файл' "$TMP/немає.sens"
must_reject_tree 'фізичний ліміт' "$TMP/завеликий.sens"
# 4097 незалежних D1:1 roots дозволені фізично, але вміщення звіту 4096
# є локальним host ресурсним gate: жодних часткових 4096 вузлів у stdout.
for ((i=0; i<4097; i++)); do
  if (( i )); then printf ' '; fi
  printf 1
done > "$TMP/забагато.words"
printf '\n' >> "$TMP/забагато.words"
"$BIN/senst5m" --pack-words "$TMP/забагато.words" > "$TMP/забагато.sens"
must_reject_tree '4097 вузлів' "$TMP/забагато.sens"
grep -Fq '4096 вузлів' "$TMP/дерево-відмова.err"
if (cd "$TMP" && "$BIN/sensbinary" --дерево "$TMP/дерево.sens" \
  > "$TMP/дерево-відмова.out" 2> "$TMP/дерево-відмова.err"); then
  echo 'ДЕРЕВО-CLI-ПОМИЛКА неприкріплені pinned таблиці' >&2; exit 1
fi
test ! -s "$TMP/дерево-відмова.out"
grep -Fq 'ДВІЙКОВЕ-ПОМИЛКА' "$TMP/дерево-відмова.err"
echo 'ДВІЙКОВЕ-ДЕРЕВО-CLI-ГАРАЗД FPC=справжній вузлів=5 фізика=трит/байт pinned-проєкцій=6 D7=дані похідна-пара=без-адреси негативів=9 старий-режим=збережено'

echo 'ДВІЙКОВЕ-CLI-ГАРАЗД FPC=фізичний T5M=так D2=так координати=точні негативні=відхилено викличність=не-доведено'
