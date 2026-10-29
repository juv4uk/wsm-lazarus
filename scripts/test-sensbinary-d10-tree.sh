#!/usr/bin/env bash
# G2.47: явний фізичний D10→D2→дерево без власного reader чи мовних законів.
# Канонічний вхід — лише двійковий T5M .sens; .words — приватний fixture.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
: "${FPC:=fpc}"
./scripts/check-pin.sh
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
  "$BIN/senst5m" --пакувати-слова "$TMP/$name.words" > "$TMP/$name.sens"
}
reject() {
  local mode=$1 file=$2 label=$3
  if "$BIN/sensbinary" "$mode" "$file" >"$TMP/відмова.out" 2>"$TMP/відмова.err"; then
    echo "Д10-ДЕРЕВО-ПОМИЛКА: прийнято $label" >&2
    exit 1
  fi
  if test -s "$TMP/відмова.out"; then
    echo "Д10-ДЕРЕВО-ПОМИЛКА: частковий stdout $label" >&2
    exit 1
  fi
  grep -Fq 'ДВІЙКОВЕ-ПОМИЛКА' "$TMP/відмова.err" || {
    cat "$TMP/відмова.err" >&2
    echo "Д10-ДЕРЕВО-ПОМИЛКА: без діагностики $label" >&2
    exit 1
  }
}

# Реальні фізичні корені; W10 із провідними нулями і з усіма одиницями.
# Вкладений D7 SYN є текстовими даними; D3:000 не D1:0.
pack 'корені' '10 0000000000 00 0010110 000 01 00 1111111111 00 0'
"$BIN/sensbinary" --дерево-д10 "$TMP/корені.sens" > "$TMP/дерево.txt"
grep -Fq 'номер=0 форма=0 батько=-1 дитина=-1 глибина=0 вид=список-D2 ' "$TMP/дерево.txt"
grep -Fq 'номер=1 форма=0 батько=0 дитина=0 глибина=1 вид=точне-слово фізичне=так слово=2 трити=[3,13) байти=[0,3) домен=D10 біти=0000000000 ук=немає-можливості' "$TMP/дерево.txt"
grep -Fq 'номер=2 форма=0 батько=0 дитина=1 глибина=1 вид=точне-слово ' "$TMP/дерево.txt"
grep -Fq 'домен=D7 біти=0010110 ук=() укр=()' "$TMP/дерево.txt"
grep -Fq 'номер=3 форма=0 батько=0 дитина=2 глибина=1 вид=порожнє-D3:000 ' "$TMP/дерево.txt"
grep -Fq 'домен=D3 біти=000 ук=() укр=()' "$TMP/дерево.txt"
grep -Fq 'номер=4 форма=1 батько=-1 дитина=-1 глибина=0 вид=точне-слово ' "$TMP/дерево.txt"
grep -Fq 'домен=D10 біти=1111111111 ук=' "$TMP/дерево.txt"
grep -Fq 'номер=5 форма=2 батько=-1 дитина=-1 глибина=0 вид=точне-слово ' "$TMP/дерево.txt"
grep -Fq 'домен=D1 біти=0 ук=ні укр=ні' "$TMP/дерево.txt"
grep -Fxq 'ДЕРЕВО-ПІДСУМОК вузлів=6 викличність=не-перевірено виконання=не-перевірено' "$TMP/дерево.txt"
test "$(wc -l < "$TMP/дерево.txt")" -eq 7
# Шість pinned проєкцій ідентичні координаті, не opcode і не dispatch.
grep -Fq ' san=' "$TMP/дерево.txt"
grep -Fq ' en=' "$TMP/дерево.txt"
grep -Fq ' LISP=' "$TMP/дерево.txt"
grep -Fq ' sym=' "$TMP/дерево.txt"
"$BIN/sensbinary" --дерево-д10 "$TMP/корені.sens" > "$TMP/повтор.txt"
cmp "$TMP/дерево.txt" "$TMP/повтор.txt"
# Старий режим не отримує D10 за мовчазним widening; аналіз-д10 незмінний.
reject --дерево "$TMP/корені.sens" 'старий D1–D9 режим'
"$BIN/sensbinary" --аналіз-д10 "$TMP/корені.sens" > "$TMP/аналіз.txt"
grep -Fq 'домен=10 біти=0000000000' "$TMP/аналіз.txt"

# Фізична крапкова пара — лише похідний вузол без вигаданого слова.
pack 'пара' '10 0000000000 00 0 11 10 1111111111 01 01'
"$BIN/sensbinary" --дерево-д10 "$TMP/пара.sens" > "$TMP/пара.txt"
grep -Fq 'номер=0 форма=0 батько=-1 дитина=-1 глибина=0 вид=похідна-пара фізичне=ні опора=1 координата=немає' "$TMP/пара.txt"
grep -Fq 'домен=D10 біти=0000000000' "$TMP/пара.txt"
grep -Fq 'домен=D10 біти=1111111111' "$TMP/пара.txt"

# Новий режим приймає той самий D1–D9 документ без зміни геометрії.
pack 'малий' '10 111 00 1 000 01 00 0'
"$BIN/sensbinary" --дерево "$TMP/малий.sens" > "$TMP/старе.txt"
"$BIN/sensbinary" --дерево-д10 "$TMP/малий.sens" > "$TMP/нове.txt"
cmp "$TMP/старе.txt" "$TMP/нове.txt"

pack 'ширина-11' '00000000000'
pack 'ширина-12' '000000000000'
pack 'пізня-ширина' '0000000000 00 000000000000'
pack 'незакрито' '10 0000000000'
reject --дерево-д10 "$TMP/ширина-11.sens" 'W11'
reject --дерево-д10 "$TMP/ширина-12.sens" 'W12 не є автоматично числом'
reject --дерево-д10 "$TMP/пізня-ширина.sens" 'пізня W12 після валідного W10'
reject --дерево-д10 "$TMP/незакрито.sens" 'D2 EOF'
printf '\363' > "$TMP/зіпсований.sens"
reject --дерево-д10 "$TMP/зіпсований.sens" 'неканонічний T5M'
: > "$TMP/порожній.sens"
reject --дерево-д10 "$TMP/порожній.sens" 'порожній T5M'
printf '(як-є так)\n' > "$TMP/проєкція.lisp"
reject --дерево-д10 "$TMP/проєкція.lisp" '.lisp не фізичний вхід'
reject --дерево-д10 "$TMP/відсутній.sens" 'відсутній .sens'
if (cd "$TMP" && "$BIN/sensbinary" --дерево-д10 "$TMP/корені.sens" \
    >"$TMP/відмова.out" 2>"$TMP/відмова.err"); then
  echo 'Д10-ДЕРЕВО-ПОМИЛКА: без pinned таблиць успіх' >&2
  exit 1
fi
test ! -s "$TMP/відмова.out"
grep -Fq 'ДВІЙКОВЕ-ПОМИЛКА' "$TMP/відмова.err"

# Усі попередні механічні/негативні тести D1–D9 та явного D10.
bash "$ROOT/scripts/test-sensbinary-d10.sh"
echo 'Д10-ДЕРЕВО-ГАРАЗД FPC=справжній T5M=фізичний D10=явний проєкцій=6 D7=SYN-дані W11/W12=відмовлено старий-D9=незмінний'
