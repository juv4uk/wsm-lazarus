#!/usr/bin/env bash
# Issue #490 — живий прогін двох голів драбини, які досі відмовляли:
#   D5:00110  встановити          (pinned lib/domains/d5.lisp:15)
#   D10:0101100010 зв'язати-параметри (pinned lib/domains/d10.lisp:365,
#                                     закон core1.lisp:193-207)
#
# Навіщо окремий .sh: компіляція — не виконання. Тут ТІ САМІ голови
# проходять ДВОМА незалежними шляхами:
#   1) scripts/test-vstanovyty-zviazaty.pas — власна програма, сесійне
#      оточення: запис, читання наступною формою, обчислена назва,
#      спільна комірка, арність, продовження оточення;
#   2) src/sens_oracle.lpr — чужий вхід, документований протокол
#      READY / OK<TAB> / ERR<TAB>, сирі дескриптори 0/1.
# Якщо обидва кажуть те саме — це властивість механізму, а не адаптера.
#
# Результат прогону — не «зелено за всяку ціну». Якщо голова не виконується,
# скрипт друкує фактичний вивід і виходить із кодом 1.
#
# Нових workflow не створюємо: викликається з core1-closure-witness.yml,
# і бюджет scripts/check-workflow-fpc-budget.sh не змінюється.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
: "${FPC:=fpc}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ZGHODA=0
ZBOI=0

zghoda() { ZGHODA=$((ZGHODA + 1)); echo "ok $1 -> $2"; }
zbii()   { ZBOI=$((ZBOI + 1));   echo "ПОМИЛКА-ТЕСТУ: $1 — очікували $2; фактично: $3"; }

echo "ВСТАНОВИТИ-ЗВЯЗАТИ-СТАН sha=$(git rev-parse --short HEAD 2>/dev/null || echo невідомо)"

# ---------------------------------------------------------- 0. Передумови
command -v "$FPC" >/dev/null 2>&1 || {
  echo "НЕ ЗКОМПІЛЬОВАНО: немає FPC ($FPC)" >&2
  exit 127
}
test -d external/sens/lib/domains || {
  echo 'НЕ ЗКОМПІЛЬОВАНО: немає pinned доменів external/sens (див. scripts/sync-authority.sh)' >&2
  exit 2
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

# --- Бюджет FPC-workflow не збільшений (нового workflow не створено) -----
echo '--- обмеження: бюджет FPC-workflow'
if byudzhet=$(bash ./scripts/check-workflow-fpc-budget.sh 2>&1); then
  zghoda 'byudzhet-fpc-workflow' "$(printf '%s' "$byudzhet" | grep -E '^FPC-BUDGET ' | tail -1)"
else
  zbii 'byudzhet-fpc-workflow' 'FPC-BUDGET-PASS без нових push/pull_request workflow' \
    "$(printf '%s' "$byudzhet" | tail -3 | tr '\n' ' ')"
fi

# ------------------------------------------ 1. Свідок .pas (сесійне оточення)
echo '--- шлях 1: scripts/test-vstanovyty-zviazaty.pas (сесія + обидві голови)'
mkdir -p build/m0.2/test-units build/m0.2/bin
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/test-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-vstanovyty-zviazaty "$ROOT/scripts/test-vstanovyty-zviazaty.pas" \
  > "$TMP/build-svidok.log" 2>&1 || {
    echo 'НЕ ЗКОМПІЛЬОВАНО: свідок не зібрався' >&2
    cat "$TMP/build-svidok.log" >&2
    exit 3
  }
SV="$ROOT/build/m0.2/bin/test-vstanovyty-zviazaty"
test -x "$SV" || { echo 'НЕ ЗКОМПІЛЬОВАНО: немає двійкового свідка' >&2; exit 3; }

set +e
"$SV" > "$TMP/svidok.out" 2> "$TMP/svidok.err"
SV_KOD=$?
set -e
cat "$TMP/svidok.out"
if [ -s "$TMP/svidok.err" ]; then
  echo '  (stderr свідка)'
  sed 's/^/  /' "$TMP/svidok.err"
fi
SV_OK=$(grep -c '^ok ' "$TMP/svidok.out" || true)
SV_ZBII=$(grep -c '^ПОМИЛКА-ТЕСТУ: ' "$TMP/svidok.out" || true)
ZGHODA=$((ZGHODA + SV_OK))
ZBOI=$((ZBOI + SV_ZBII))
if [ "$SV_KOD" -ne 0 ] && [ "$SV_ZBII" -eq 0 ]; then
  zbii 'kod-vyhodu-svidka' 'kod 1 lyše za naiavnist zboiv' "kod $SV_KOD"
fi
echo "  кроків свідка: ok=$SV_OK збоїв=$SV_ZBII код=$SV_KOD"

# ------------------------------- 2. Той самий механізм через протокол оракула
echo '--- шлях 2: src/sens_oracle.lpr (протокол READY / OK<TAB> / ERR<TAB>)'
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/test-units" -FE"$ROOT/build/m0.2/bin" \
  -osens-oracle-vstanovyty "$ROOT/src/sens_oracle.lpr" \
  > "$TMP/build-oracle.log" 2>&1 || {
    echo 'НЕ ЗКОМПІЛЬОВАНО: оракул не зібрався' >&2
    cat "$TMP/build-oracle.log" >&2
    exit 3
  }
