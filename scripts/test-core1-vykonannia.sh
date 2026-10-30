#!/usr/bin/env bash
# Чи ВИКОНУЄТЬСЯ хоч одне визначення з external/sens/lib/core1.lisp?
#
# Навіщо окремий свідок. `knowledge/core1-poverhnia.md` рахує 96 визначень
# у людській проєкції Core1, а `scripts/test-core1-repl.sh` доводить, що
# механізм замикань працює для ВЛАСНИХ визначень сеансу. Ці два факти
# разом ще не кажуть, що хоч одне з 96 тіл Core1 реально обчислюється.
# Тут перевіряється саме це — фактичним виводом, а не наміром.
#
# Що робить скрипт:
#   1. збирає src/senscore1repl.lpr (єдиний наявний інструмент, що приймає
#      `(визначити …)` і викликає тіла у сталому середовищі pinned Core1);
#   2. подає ДОСЛІВНІ форми з core1.lisp — не вигадані;
#   3. друкує для кожної або `ok <назва> -> <результат>`, або
#      `НЕ ВИКОНУЄТЬСЯ: <точний текст помилки>`;
#   4. окремо показує, що `визначити` (D4:0011) відсутнє як механізм
#      загального обчислювача (src/sens_oracle.lpr);
#   5. грубим суцільним прогоном міряє, скільком із 96 визначень взагалі
#      вдалося дати вивід на однорідному аргументі.
#
# Результат не підганяється: якщо Core1 не виконується, скрипт так і
# друкує і виходить із кодом 1.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
: "${FPC:=fpc}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/u" "$WORK/b"
OKIV=0
ZBOJIV=0

ok()   { OKIV=$((OKIV + 1));   printf 'ok %s -> %s\n' "$1" "$2"; }
niv()  { ZBOJIV=$((ZBOJIV + 1)); printf 'НЕ ВИКОНУЄТЬСЯ: %s — %s\n' "$1" "$2"; }

command -v "$FPC" >/dev/null 2>&1 || { echo "НЕ ЗКОМПІЛЬОВАНО: немає FPC ($FPC)" >&2; exit 127; }
test -s external/sens/lib/core1.lisp || { echo 'ПОМИЛКА-ТЕСТУ: немає pinned core1.lisp' >&2; exit 2; }

"$FPC" -B -Mobjfpc -Fu"$ROOT/src" -FU"$WORK/u" -FE"$WORK/b" \
  -o"$WORK/repl" "$ROOT/src/senscore1repl.lpr" > "$WORK/build.log" 2>&1 || {
    echo 'НЕ ЗКОМПІЛЬОВАНО: REPL Core1 не зібрався' >&2
    cat "$WORK/build.log" >&2
    exit 3
  }
echo '--- REPL Core1 зібрано; джерело форм: external/sens/lib/core1.lisp'

# Один рядок — один прогін: так помилка рядка не змішується з наступним.
# vykon <назва> <дослівна форма>
vykon() {
  local nazva="$1" forma="$2" vyhid pomylka
  printf '%s\n:quit\n' "$forma" > "$WORK/in"
  timeout 60s "$WORK/repl" "$ROOT" < "$WORK/in" > "$WORK/out" 2> "$WORK/err"
  vyhid=$(grep -v -E '^(SENS Core1 REPL|Допущених визначень|Двійковий літерал|Команди:)' \
            "$WORK/out" | tr '\n' '|' | sed 's/|$//')
  pomylka=$(sed 's/^[^;]*; помилка: //' "$WORK/err" | grep -v 'сеанс завершено' | tr '\n' '|' | sed 's/|$//')
  if [ -n "$vyhid" ]; then
    ok "$nazva" "$vyhid"
  else
    niv "$nazva" "$pomylka"
  fi
}

echo '--- 1. найпростіше визначення Core1 (core1.lisp:33-35), тіло (друге передане-значення)'
# Дослівна форма файла. У проєкції на цьому коміті тіло саме (друге …),
# а не (перше (решта …)), і параметр зветься передане-значення.
vykon 'ядро1-другий-елемент / дослівний виклик з ()' \
  '(ядро1-другий-елемент (сполучити так ()))'
vykon 'ядро1-другий-елемент / аргумент-список без ()' \
  '(ядро1-другий-елемент (сполучити так так))'

echo '--- 2. визначення із за-умовою (core1.lisp:51-57)'
vykon 'ядро1-помилка? / атом' '(ядро1-помилка? так)'

echo '--- 3. рекурсивне визначення з мітка (core1.lisp:193-210)'
vykon 'ядро1-поєднати-параметри / списки' \
  '(ядро1-поєднати-параметри (сполучити так так) (сполучити так так) так)'

