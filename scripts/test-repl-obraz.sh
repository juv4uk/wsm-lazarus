#!/usr/bin/env bash
# Образ середовища REPL: середовище зберігається на диск і відновлюється
# в ІНШОМУ процесі. Це перший крок до системних образів (save-lisp-and-die
# у SBCL), і цей скрипт доводить рівно те, що доводить, — не більше:
#
#   ПОЗИТИВНИЙ — ДВА РІЗНІ ПРОЦЕСИ:
#     процес А (роль zberegty) визначає імена і зберігає образ у файл,
#     процес Б (роль zavanty) — окремий запуск, окремий pid — завантажує
#     образ і читає імʼя. Значення порівнює ЦЕЙ скрипт, а не програма:
#     інакше доказ був би переказом власного коду.
#   НЕГАТИВНИЙ — процес В (роль bez-obrazu) на тому самому файлі образу,
#     але БЕЗ завантаження: те саме імʼя мусить дати
#     'unknown native binding'. Якщо й там було б значення — образ нічого
#     не додає, і це збій, а не зелено.
#   МЕЖА — процес Г (роль zipsovany): зіпсований образ мусить відмовити,
#     а не стати «схожим на середовище».
#
# Межа доказу названа прямо: переносяться ЗВʼЯЗУВАННЯ верхнього рівня.
# Тіла замикань (вузли AST документа сесії) процес не переживають, і
# свідок вимагає, щоб це було видно, а не замовчане.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
: "${FPC:=fpc}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

OBRAZ="$TMP/seredovyshche.sens"
ZIPSOVANY="$TMP/zipsovanyi.sens"

ZGHODA=0
ZBOI=0
NEPIDTVERDZHENO=0

zghoda() { ZGHODA=$((ZGHODA + 1)); echo "ok $1 -> $2"; }
zbii()   { ZBOI=$((ZBOI + 1));   echo "ПОМИЛКА-ТЕСТУ: $1 — очікували $2; фактично: $3"; }
nv()     { NEPIDTVERDZHENO=$((NEPIDTVERDZHENO + 1)); echo "NOT_VERIFIED $1: $2"; }

echo "REPL-ОБРАЗ-СТАН sha=$(git rev-parse --short HEAD 2>/dev/null || echo невідомо)"

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
echo '--- свідок: образ на диску, два процеси'
mkdir -p build/m0.2/test-units build/m0.2/bin
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/test-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-repl-obraz "$ROOT/scripts/test-repl-obraz.pas" \
  > "$TMP/build-svidok.log" 2>&1 || {
    echo 'НЕ ЗКОМПІЛЬОВАНО: свідок образу не зібрався' >&2
    cat "$TMP/build-svidok.log" >&2
    exit 3
  }
SV="$ROOT/build/m0.2/bin/test-repl-obraz"
test -x "$SV" || { echo 'НЕ ЗКОМПІЛЬОВАНО: немає двійкового свідка образу' >&2; exit 3; }

# Кожен запуск — окремий процес; роль передається аргументом.
zapusty() { # zapusty <роль> <файл> <журнал>
  "$SV" "$1" "$2" > "$3" 2> "$3.err"
  local kod=$?
  cat "$3"
  if [ -s "$3.err" ]; then
    echo '  (stderr свідка)'
    sed 's/^/  /' "$3.err"
  fi
  local ok zb
  ok=$(grep -c '^ok ' "$3" || true)
  zb=$(grep -c '^ПОМИЛКА-ТЕСТУ: ' "$3" || true)
  ZGHODA=$((ZGHODA + ok))
  ZBOI=$((ZBOI + zb))
  echo "  кроків ролі $1: ok=$ok збоїв=$zb код=$kod"
  return $kod
}

zapusty zberegty  "$OBRAZ"     "$TMP/a.out" || zbii 'rol-zberegty' 'код 0' "$(tail -1 "$TMP/a.out")"
zapusty zavanty   "$OBRAZ"     "$TMP/b.out" || zbii 'rol-zavanty'  'код 0' "$(tail -1 "$TMP/b.out")"
zapusty bez-obrazu "$OBRAZ"    "$TMP/c.out" || zbii 'rol-bez-obrazu' 'код 0' "$(tail -1 "$TMP/c.out")"
zapusty zipsovany "$ZIPSOVANY" "$TMP/g.out" || zbii 'rol-zipsovany' 'код 0' "$(tail -1 "$TMP/g.out")"

