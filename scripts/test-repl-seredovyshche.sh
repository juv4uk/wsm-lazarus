#!/usr/bin/env bash
# Задача — постійне середовище REPL: визначення мусять переживати ОДНЕ
# обчислення. Цей скрипт доводить це двома свідками, і жоден з них не є
# переказом коду:
#
#   ПОЗИТИВНИЙ — сесія: форма 1 визначає імʼя (D5:00111 встановити-ім'я),
#     форма 2 в ОКРЕМОМУ обчисленні читає його й дістає збережене значення.
#   НЕГАТИВНИЙ — без сесії: ТА САМА форма 2 на тому самому обчислювачі й на
#     свіжому мусить дати помилку. Якщо обидва дають одне й те саме — свідок
#     нічого не доводить, і це збій, а не зелено.
#
# Межа доказу названа прямо: це оточення СЕСІЇ одного процесу, а не
# збереження на диск, не Core4 і не повний REPL SENS. Лічба перевірок
# свідка замикання (62) і паритет 16/16 цим скриптом не змінюються.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
: "${FPC:=fpc}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ZGHODA=0
ZBOI=0
NEPIDTVERDZHENO=0

zghoda() { ZGHODA=$((ZGHODA + 1)); echo "ok $1 -> $2"; }
zbii()   { ZBOI=$((ZBOI + 1));   echo "ПОМИЛКА-ТЕСТУ: $1 — очікували $2; фактично: $3"; }
nv()     { NEPIDTVERDZHENO=$((NEPIDTVERDZHENO + 1)); echo "NOT_VERIFIED $1: $2"; }

echo "REPL-СЕРЕДОВИЩЕ-СТАН sha=$(git rev-parse --short HEAD 2>/dev/null || echo невідомо)"

# ---------------------------------------------------------- 0. Передумови
test -d external/sens/lib/domains || {
  echo 'НЕ ЗКОМПІЛЬОВАНО: немає pinned доменів external/sens (див. scripts/sync-authority.sh)' >&2
  exit 2
}
command -v "$FPC" >/dev/null 2>&1 || {
  echo "НЕ ЗКОМПІЛЬОВАНО: немає FPC ($FPC)" >&2
  exit 127
}

# --- Обмеження задачі: заборонені модулі не змінені ----------------------
# src/wsm.nativeeval.pas — дозволений цією задачею; усі інші заборонені
# модулі лишаються під охороною, і перевірка лишається однією.
echo '--- обмеження: заборонені модулі не змінені'
zmineno=$(git status --porcelain -- src/wsm.irwidefront.pas \
  src/wsm.exactir.pas src/wsm.gc.pas src/wsm.t5m.pas 'src/wsm.elf*.pas' 2>/dev/null || true)
if [ -z "$zmineno" ]; then
  zghoda 'zaboroneni-faily-ne-zmineno' \
    'irwidefront, exactir, gc, t5m і wsm.elf* чисті щодо HEAD'
else
  zbii 'zaboroneni-faily-ne-zmineno' 'чистий git status для заборонених файлів' \
    "$(printf '%s' "$zmineno" | tr '\n' ' ')"
fi

# --- Бюджет FPC-workflow не збільшений (новий workflow не створено) ------
echo '--- обмеження: бюджет FPC-workflow'
if byudzhet=$(bash ./scripts/check-workflow-fpc-budget.sh 2>&1); then
  zghoda 'byudzhet-fpc-workflow' "$(printf '%s' "$byudzhet" | grep -E '^FPC-BUDGET ' | tail -1)"
else
  zbii 'byudzhet-fpc-workflow' 'FPC-BUDGET-PASS без нових push/pull_request workflow' \
    "$(printf '%s' "$byudzhet" | tail -3 | tr '\n' ' ')"
fi

# ------------------------------------------------- 1. СВІДОК ВИКОНАННЯ
echo '--- свідок: визначення переживає обчислення'
mkdir -p build/m0.2/test-units build/m0.2/bin
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/test-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-repl-seredovyshche "$ROOT/scripts/test-repl-seredovyshche.pas" \
  > "$TMP/build-svidok.log" 2>&1 || {
    echo 'НЕ ЗКОМПІЛЬОВАНО: свідок не зібрався' >&2
    cat "$TMP/build-svidok.log" >&2
    exit 3
  }
SV="$ROOT/build/m0.2/bin/test-repl-seredovyshche"
test -x "$SV" || { echo 'НЕ ЗКОМПІЛЬОВАНО: немає двійкового свідка' >&2; exit 3; }

"$SV" > "$TMP/svidok.out" 2> "$TMP/svidok.err"
SV_KOD=$?
cat "$TMP/svidok.out"
if [ -s "$TMP/svidok.err" ]; then
  echo '  (stderr свідка)'
  sed 's/^/  /' "$TMP/svidok.err"