echo '--- 4. дослівна подача самих визначень через (визначити …)'
# Імена вже належать сталому світу pinned Core1, тому повторне визначення
# мусить бути відмовою — інакше світ мовчки підмінявся б.
printf '%s\n:quit\n' \
  '(визначити ядро1-другий-елемент (функція (передане-значення) (друге передане-значення)))' \
  '(визначити ядро1-помилка? (функція (передане-значення) (за-умовою ((атом? передане-значення) ні) (так ні))))' \
  '(визначити ядро1-поєднати-параметри (мітка ядро1-поєднати-параметри (функція (параметри передані-значення оточення) оточення)))' \
  | timeout 60s "$WORK/repl" "$ROOT" > "$WORK/out" 2> "$WORK/err"
sed 's/^[^;]*; помилка: //' "$WORK/err" | grep -v 'сеанс завершено' | sed 's/^/  /'

echo '--- 5. чи реалізовано визначити (D4:0011, domains/d4.lisp:12) у загальному обчислювачі'
"$FPC" -B -Mobjfpc -Fu"$ROOT/src" -FU"$WORK/u" -FE"$WORK/b" \
  -o"$WORK/oracle" "$ROOT/src/sens_oracle.lpr" > "$WORK/build-oracle.log" 2>&1 || {
    echo 'НЕ ЗКОМПІЛЬОВАНО: оракул не зібрався' >&2
    cat "$WORK/build-oracle.log" >&2
    exit 3
  }
printf '(визначити тест (функція (х) х))\n' | timeout 60s "$WORK/oracle" > "$WORK/out" 2>/dev/null
KOD=$?
# Українські слова «рядок=» і «колонка=» у цьому рядку друкуються через
# кодову сторінку консолі й видно як ?????. Латинська частина — точна.
printf '  код=%s вивід=%s\n' "$KOD" "$(tr '\n' '|' < "$WORK/out" | sed 's/|$//')"

echo '--- 6. грубий суцільний прогін усіх 96 визначень (аргумент — атом так)'
python3 - "$WORK/repl" "$ROOT" <<'PY'
import re, subprocess, sys
from collections import Counter
repl, root = sys.argv[1], sys.argv[2]
text = '\n'.join(l.split(';')[0] for l in
                 open('external/sens/lib/core1.lisp', encoding='utf-8').read().split('\n'))
toks = re.findall(r'\(|\)|[^\s()]+', text)
def parse(i):
    i += 1; out = []
    while toks[i] != ')':
        if toks[i] == '(':
            sub, i = parse(i); out.append(sub)
        else:
            out.append(toks[i]); i += 1
    return out, i + 1
forms, i = [], 0
while i < len(toks):
    if toks[i] == '(':
        f, i = parse(i); forms.append(f)
    else:
        i += 1
defs = []
for f in forms:
    if f and f[0] == 'визначити':
        v = f[2]
        if isinstance(v, list) and v[0] == 'мітка':
            v = v[2]
        defs.append((f[1], len(v[1]) if isinstance(v, list) and len(v) > 1 else 0))
vid, bez, prychyny = 0, 0, Counter()
for name, arity in defs:
    call = '(' + name + (' ' + ' '.join(['так'] * arity) if arity else '') + ')'
    p = subprocess.run([repl, root], input=call + '\n:quit\n',
                       capture_output=True, text=True, timeout=120)
    body = [l for l in p.stdout.split('\n') if l and not l.startswith(
        ('SENS Core1 REPL', 'Допущених', 'Двійковий', 'Команди'))]
    if body:
        vid += 1
    else:
        bez += 1
        for l in p.stderr.split('\n'):
            if 'помилка: ' in l:
                prychyny[l.split('помилка: ', 1)[1]] += 1
print(f'  визначень у проєкції: {len(defs)}')
print(f'  дали вивід: {vid}   без виводу: {bez}')
for k, v in prychyny.most_common():
    print(f'    {v:3d}  {k}')
PY

echo '--- підсумок'
echo "  перевірок: ok=$OKIV НЕ-ВИКОНУЄТЬСЯ=$ZBOJIV"
if [ "$ZBOJIV" -eq 0 ]; then
  echo 'CORE1-VYKONANNIA: ВИКОНУЄТЬСЯ (див. ok-рядки вище)'
  exit 0
fi
if [ "$OKIV" -gt 0 ]; then
  echo "ВИСНОВОК: виконується ЧАСТКОВО — $OKIV із $((OKIV + ZBOJIV)) перевірених визначень дали результат."
  echo "CORE1-VYKONANNIA: ВИКОНУЄТЬСЯ ЧАСТКОВО ok=$OKIV збоїв=$ZBOJIV"
else
  echo 'ВИСНОВОК: жодне з перевірених визначень Core1 не дало результату.'
  echo 'CORE1-VYKONANNIA: НЕ ВИКОНУЄТЬСЯ'
fi
exit 1