# --------------------------------------- 2. ЦЕ СПРАВДІ ДВА РІЗНІ ПРОЦЕСИ
# Інакше «відновлення» могло б бути тим самим процесом, що й збереження.
pid() { grep -o 'pid=[0-9]*' "$1" | head -1 | sed 's/pid=//'; }
PID_A=$(pid "$TMP/a.out")
PID_B=$(pid "$TMP/b.out")
PID_C=$(pid "$TMP/c.out")
if [ -n "$PID_A" ] && [ -n "$PID_B" ] && [ -n "$PID_C" ] &&
   [ "$PID_A" != "$PID_B" ] && [ "$PID_A" != "$PID_C" ] && [ "$PID_B" != "$PID_C" ]; then
  zghoda 'rizni-protsesy' "А=$PID_A Б=$PID_B В=$PID_C — три різні pid"
else
  zbii 'rizni-protsesy' 'три різні pid' "А=${PID_A:-—} Б=${PID_B:-—} В=${PID_C:-—}"
fi

# ------------------------------------------------ 3. ФАЙЛ ОБРАЗУ НА ДИСКУ
if [ -s "$OBRAZ" ]; then
  zghoda 'obraz-na-disku' "файл $(basename "$OBRAZ") = $(wc -c < "$OBRAZ") байтів"
else
  zbii 'obraz-na-disku' 'непорожній файл образу' 'файлу немає або він порожній'
fi

# ------------------------------------ 4. ПОЗИТИВНИЙ: А зберіг, Б прочитав
znach() { # znach <імʼя кроку> <журнал>
  local line
  line=$(grep -F "ok $1 -> " "$2" | head -1)
  printf '%s' "${line#ok $1 -> }" | sed 's/[[:space:]]*$//'
}

a_chyslo=$(znach 'a-vyznachennia-chyslo' "$TMP/a.out")
b_chyslo=$(znach 'b-chyslo' "$TMP/b.out")
if [ -n "$b_chyslo" ] && [ "$b_chyslo" = '1' ]; then
  zghoda 'b-chytannia-chysla-pislia-zavantazhennia' \
    "процес Б дістав із образу значення '$b_chyslo'"
else
  zbii 'b-chytannia-chysla-pislia-zavantazhennia' \
    'значення 1, прочитане в іншому процесі з образу' "${b_chyslo:-—}"
fi

# Те саме значення в А і в Б: визначення не переписане в Б, воно прийшло.
if [ -n "$a_chyslo" ] && [ "$a_chyslo" = "$b_chyslo" ]; then
  zghoda 'chyslo-te-same-v-obokh-protsesakh' "А=$a_chyslo Б=$b_chyslo"
else
  zbii 'chyslo-te-same-v-obokh-protsesakh' 'те саме значення в А і Б' \
    "А=${a_chyslo:-—} Б=${b_chyslo:-—}"
fi

a_perelik=$(znach 'a-perelik-dosi' "$TMP/a.out")
b_perelik=$(znach 'b-perelik' "$TMP/b.out")
if [ -n "$a_perelik" ] && [ "$a_perelik" = "$b_perelik" ]; then
  zghoda 'struktura-vidnovlena-baivt-v-baivt' \
    "А=$a_perelik Б=$b_perelik (те саме)"
else
  zbii 'struktura-vidnovlena-baijt-v-baivt' \
    'той самий відбиток структури в А і Б' \
    "А=${a_perelik:-—} Б=${b_perelik:-—}"
fi

# ------------------------------------------ 5. НЕГАТИВНИЙ: БЕЗ ЗАВАНТАЖЕННЯ
# Той самий файл образу лежить на диску; процес В його просто не читає.
if grep -q '^ok n-bez-obrazu-im-ia-nevydyme -> .*помилка=unknown native binding' "$TMP/c.out"; then
  zghoda 'negatyvnyi-bez-zavantazhennia' \
    "без завантаження те саме імʼя = 'unknown native binding'"
