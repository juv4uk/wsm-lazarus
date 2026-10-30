#!/usr/bin/env bash
# Задача #866 — незалежний свідок того, що замикання SENS ВИКОНУЮТЬСЯ,
# тобто що захоплене оточення справді бере участь у виклику через
# evlis/appq, а не що в src/wsm.nativeeval.pas є функції з такими назвами.
#
# ТРИ РІЗНІ ПИТАННЯ, ТРИ РІЗНІ ШЛЯХИ — навмисно не змішані:
#
#   1. ЧИ Є МЕХАНІЗМ У КОДІ (статичний факт). Читаємо
#      src/wsm.nativeeval.pas і друкуємо ФАКТ / NOT_VERIFIED. Це не доказ
#      виконання: файл із функцією Evlis може ніколи її не викликати.
#
#   2. ЧИ ВІН ВИКОНУЄТЬСЯ (субʼєкт). scripts/test-zamykannia-svidok.pas —
#      власна програма, що викликає сам механізм. Її вивід — спостереження,
#      а не доказ правильності: програма й механізм — один і той самий код.
#
#   3. ЧИ ЦЕ ПРАВИЛЬНО (незалежний оракул). Дві спроби, різного ґатунку:
#      3a. pinned SENS REPL — єдиний справжній авторитет. Якщо його немає
#          в середовищі, це NOT_VERIFIED із названою причиною, а не тихий
#          пропуск і не підміна.
#      3b. scripts/zamykannia-orakul-model.py — ДРУГА реалізація тих самих
#          законів іншою мовою (Python), виведена з pinned core1.lisp і
#          таблиць d5/d10, без жодного спільного рядка з Pascal. Це
#          диференційна перевірка, і в звіті вона названа моделлю, а не
#          авторитетом.
#
# НЕГАТИВНИЙ СВІДОК — обовʼязковий і перевіряється двічі:
#   * у .pas: форми з тілом (y) x і (y) y мусять дати РІЗНІ результати,
#     і форми мусять відрізнятися рівно одним байтом тіла;
#   * тут: якщо результати збіглися, свідок нічого не доводить — збій.
#
# НІЧОГО НЕ ВИМИКАЄТЬСЯ ЗАРАДИ ЗЕЛЕНОГО: будь-який збій — код 1.
# NOT_VERIFIED не робить прогін зеленим — він друкується окремим рядком і
# окремою лічбою, і підсумок прямо каже, що саме лишилось непідтвердженим.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
: "${FPC:=fpc}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Базова ревізія — остання, де оточення ще було ЗНІМКОМ. Задачею
# про спільну комірку змінено лише src/wsm.nativeeval.pas, тому той самий
# файл із цієї ревізії — це справжня попередня реалізація, а не переказ.
# Стала, а не HEAD~1: глибина історії клону не мусить ламати свідка.
SNAPSHOT_BASE=722650af9b41cdd4e36c6f66b818b8301f60e233

ZGHODA=0
ZBOI=0
NEPIDTVERDZHENO=0

zghoda() { ZGHODA=$((ZGHODA + 1)); echo "ok $1 -> $2"; }
zbii()   { ZBOI=$((ZBOI + 1));   echo "ПОМИЛКА-ТЕСТУ: $1 — очікували $2; фактично: $3"; }
nv()     { NEPIDTVERDZHENO=$((NEPIDTVERDZHENO + 1)); echo "NOT_VERIFIED $1: $2"; }

echo "ЗАМИКАННЯ-СВІДОК-СТАН sha=$(git rev-parse --short HEAD 2>/dev/null || echo невідомо)"
if [ -d external/sens/.git ] || [ -f external/sens/lib/core1.lisp ]; then
  echo "ЗАМИКАННЯ-СВІДОК-СТАН pinned-sens=$(git -C external/sens rev-parse HEAD 2>/dev/null || echo невідомо)"
else
  nv 'pinned-sens' 'external/sens не матеріалізовано; див. scripts/sync-authority.sh'
fi

# ---------------------------------------------------------------- 1. ФАКТИ
# Читаємо код, не припускаємо. Кожен рядок — окреме питання до файлу.
NATIVEEVAL=src/wsm.nativeeval.pas
[ -f "$NATIVEEVAL" ] || { echo "НЕ ЗКОМПІЛЬОВАНО: немає $NATIVEEVAL" >&2; exit 3; }