fi
SV_OK=$(grep -c '^ok ' "$TMP/svidok.out" || true)
SV_ZBII=$(grep -c '^ПОМИЛКА-ТЕСТУ: ' "$TMP/svidok.out" || true)
ZGHODA=$((ZGHODA + SV_OK))
ZBOI=$((ZBOI + SV_ZBII))
if [ "$SV_KOD" -eq 1 ] && [ "$SV_ZBII" -eq 0 ]; then
  zbii 'код-виходу-свідка' 'код 1 лише за наявності збоїв' 'код 1 без жодного збою'
fi
echo "  кроків свідка: ok=$SV_OK збоїв=$SV_ZBII код=$SV_KOD"

# ------------------------------------ 2. ПОЗИТИВНИЙ І НЕГАТИВНИЙ — ОКРЕМО
# Свідок доводить постійне середовище лише тоді, коли БЕЗ нього імʼя не
# видно. Тому обидва значення витягуються з виводу й порівнюються тут.
znach() { # znach <імʼя кроку>
  { grep -E "^ok $1 -> " "$TMP/svidok.out" | head -1 | sed 's/.* -> //' |
    sed 's/[[:space:]]*$//'; }
}

vyznachennia=$(znach 'vyznachennia-v-pershomu-obchyslenni')
chytannia=$(znach 'chytannia-v-okremomu-obchyslenni')
if [ -n "$vyznachennia" ] && [ "$vyznachennia" = "$chytannia" ]; then
  zghoda 'pozytyvnyi-vyznachennia-perezhyvaie-obchyslennia' \
    "визначення=$vyznachennia читання=$chytannia (те саме значення)"
else
  zbii 'pozytyvnyi-vyznachennia-perezhyvaie-obchyslennia' \
    'читання в окремому обчисленні дає те саме значення, що й визначення' \
    "визначення=${vyznachennia:-—} читання=${chytannia:-—}"
fi

# Негативний свідок: два обчислення БЕЗ сесії. Обидва мусять відмовити.
if grep -q '^ok negatyvnyi-bez-sesii-te-same-otochemnia -> ' "$TMP/svidok.out" &&
   grep -q '^ok negatyvnyi-bez-sesii-svizhe-otochemnia -> ' "$TMP/svidok.out"; then
  zghoda 'negatyvnyi-bez-sesii-im-ia-nevydyme' \
    'те саме оточення двічі і свіже оточення — обидва відмовили'
else
  zbii 'negatyvnyi-bez-sesii-im-ia-nevydyme' \
    'без сесії читання імені відмовляє в обох випадках' \
    "$(grep -c '^ok negatyvnyi-bez-sesii' "$TMP/svidok.out" || true) підтверджених відмов із 2"
fi

# Головна умова: без сесії — помилка, із сесією — значення. Однакова
# відповідь означала б, що сесія не додає нічого.
if [ -n "$chytannia" ] &&
   grep -q 'помилка=unknown native binding' "$TMP/svidok.out"; then
  zghoda 'negatyvnyi-vidrizniaietsia-vid-pozytyvnoho' \
    "із сесією=$chytannia, без сесії=помилка 'unknown native binding'"
else
  zbii 'negatyvnyi-vidrizniaietsia-vid-pozytyvnoho' \
    "із сесією — значення, без сесії — помилка" \
    "із сесією=${chytannia:-—}; рядка про помилку без сесії немає"
fi

# Замикання з попередньої форми: тіло — вузол AST тієї форми. Якщо сесія
# не тримає документ, тут було б читання звільненої памʼяті, а не 0.
vyklyk=$(znach 'zamykannia-vyklykaietsia-z-inshoho-obchyslennia')
if [ "$vyklyk" = '0' ]; then
  zghoda 'zamykannia-perezhyvaie-obchyslennia' \
    'виклик замикання з наступної форми дає 0, а не помилку'
else
  zbii 'zamykannia-perezhyvaie-obchyslennia' 'значення 0' "${vyklyk:-—}"
fi

# ------------------------------------------------ 3. МЕЖІ ДОКАЗУ (явно)
echo '--- межі доказу'
nv 'zberezhennia-na-dysk' \
  'середовище живе в памʼяті одного процесу; між процесами воно НЕ зберігається і не заявляється'
nv 'povnyi-repl-sens' \
  'сеанс виконує лише наявні механізми G3.2 (D3, D5 мітка/SETQ, D10 замикання); Core4, GC і довільні визначення не заявлені'

# ------------------------------------------------------------ 4. ПІДСУМОК
echo "REPL-СЕРЕДОВИЩЕ-ПІДСУМОК перевірок=$((ZGHODA + ZBOI)) ok=$ZGHODA збоїв=$ZBOI not_verified=$NEPIDTVERDZHENO"
if [ "$ZBOI" -gt 0 ]; then
  echo 'ВИСНОВОК: постійного середовища НЕМАЄ — визначення не переживають обчислення.'
  exit 1
fi
echo 'ВИСНОВОК: визначення переживають обчислення в сесії; без сесії те саме імʼя не видно.'
if [ "$NEPIDTVERDZHENO" -gt 0 ]; then
  echo "ВИСНОВОК-НЕПОВНИЙ: not_verified=$NEPIDTVERDZHENO — названі вище межі НЕ перевірені, і це не зелено."
fi
exit 0
