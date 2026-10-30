#!/usr/bin/env bash
# Core1 / issue #866 — живий прогін свідка замикання.
#
# Навіщо окремий .sh, коли є .pas: компіляція — не виконання, і один
# шлях до механізму ще не доказ. Тут ТІ САМІ форми проходять ДВОМА
# незалежними шляхами:
#   1) scripts/test-core1-closure.pas — власна програма, прямий виклик
#      TNativeEvaluator.EvaluateSource;
#   2) src/sens_oracle.lpr — чужий вхід, документований протокол
#      READY / OK<TAB><результат> / ERR<TAB><причина>, сирі дескриптори 0/1.
# Якщо обидва шляхи кажуть те саме — це властивість механізму, а не
# властивість одного адаптера.
#
# Результат прогону — не «зелено за всяку ціну». Якщо замикання не
# викликається, скрипт друкує фактичний вивід і виходить із кодом 1.
# Це і є доказ, якого бракувало комітам 84ed386c..a5d724e6.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
: "${FPC:=fpc}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p build/m0.2/test-units build/m0.2/bin

command -v "$FPC" >/dev/null 2>&1 || {
  echo "НЕ ЗКОМПІЛЬОВАНО: немає FPC ($FPC)" >&2
  exit 127
}
test -d external/sens/lib/domains || {
  echo "ПОМИЛКА-ТЕСТУ: немає pinned доменів external/sens (див. scripts/sync-authority.sh)" >&2
  exit 2
}

ZGHODA=0
ZBOI=0
zghoda() { ZGHODA=$((ZGHODA + 1)); echo "ok $1 -> $2"; }
zbii()   { ZBOI=$((ZBOI + 1));   echo "ПОМИЛКА-ТЕСТУ: $1 — очікували $2; фактично: $3"; }

# ---------- 1. Свідок .pas ----------
echo '--- шлях 1: scripts/test-core1-closure.pas (прямий виклик механізму)'
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/test-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-core1-closure "$ROOT/scripts/test-core1-closure.pas" \
  > "$TMP/build-svidok.log" 2>&1 || {
    echo "НЕ ЗКОМПІЛЬОВАНО: свідок не зібрався" >&2
    cat "$TMP/build-svidok.log" >&2
    exit 3
  }
SV="$ROOT/build/m0.2/bin/test-core1-closure"
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
if [ "$SV_KOD" -eq 1 ] && [ "$SV_ZBII" -eq 0 ]; then
  zbii 'код-виходу-свідка' 'код 1 лише за наявності збоїв' "код 1 без жодного збою"
fi
echo "  кроків свідка: ok=$SV_OK збоїв=$SV_ZBII код=$SV_KOD"

# ---------- 2. Той самий механізм через протокол оракула ----------
echo '--- шлях 2: src/sens_oracle.lpr (протокол READY / OK<TAB> / ERR<TAB>)'
"$FPC" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/test-units" -FE"$ROOT/build/m0.2/bin" \
  -osens-oracle-closure "$ROOT/src/sens_oracle.lpr" \
  > "$TMP/build-oracle.log" 2>&1 || {
    echo "НЕ ЗКОМПІЛЬОВАНО: оракул не зібрався" >&2
    cat "$TMP/build-oracle.log" >&2
    exit 3
  }
ORACLE="$ROOT/build/m0.2/bin/sens-oracle-closure"
test -x "$ORACLE" || { echo 'НЕ ЗКОМПІЛЬОВАНО: немає двійкового оракула' >&2; exit 3; }

# oracle_vypadok <назва> <форма> <очікування>
#   очікування: ok             — код 0 і OK<TAB> (форму прийнято; порожній
#                                результат тут не помилка: у ncClosure немає
#                                текстової проєкції — це окремий випадок свідка)
#               okneporo       — код 0 і OK<TAB> з непорожнім результатом
#               err:<підрядок> — код 2 і ERR<TAB>…<підрядок>
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
      if [ "$kod" -eq 0 ] && printf '%s' "$ridok" | grep -q '^OK	'; then
        zghoda "$nazva" "$ridok"
      else
        zbii "$nazva" 'код 0 і OK<TAB>' "код=$kod $ridok"
      fi
      ;;
    okneporo)
      if [ "$kod" -eq 0 ] && printf '%s' "$ridok" | grep -q '^OK	'; then
        if [ -n "$(printf '%s' "$ridok" | cut -f2- | tr -d '[:space:]')" ]; then
          zghoda "$nazva" "$ridok"
        else
          zbii "$nazva" 'OK з непорожнім результатом' "$ridok"
        fi
      else
        zbii "$nazva" 'код 0 і OK<TAB>' "код=$kod $ridok"
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

oracle_vypadok 'оракул-створити-замикання' \
  '(створити-лямбда-замикання (х) х)' ok
oracle_vypadok 'оракул-виклик-фізичним-аргументом' \
  '((створити-лямбда-замикання (х) х) так)' okneporo
oracle_vypadok 'оракул-виклик-замало-аргументів' \
  '((створити-лямбда-замикання (х) х))' 'err:ARITY'
oracle_vypadok 'оракул-виклик-забагато-аргументів' \
  '((створити-лямбда-замикання (х) х) так ні)' 'err:ARITY'
oracle_vypadok 'оракул-створення-без-тіла' \
  '(створити-лямбда-замикання (х))' 'err:closure needs parameters and body'

# ---------- 3. Діагностика: чи є на поверхні шлях зв'язати ім'я із замиканням ----------
# Ці рядки НЕ зараховуються: вони нічого не стверджують про правильність,
# лише друкують фактичну відповідь. Потрібні, щоб назвати причину, якщо
# гілка виклику недосяжна: Assoc шукає в Env, а Env наповнює лише Pairlis
# під час виклику замикання (wsm.nativeeval.pas:523-529, 362-373).
echo '--- діагностика (не зараховується): форми, що могли б звязати імʼя із замиканням'
diahnostyka() {
  printf '%s\n' "$2" > "$TMP/in"
  set +e
  timeout 45s "$ORACLE" < "$TMP/in" > "$TMP/out" 2>/dev/null
  set -e
  echo "  діагностика $1 -> $(sed -n '2p' "$TMP/out")"
}
diahnostyka 'встановити-D5-00110' '(встановити імʼя (створити-лямбда-замикання (х) х))'
diahnostyka 'встановити-імʼя-D5-00111' '(встановити-імʼя імʼя так)'
diahnostyka 'звʼязати-параметри-D10-0101100010' '(звʼязати-параметри (х) так ())'

# ---------- 4. Підсумок ----------
echo "ЗАМИКАННЯ-СВІДОК-ПІДСУМОК перевірок=$((ZGHODA + ZBOI)) ok=$ZGHODA збоїв=$ZBOI"
if [ "$ZBOI" -gt 0 ]; then
  echo 'ВИСНОВОК: механізм замикань у цьому стані НЕ ВИКОНУЄТЬСЯ на поверхні (див. збої вище).'
  exit 1
fi
echo 'ВИСНОВОК: створення і виклик замикання підтверджені фактичним виводом.'