fakt_ye() { # fakt_ye <назва> <регекс> <що це доводить>
  local nazva="$1" re="$2" smysl="$3" n
  n=$(grep -cE -- "$re" "$NATIVEEVAL" || true)
  if [ "${n:-0}" -gt 0 ]; then
    zghoda "$nazva" "знайдено в $NATIVEEVAL ($n): $smysl"
  else
    nv "$nazva" "у $NATIVEEVAL немає /$re/ — $smysl; це задача #803, не свідка"
  fi
}

echo '--- 1. фактичний стан механізму в src/wsm.nativeeval.pas'
fakt_ye 'evlis-визначено' 'function TNativeEvaluator\.Evlis\(' \
  'обчислення аргументів існує як окрема функція'
fakt_ye 'appq-визначено' 'function TNativeEvaluator\.Appq\(' \
  'пакування обчислених аргументів існує як окрема функція'
n_call=$(grep -cE 'Appq\(Evlis\(N,1,Depth\+1,Env\),N\)' "$NATIVEEVAL" || true)
if [ "${n_call:-0}" -ge 2 ]; then
  zghoda 'evlis-appq-викликаються-у-гілці-виклику' \
    "знайдено ланцюг Appq(Evlis(N,1,Depth+1,Env),N) у ${n_call} місцях"
else
  nv 'evlis-appq-викликаються-у-гілці-виклику' \
    "ланцюг Appq(Evlis(...)) знайдено ${n_call:-0} раз(ів), треба >=2 (обчислена голова + імʼя в оточенні)"
fi
fakt_ye 'zakhoplene-otochemnia-peredaietsia-v-pairlis' \
  'Pairlis\(FCells\[A\]\.First,B,FClosureEnvs\[FCells\[A\]\.Rest\],N\)' \
  'виклик зшиває параметри з ЗАХОПЛЕНИМ оточенням, а не з порожнім'
fakt_ye 'mitka-D5-00100-адреса-в-драбині' 'Key\.Bits=%00100' \
  'гілка адреси 00100 (мітка) присутня'
fakt_ye 'mitka-shyryna-5' 'if Key\.Width=5 then begin' \
  'адреса мітки живе в ширині 5, тобто драбина її бачить'
fakt_ye 'adresy-vziati-z-pinned-tabl' 'd5\.lisp:13' \
  'адреса мітки звірена з pinned d5.lisp:13'
fakt_ye 'adresa-zamykannia-z-pinned-tabl' 'lib/domains/d10\.lisp' \
  'адреси замикання звірені з pinned lib/domains/d10.lisp'
fakt_ye 'adresa-0100111100-u-drabyni' 'Key\.Bits=%0100111100' \
  'гілка адреси 0100111100 (створити-лямбда-замикання) присутня в драбині'

# --- Обмеження задачі: заборонені файли не змінені -----------------------
# УВАГА: перевірка ЗВУЖЕНА, а не вимкнена. Задача #866 забороняла чіпати
# і src/wsm.nativeeval.pas; задача про спільну комірку його ДОЗВОЛЯЄ — це
# її суть. Тому з переліку прибрано рівно один файл, а всі інші заборонені
# модулі (irwidefront, exactir, gc, t5m і 43 wsm.elf*) лишаються під
# охороною, і сама перевірка лишається однією (лічба не змінюється).
echo '--- обмеження: заборонені модулі (крім nativeeval) не змінені'
zmineno=$(git status --porcelain -- src/wsm.irwidefront.pas \
  src/wsm.exactir.pas src/wsm.gc.pas src/wsm.t5m.pas 'src/wsm.elf*.pas' 2>/dev/null || true)
if [ -z "$zmineno" ]; then
  zghoda 'zaboroneni-faily-ne-zmineno' \
    'irwidefront, exactir, gc, t5m і wsm.elf* чисті щодо HEAD (nativeeval дозволено задачею)'
else
  zbii 'zaboroneni-faily-ne-zmineno' 'чистий git status для заборонених файлів' \
    "$(printf '%s' "$zmineno" | tr '\n' ' ')"