ORACLE="$ROOT/build/m0.2/bin/sens-oracle-vstanovyty"
test -x "$ORACLE" || { echo 'НЕ ЗКОМПІЛЬОВАНО: немає двійкового оракула' >&2; exit 3; }

# oracle_vypadok <назва> <форма> <очікування>
#   ok             — код 0 і OK<TAB> (форму прийнято)
#   err:<підрядок> — код 2 і ERR<TAB>…<підрядок>
oracle_vypadok() {
  local nazva="$1" forma="$2" ochik="$3" kod ridok
  printf '%s\n' "$forma" > "$TMP/in"
  set +e
  timeout 45s "$ORACLE" < "$TMP/in" > "$TMP/out" 2> "$TMP/err"
  kod=$?
  set -e
  if ! head -1 "$TMP/out" | grep -qx 'READY'; then
    zbii "$nazva" 'перший рядок READY' "немає READY: $(tr '\n' '|' < "$TMP/out")"
    return
  fi
  ridok=$(sed -n '2p' "$TMP/out")
  case "$ochik" in
    ok)
      if [ "$kod" -eq 0 ] && printf '%s' "$ridok" | grep -q '^OK	' &&
         ! printf '%s' "$ridok" | grep -qF 'unsupported D5 callable' &&
         ! printf '%s' "$ridok" | grep -qF 'bind-params: not implemented'; then
        zghoda "$nazva" "$ridok"
      else
        zbii "$nazva" 'код 0 і OK<TAB> без давньої відмови' "код=$kod $ridok"
      fi
      ;;
    err:*)
      local pid="${ochik#err:}"
      if [ "$kod" -eq 2 ] && printf '%s' "$ridok" | grep -q '^ERR	' &&
         printf '%s' "$ridok" | grep -qF -- "$pid"; then
        zghoda "$nazva" "$ridok"
      else
        zbii "$nazva" "код 2 і ERR<TAB>…$pid" "код=$kod $ridok"
      fi
      ;;
  esac
}

# D5:00110 — назва обчислюється з D7-даних, значення обчислюється.
oracle_vypadok 'оракул-встановити-D5-00110' \
  '(встановити (як-є х) так)' ok
oracle_vypadok 'оракул-встановити-обчислена-назва' \
  '(встановити (перше (як-є (х у))) ні)' ok
oracle_vypadok 'оракул-встановити-без-виразу' \
  '(встановити (як-є х))' 'err:D5:00110'
oracle_vypadok 'оракул-встановити-назва-не-значення' \
  '(встановити () так)' 'err:'

# D10:0101100010 — три аргументи, дві РІЗНІ помилки арності.
oracle_vypadok 'оракул-звязати-параметри' \
  '(зв'"'"'язати-параметри (як-є (х)) (сполучити так ()) ())' ok
oracle_vypadok 'оракул-звязати-параметри-замало-аргументів' \
  '(зв'"'"'язати-параметри (як-є (х)) () ())' 'err:ARITY: TOO-FEW-ARGUMENTS'
oracle_vypadok 'оракул-звязати-параметри-забагато-аргументів' \
  '(зв'"'"'язати-параметри (як-є ()) (сполучити так ()) ())' \
  'err:ARITY: TOO-MANY-ARGUMENTS'
oracle_vypadok 'оракул-звязати-параметри-без-оточення' \
  '(зв'"'"'язати-параметри (як-є (х)) (сполучити так ()))' 'err:D10:0101100010'

# ----------------------------------------------------------- 3. Підсумок
echo "ВСТАНОВИТИ-ЗВЯЗАТИ-ПІДСУМОК перевірок=$((ZGHODA + ZBOI)) ok=$ZGHODA збоїв=$ZBOI"
if [ "$ZBOI" -gt 0 ]; then
  echo 'ВИСНОВОК: голови встановити (D5:00110) і звʼязати-параметри (D10:0101100010) у цьому стані НЕ ВИКОНУЮТЬСЯ на поверхні (див. збої вище).'
  exit 1
fi
echo 'ВИСНОВОК: обидві голови виконані фактичним виводом — запис за обчисленою назвою і звʼязування параметрів підтверджені двома шляхами.'