else
  zbii 'negatyvnyi-bez-zavantazhennia' \
    "відмова 'unknown native binding' без завантаження образу" \
    "$(grep -E '^ok n-|^ПОМИЛКА-ТЕСТУ: n-' "$TMP/c.out" | tr '\n' ' ')"
fi

# Негативний мусить ВІДРІЗНЯТИСЯ від позитивного: якщо обидва дають те
# саме, свідок нічого не доводить.
if [ "$b_chyslo" = '1' ] && grep -q 'unknown native binding' "$TMP/c.out"; then
  zghoda 'negatyvnyi-vidrizniaietsia-vid-pozytyvnoho' \
    "із образом=$b_chyslo, без образу=помилка 'unknown native binding'"
else
  zbii 'negatyvnyi-vidrizniaietsia-vid-pozytyvnoho' \
    'із образом — значення, без образу — помилка' \
    "із образом=${b_chyslo:-—}; відмови без образу немає"
fi

# ------------------------------------- 6. МЕЖА ЗРІЗУ: ТІЛА НЕ ПЕРЕЖИЛИ
# Замикання було в А (3 звʼязування), в образ пішло 2, і в Б його імʼя
# невидиме. Якби воно мовчки «працювало», це була б вигадка.
if grep -q '^ok a-obraz-zberezheno -> .*записано=2 пропущено=1' "$TMP/a.out" &&
   grep -q '^ok b-obraz-zavantazheno -> 2' "$TMP/b.out" &&
   grep -q '^ok b-tilo-zamykannia-ne-perezhylo -> .*unknown native binding' "$TMP/b.out"; then
  zghoda 'tilo-zamykannia-ne-perezhylo' \
    'замикання назване як пропущене (пропущено=1) і в Б невидиме'
else
  zbii 'tilo-zamykannia-ne-perezhylo' \
    'пропущене замикання назване в А і невидиме в Б' \
    "$(grep -E 'obraz-zberezheno|obraz-zavantazheno|tilo-zamykannia' "$TMP/a.out" "$TMP/b.out" | tr '\n' ' ')"
fi

# ---------------------------------- 7. ЗІПСОВАНИЙ ОБРАЗ: ВІДМОВА, НЕ ЗДОГАД
if grep -q '^ok z-zipsovanyi-obraz-vidmovliaie -> .*відмова' "$TMP/g.out"; then
  zghoda 'zipsovanyi-obraz-vidmovliaie' \
    "$(grep -o 'відмова: .*' "$TMP/g.out" | head -1)"
else
  zbii 'zipsovanyi-obraz-vidmovliaie' 'відмова на зіпсованих байтах' \
    "$(grep -E '^ok z-|^ПОМИЛКА-ТЕСТУ: z-' "$TMP/g.out" | tr '\n' ' ')"
fi

# ------------------------------------------------ 8. МЕЖІ ДОКАЗУ (явно)
echo '--- межі доказу'
nv 'tilo-zamykannia' \
  'переносяться лише звʼязування верхнього рівня; тіла замикань (FNodes) — вузли AST документа сесії — процес не переживають'
nv 'imeni-poza-d7' \
  'імʼя мусить мати проєкцію Д7 (українські літери й ASCII-координати таблиці); імʼя поза нею в образ не потрапляє і рахується як пропущене'
nv 'odyn-obraz' \
  'образ не містить історії форм, бюджетів кроків/клітинок і стану GC; це звʼязування, а не повний дамп процесу'

# ------------------------------------------------------------ 9. ПІДСУМОК
echo "REPL-ОБРАЗ-ПІДСУМОК перевірок=$((ZGHODA + ZBOI)) ok=$ZGHODA збоїв=$ZBOI not_verified=$NEPIDTVERDZHENO"
if [ "$ZBOI" -gt 0 ]; then
  echo 'ВИСНОВОК: образу середовища НЕМАЄ — звʼязування не переживають процес.'
  exit 1
fi
echo 'ВИСНОВОК: звʼязування середовища збережено в образ і відновлено в ІНШОМУ процесі; без образу те саме імʼя невидиме.'
if [ "$NEPIDTVERDZHENO" -gt 0 ]; then
  echo "ВИСНОВОК-НЕПОВНИЙ: not_verified=$NEPIDTVERDZHENO — названі вище межі НЕ перевірені, і це не зелено."
fi
exit 0