fi
# Не лічба, а факт для читача: nativeeval справді змінений цією задачею.
echo "  (nativeeval у робочому дереві: $(git status --porcelain -- src/wsm.nativeeval.pas 2>/dev/null | tr '\n' ' ' | sed 's/ *$//'))"

# ------------------------------------------------- 2. СВІДОК ВИКОНАННЯ
echo '--- 2. свідок: механізм викликається і дає результати'
command -v "$FPC" >/dev/null 2>&1 || {
  echo "НЕ ЗКОМПІЛЬОВАНО: немає FPC ($FPC)" >&2
  exit 127
}
mkdir -p build/m0.2/test-units build/m0.2/bin
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/test-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-zamykannia-svidok "$ROOT/scripts/test-zamykannia-svidok.pas" \
  > "$TMP/build-svidok.log" 2>&1 || {
    echo 'НЕ ЗКОМПІЛЬОВАНО: свідок не зібрався' >&2
    cat "$TMP/build-svidok.log" >&2
    exit 3
  }
SV="$ROOT/build/m0.2/bin/test-zamykannia-svidok"
test -x "$SV" || { echo 'НЕ ЗКОМПІЛЬОВАНО: немає двійкового свідка' >&2; exit 3; }

"$SV" > "$TMP/svidok.out" 2> "$TMP/svidok.err"
SV_KOD=$?
grep -v '^СВІДОК	' "$TMP/svidok.out" || true
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

# ------------------------------------ 3. НЕГАТИВНИЙ СВІДОК (окремо, явно)
# Свідок доводить захоплення лише тоді, коли не-захоплення дає ІНШЕ.
zah=$(grep -E '^ok zamykannia-zakhopliuie-otochemnia -> ' "$TMP/svidok.out" | sed 's/.* -> //')
bez=$(grep -E '^ok negatyvnyi-bez-zakhoplennia -> ' "$TMP/svidok.out" | sed 's/.* -> //')
if [ -n "$zah" ] && [ -n "$bez" ] && [ "$zah" != "$bez" ]; then
  zghoda 'negatyvnyi-svidok-okremo' "захоплення=$zah не-захоплення=$bez (різні)"
else
  zbii 'negatyvnyi-svidok-okremo' 'різні результати з захопленням і без' \
    "захоплення=${zah:-—} не-захоплення=${bez:-—}"
fi
# --- Негативний свідок СПІЛЬНОЇ КОМІРКИ: знімок і комірка мусять різнитись
komirka=$(grep -E '^ok spilna-komirka-bachyt-nove-znachennia -> ' "$TMP/svidok.out" | sed 's/.* -> //')
znimok=$(grep -E '^ok negatyvnyi-kopiia-ne-bachyt-novoho-znachennia -> ' "$TMP/svidok.out" | sed 's/.* -> //')
if [ -n "$komirka" ] && [ -n "$znimok" ] && [ "$komirka" != "$znimok" ]; then
  zghoda 'negatyvnyi-spilna-komirka-proty-znimka-okremo' \
    "спільна комірка=$komirka знімок=$znimok (різні)"
else
  zbii 'negatyvnyi-spilna-komirka-proty-znimka-okremo' \
    'різні результати зі спільною коміркою і зі знімком' \
    "комірка=${komirka:-—} знімок=${znimok:-—}"
fi
zah3=$(grep -E '^ok zakhoplene-znachennia-dvichi-rizni-arhumenty -> ' "$TMP/svidok.out" | sed 's/.* -> //')
bez4=$(grep -E '^ok negatyvnyi-dvichi-bez-zakhoplennia -> ' "$TMP/svidok.out" | sed 's/.* -> //')
if [ -n "$zah3" ] && [ -n "$bez4" ] && [ "$zah3" != "$bez4" ]; then
  zghoda 'negatyvnyi-svidok-dvichi-okremo' "захоплення=$zah3 не-захоплення=$bez4 (різні)"
else
  zbii 'negatyvnyi-svidok-dvichi-okremo' 'різні результати з захопленням і без' \
    "захоплення=${zah3:-—} не-захоплення=${bez4:-—}"
fi

# ------- 3в. ДИФЕРЕНЦІЙНИЙ СВІДОК: та сама форма на ПОПЕРЕДНІЙ реалізації
# Найсильніша форма негативного свідка: не «інша форма», а ТА САМА форма,
# обчислена старою реалізацією (знімок) і новою (спільна комірка). Якщо
# обидві дають однакове — зміна нічого не змінила, і свідок не доводить нічого.
echo '--- 3в. та сама форма на попередній реалізації (знімок) і на поточній'
OLD_SRC="$TMP/oldsrc"
if ! git cat-file -e "$SNAPSHOT_BASE:src/wsm.nativeeval.pas" 2>/dev/null; then
  nv 'dyferentsiia-proty-poperednoi-realizatsii' \
    "у цьому клоні немає обʼєкта $SNAPSHOT_BASE (мілкий клон?) — стару реалізацію не зібрати, порівняння не виконане"
else
  mkdir -p "$OLD_SRC" "$TMP/old-units"
  for f in src/*.pas; do
    b=$(basename "$f")
    if [ "$b" = wsm.nativeeval.pas ]; then
      git show "$SNAPSHOT_BASE:src/wsm.nativeeval.pas" > "$OLD_SRC/$b"
    else
      ln -sf "$ROOT/$f" "$OLD_SRC/$b"
    fi
  done
  cat > "$TMP/probe-spilna.pas" <<'PAS'
program probe_spilna_komirka;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,wsm.nativeeval,wsm.source;
const
  F:RawByteString=
    '((створити-лямбда-замикання (x) (решта (сполучити '+
    '(сполучити (мітка g (створити-лямбда-замикання (y) x)) '+
    '(встановити-ім''я x ні)) (g так)))) так)';
var E:TNativeEvaluator;
begin
  E:=TNativeEvaluator.Create('external/sens');
  try WriteLn(E.EvaluateSource(F)); finally E.Free; end;
end.
PAS
  if "$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$OLD_SRC" \
       -FU"$TMP/old-units" -FE"$TMP" -o"$TMP/probe-spilna-old" \
       "$TMP/probe-spilna.pas" > "$TMP/build-old.log" 2>&1; then
    STAR=$(cd "$ROOT" && "$TMP/probe-spilna-old" 2>/dev/null || echo '<збій>')
    NOVA=$(grep -E '^ok spilna-komirka-bachyt-nove-znachennia -> ' \
      "$TMP/svidok.out" | sed 's/.* -> //')
    if [ -n "$NOVA" ] && [ "$STAR" != "$NOVA" ]; then
      zghoda 'dyferentsiia-proty-poperednoi-realizatsii' \
        "та сама форма: попередня=$STAR поточна=$NOVA (різні)"
    else
      zbii 'dyferentsiia-proty-poperednoi-realizatsii' \
        'різні результати старої і нової реалізації на одній формі' \
        "попередня=${STAR:-—} поточна=${NOVA:-—}"
    fi
  else
    echo 'НЕ ЗКОМПІЛЬОВАНО: попередня реалізація не зібралася' >&2
    sed 's/^/  /' "$TMP/build-old.log" >&2
    exit 3
  fi
fi

# --------------------------------------------- 4. НЕЗАЛЕЖНИЙ ОРАКУЛ (3a)
echo '--- 3a. незалежний оракул: pinned SENS REPL'
SENS_REPL=""
for kandydat in "${SENS_REPL:-}" external/sens/target/release/sens \
  external/sens/target/debug/sens sens; do
  [ -n "$kandydat" ] || continue
  if command -v "$kandydat" >/dev/null 2>&1 || [ -x "$kandydat" ]; then
    SENS_REPL=$kandydat
    break
  fi
done
if [ -n "$SENS_REPL" ]; then
  zghoda 'pinned-sens-repl-znadeno' "$SENS_REPL"
  # Сам протокол REPL тут не вгадується: без документованого входу
  # викликати його означало б вигадати результат.
  nv 'pinned-sens-repl-протокол' \
    "REPL знайдено ($SENS_REPL), але протокол входу не зафіксовано в цьому свідку — звірка не виконана"
else
  ozvit=$(bash "$ROOT/scripts/check-oracle-feasibility.sh" 2>&1 || true)
  prychyna=$(printf '%s\n' "$ozvit" | grep -E 'ВЕРДИКТ' | head -1 | sed 's/^ORACLE-FEASIBILITY //')
  nv 'pinned-sens-repl' \
    "немає pinned SENS REPL у середовищі; ${prychyna:-причина не встановлена}. Незалежність від АВТОРИТЕТА лишається недоведеною — див. 3b (модель, не авторитет)"
fi

# --------------------------------------------- 5. НЕЗАЛЕЖНИЙ ОРАКУЛ (3b)
echo '--- 3b. друга реалізація іншою мовою: scripts/zamykannia-orakul-model.py'
MODEL="$ROOT/scripts/zamykannia-orakul-model.py"
if ! command -v python3 >/dev/null 2>&1; then
  nv 'model-orakul' 'немає python3 — диференційну звірку не виконано'
else
  # Форми беремо з виводу свідка: одне джерело істини, без дублювання.
  grep '^СВІДОК	' "$TMP/svidok.out" | cut -f4 > "$TMP/formy"
  grep '^СВІДОК	' "$TMP/svidok.out" | cut -f2,3,5 > "$TMP/svidok-fakty"
  if [ ! -s "$TMP/formy" ]; then
    nv 'model-orakul' 'свідок не надрукував жодного машинного рядка'
  else
    python3 "$MODEL" < "$TMP/formy" > "$TMP/model.out" 2> "$TMP/model.err"
    if [ -s "$TMP/model.err" ]; then
      echo '  (stderr моделі)'; sed 's/^/  /' "$TMP/model.err"
    fi
    python3 - "$TMP/svidok-fakty" "$TMP/model.out" > "$TMP/model.pid" 2>&1 <<'PY'
import sys
fakty = [l.rstrip("\n") for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
model = [l.rstrip("\n") for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
ok = zboi = 0
for fakt, m in zip(fakty, model):
    nazva, status, tekst = fakt.split("\t", 2)
    if m.split("\t", 1) == [status, tekst]:
        ok += 1
        print("ok model-zbigaie-%s -> %s %s" % (nazva, status, tekst))
    else:
        zboi += 1
        print("ПОМИЛКА-ТЕСТУ: model-rozbig-z-%s — очікували %s; фактично: %s"
              % (nazva, m.replace("\t", " "), status + " " + tekst))
if len(fakty) != len(model):
    zboi += 1
    print("ПОМИЛКА-ТЕСТУ: model-kiljkist — очікували %d рядків; фактично: %d"
          % (len(fakty), len(model)))
print("MODEL-PIDSUMOK ok=%d zboi=%d" % (ok, zboi))
sys.exit(1 if zboi else 0)
PY
    MODEL_KOD=$?
    cat "$TMP/model.pid"
    MODEL_OK=$(sed -nE 's/^MODEL-PIDSUMOK ok=([0-9]+) zboi=[0-9]+$/\1/p' "$TMP/model.pid")
    MODEL_ZBOI=$(sed -nE 's/^MODEL-PIDSUMOK ok=[0-9]+ zboi=([0-9]+)$/\1/p' "$TMP/model.pid")
    if [ -n "$MODEL_OK" ] && [ -n "$MODEL_ZBOI" ]; then
      ZGHODA=$((ZGHODA + MODEL_OK))
      ZBOI=$((ZBOI + MODEL_ZBOI))
    else
      zbii 'model-orakul' 'рядок MODEL-PIDSUMOK у виводі звірки' "код=$MODEL_KOD, рядка немає"
    fi
  fi
fi

# ------------------------------------------------------------ 6. ПІДСУМОК
echo "ЗАМИКАННЯ-СВІДОК-ПІДСУМОК перевірок=$((ZGHODA + ZBOI)) ok=$ZGHODA збоїв=$ZBOI not_verified=$NEPIDTVERDZHENO"
if [ "$ZBOI" -gt 0 ]; then
  echo 'ВИСНОВОК: механізм замикань у цьому стані НЕ ВИКОНУЄТЬСЯ або розходиться з моделлю (див. збої вище).'
  exit 1
fi
echo 'ВИСНОВОК: захоплення оточення замиканням підтверджене фактичним виводом, і негативний свідок розрізняє захоплення від не-захоплення.'
if [ "$NEPIDTVERDZHENO" -gt 0 ]; then
  echo "ВИСНОВОК-НЕПОВНИЙ: not_verified=$NEPIDTVERDZHENO — перелічене вище НЕ перевірено, і це не зелено."
fi
exit 0
