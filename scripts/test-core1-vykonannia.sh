#!/usr/bin/env bash
# Чи ВИКОНУЄТЬСЯ хоч одне визначення з external/sens/lib/core1.lisp?
#
# Навіщо окремий свідок. `knowledge/core1-poverhnia.md` рахує 129 визначень
# у людській проєкції Core1, а `scripts/test-core1-repl.sh` доводить, що
# механізм замикань працює для ВЛАСНИХ визначень сеансу. Ці два факти
# разом ще не кажуть, що хоч одне з 129 тіл Core1 реально обчислюється.
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
#   5. суцільним прогоном міряє, скільком із 129 визначень взагалі
#      вдалося дати вивід — окремо на атомному наборі аргументів (як було),
#      окремо на списковому, порожньому й підібраному за типом.
#
# ВИПРАВЛЕНО (пін 2c498b35): попередня редакція подавала кожному визначенню
# рівно атом `так` і діставала 37 із 129. Це число міряло не мову, а сліпоту
# свідка: `перше`, `друге`, `третє`, `решта`, `сполучити`, `порожній?` за
# природою працюють зі списками, тож атомний прогін заздалегідь прирікав їх
# на відмову. Той самий дефект уже виправлено в `test-core1-argumenty.sh`
# (коміт 0d2f3740) — тут зроблено так само: кожному визначенню подається
# кілька РІЗНИХ наборів аргументів, зокрема підібраний за типом.
#
# Ніщо не ослаблено: атомний прогін лишається в матриці як один із наборів,
# його число 37 друкується далі, а кожна перевірка розділів 1–5 збережена.
# Додано негативні перевірки (виклики, що МУСЯТЬ відмовити, із заданим
# очікуваним текстом), тож кількість перевірок лише зросла.
#
# Результат не підганяється: якщо визначення відмовляє — друкується дослівний
# текст помилки, а не припущення про її причину.
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
# vykon <назва> <дослівна форма> [очікуваний-вивід]
#   без третього аргументу — мусить дати будь-який вивід;
#   з третім — вивід мусить збігтися ДОСЛІВНО.
vykon() {
  local nazva="$1" forma="$2" ochikuvane="${3-}" vyhid pomylka
  printf '%s\n:quit\n' "$forma" > "$WORK/in"
  timeout 60s "$WORK/repl" "$ROOT" < "$WORK/in" > "$WORK/out" 2> "$WORK/err"
  vyhid=$(grep -v -E '^(SENS Core1 REPL|Допущених визначень|Двійковий літерал|Команди:)' \
            "$WORK/out" | tr '\n' '|' | sed 's/|$//')
  pomylka=$(sed 's/^[^;]*; помилка: //' "$WORK/err" | grep -v 'сеанс завершено' | tr '\n' '|' | sed 's/|$//')
  if [ -z "$vyhid" ]; then
    niv "$nazva" "$pomylka"
  elif [ -n "$ochikuvane" ] && [ "$vyhid" != "$ochikuvane" ]; then
    niv "$nazva" "вивід «$vyhid», а мусив бути «$ochikuvane»"
  else
    ok "$nazva" "$vyhid"
  fi
}

# vykon_vidmova <назва> <дослівна форма> <очікуваний-текст-помилки>
#   мусить ВІДМОВИТИ, і саме з цим текстом: інакше «відмова» пройшла б із
#   неправильної причини (напр. «такого імені немає») і нічого не доводила.
vykon_vidmova() {
  local nazva="$1" forma="$2" ochikuvane="$3" vyhid pomylka
  printf '%s\n:quit\n' "$forma" > "$WORK/in"
  timeout 60s "$WORK/repl" "$ROOT" < "$WORK/in" > "$WORK/out" 2> "$WORK/err"
  vyhid=$(grep -v -E '^(SENS Core1 REPL|Допущених визначень|Двійковий літерал|Команди:)' \
            "$WORK/out" | tr '\n' '|' | sed 's/|$//')
  pomylka=$(sed 's/^[^;]*; помилка: //' "$WORK/err" | grep -v 'сеанс завершено' | tr '\n' '|' | sed 's/|$//')
  if [ -n "$vyhid" ]; then
    niv "$nazva" "мусив відмовити, а дав: $vyhid"
  elif ! printf '%s' "$pomylka" | grep -qF "$ochikuvane"; then
    niv "$nazva" "відмова є, але інша: $pomylka (ждали: $ochikuvane)"
  else
    ok "$nazva" "відмовив, як і мусив: $pomylka"
  fi
}

# ── Розділ 1 ────────────────────────────────────────────────────────────────
echo '--- 1. найпростіше визначення Core1 (core1.lisp:31-33), тіло (друге передане-значення)'
# `другий-елемент` — визначення, рядок 31; тіло — (друге передане-значення).
# Атом `так` тут не годиться: `друге` — селектор D4 і потребує фізичного
# списку. Список мусить бути справжнім: `(сполучити так ())` дає список з
# ОДНОГО елемента, а не з двох, і `друге` відмовляє «D4:1001 потребує
# щонайменше два значення». Тому елементи набираються вкладеним сполучити.
vykon 'другий-елемент / двоелементний список' \
  '(другий-елемент (сполучити так (сполучити так ())))' '1'
vykon 'другий-елемент / трьохелементний список' \
  '(другий-елемент (сполучити так (сполучити так (сполучити так ()))))' '1'
# Негативні: та сама перевірка з іншого боку — мусить відмовити САМЕ з цим.
vykon_vidmova 'другий-елемент / атом' '(другий-елемент так)' \
  'потребує фізичного списку'
vykon_vidmova 'другий-елемент / одноeлементний список' '(другий-елемент (сполучити так ()))' \
  'D4:1001 потребує щонайменше два значення'

# ── Розділ 2 ────────────────────────────────────────────────────────────────
echo '--- 2. визначення із за-умовою (core1.lisp:49-54)'
# `помилка?` — визначення, рядок 49; атом? на атомі дає гілку «ні» (0).
vykon 'помилка? / атом' '(помилка? так)' '0'

# ── Розділ 3 ────────────────────────────────────────────────────────────────
echo '--- 3. рекурсивне визначення з мітка (core1.lisp:190-205)'
# `поєднати-параметри` — визначення, рядок 190; усі три параметри
# (параметри, передані-значення, оточення) є списками — тіло починається
# з (порожній? параметри) і рекурсує через (решта …). Два одноeлементні
# списки й порожнє оточення дають рівно один крок рекурсії.
vykon 'поєднати-параметри / списки' \
  '(поєднати-параметри (сполучити так ()) (сполучити так ()) ())' '((1 11 1))'
# Тут відмова приходить від фізичного селектора D3 (тіло починається з
# (порожній? параметри)), а не від D4 — текст узято з фактичного виводу,
# а не припущено.
vykon_vidmova 'поєднати-параметри / атом замість списку' \
  '(поєднати-параметри так так так)' 'native selector requires nonempty pair'

# ── Розділ 4 ────────────────────────────────────────────────────────────────
echo '--- 4. дослівна подача самих визначень через (визначити …)'
# Імена вже належать сталому світу pinned Core1, тому повторне визначення
# мусить бути відмовою — інакше світ мовчки підмінявся б. Форми дослівні з
# core1.lisp:31, :49, :190.
printf '%s\n:quit\n' \
  '(визначити другий-елемент (функція (передане-значення) (друге передане-значення)))' \
  '(визначити помилка? (функція (передане-значення) (за-умовою ((атом? передане-значення) ні) (так ні))))' \
  '(визначити поєднати-параметри (мітка поєднати-параметри (функція (параметри передані-значення оточення) оточення)))' \
  | timeout 60s "$WORK/repl" "$ROOT" > "$WORK/out" 2> "$WORK/err"
povidomlen=$(sed 's/^[^;]*; помилка: //' "$WORK/err" | grep -v 'сеанс завершено')
printf '%s\n' "$povidomlen" | sed 's/^/  /'
# Кожне з трьох повторних визначень мусить дати САМЕ відмову «імʼя вже є».
for imya in другий-елемент помилка? поєднати-параметри; do
  if printf '%s' "$povidomlen" | grep -qF 'вже є у світі сеансу'; then
    ok "повторне визначити $imya" 'відмовлено: імʼя вже є у світі сеансу'
  else
    niv "повторне визначити $imya" "мусило відмовити, а повідомлень: ${povidomlen:-<немає>}"
  fi
done

# ── Розділ 5 ────────────────────────────────────────────────────────────────
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
ORACLE_VYHID=$(tr '\n' '|' < "$WORK/out" | sed 's/|$//')
printf '  код=%s вивід=%s\n' "$KOD" "$ORACLE_VYHID"
if printf '%s' "$ORACLE_VYHID" | grep -qF 'unsupported native callable domain'; then
  ok 'визначити у загальному обчислювачі' "відсутнє, як і має бути: $ORACLE_VYHID"
else
  niv 'визначити у загальному обчислювачі' "очікували відмову unsupported native callable domain, а маємо: $ORACLE_VYHID"
fi

# ── Розділ 6 ────────────────────────────────────────────────────────────────
echo '--- 6. суцільний прогін усіх 129 визначень: чотири різні набори аргументів'
python3 - "$WORK/repl" "$ROOT" > "$WORK/matrix.log" 2>&1 <<'PY'
import re, subprocess, sys
from collections import Counter, OrderedDict

repl, root = sys.argv[1], sys.argv[2]
CORE1 = root + '/external/sens/lib/core1.lisp'

# ── розбір core1.lisp: форми беруться з файла, не вигадуються ───────────────
text = '\n'.join(l.split(';')[0] for l in open(CORE1, encoding='utf-8').read().split('\n'))
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
        params = v[1] if isinstance(v, list) and len(v) > 1 else []
        defs.append({'name': f[1], 'params': params, 'body': v[2:] if isinstance(v, list) else []})

# ── типи параметрів із ТІЛА (не з імен) ─────────────────────────────────────
SEL = {'перше': 1, 'друге': 2, 'третє': 3, 'решта': 0, 'порожній?': 0}
ARITH = {'додати', 'відняти', 'помножити', 'частка', 'остача', 'менше?', 'більше?', 'змінити-знак'}
# Атомні предикати — ЛИШЕ ті, що справді є в чинному піні й справді
# приймають атом: атом? (примітив), тотожне? (примітив), однакові-атоми?
# (визначення). `назви-рівні?` (рядок 74) сюди НЕ входить: воно саме
# спускається в список, тож оголосити його аргументи атомами означало б
# збрехати про пін.
ATOMP = {'атом?', 'тотожне?', 'однакові-атоми?'}
BYSIDE = {d['name']: d for d in defs}

def walk(node, fn, rests=0, outer=0):
    if not isinstance(node, list):
        return
    fn(node, rests, outer)
    h = node[0] if node and isinstance(node[0], str) else None
    child_outer = outer + SEL[h] if h in SEL else outer
    child_rests = rests + 1 if h == 'решта' else rests
    for c in node:
        walk(c, fn, child_rests, child_outer)

def scan(d):
    depth = {p: 0 for p in d['params']}
    marks = {p: set() for p in d['params']}
    calls = {p: [] for p in d['params']}

    def visit(node, rests, outer):
        if not node or not isinstance(node[0], str):
            return
        head = node[0]
        for k, c in enumerate(node[1:], start=1):
            if isinstance(c, str) and c in marks:
                if head in SEL:
                    marks[c].add('список')
                    depth[c] = max(depth[c], SEL[head] + (1 if head == 'решта' else 0) + outer)
                elif head in ARITH:
                    marks[c].add('число')
                elif head in ATOMP:
                    marks[c].add('атом')
                elif head == 'сполучити' and k == 2:
                    marks[c].add('список')
                elif head in BYSIDE:
                    calls[c].append((head, k - 1))
        if (head in SEL and head != 'решта' and isinstance(node[1], list)
                and node[1] and node[1][0] in SEL and node[1][0] != 'решта'):
            for inner in node[1][1:]:
                if isinstance(inner, str) and inner in marks:
                    marks[inner].add('список-пар')
    walk(d['body'], visit)
    return marks, depth, calls

info = {d['name']: scan(d) for d in defs}
defs_by_name = {d['name']: d for d in defs}

def kind_of(name, idx):
    marks, depth, _ = info[name]
    p = defs_by_name[name]['params'][idx]
    m = marks[p]
    for k in ('число', 'список-пар', 'список', 'атом'):
        if k in m:
            return k
    return 'атом'

# тип, що лише передається далі, береться з параметра викликаного визначення
for _ in range(6):
    changed = False
    for d in defs:
        marks, depth, calls = info[d['name']]
        for p, lst in calls.items():
            if marks[p]:
                continue
            for callee, idx in lst:
                if idx < len(defs_by_name[callee]['params']):
                    k = kind_of(callee, idx)
                    if k != 'атом':
                        marks[p].add(k); changed = True; break
    if not changed:
        break

def kind(d, p):
    marks, depth, _ = info[d['name']]
    m = marks[p]
    for k in ('число', 'список-пар', 'список', 'атом'):
        if k in m:
            return k
    return 'атом'

# ── набори аргументів ───────────────────────────────────────────────────────
ATOM = 'так'
def lst(n):
    s = '()'
    for _ in range(n):
        s = '(сполучити так %s)' % s
    return s
def pairlist(n=2):
    s = '()'
    for _ in range(n):
        s = '(сполучити (сполучити так (сполучити так ())) %s)' % s
    return s

def typed_args(d):
    out = []
    marks, depth, _ = info[d['name']]
    for p in d['params']:
        k = kind(d, p)
        if k == 'число':
            out.append('1')
        elif k == 'список-пар':
            out.append(pairlist())
        elif k == 'список':
            out.append(lst(max(3, depth[p])))
        else:
            out.append(ATOM)
    return out

PROFILES = OrderedDict()
PROFILES['атом'] = lambda d: [ATOM] * len(d['params'])
PROFILES['список'] = lambda d: [lst(3)] * len(d['params'])
PROFILES['порожній'] = lambda d: ['()'] * len(d['params'])
PROFILES['за-типом'] = typed_args

# Розділювач сеансу: ДВА ЦИТОВАНІ атоми, а не виклики визначень Core1.
# Префікс `ядро1-` тут ужито САМЕ для того, щоб рядок не збігся зі справжнім
# виводом: жодне визначення чинного піна такого імені не має.
MARK = '(сполучити (як-є ядро1-запис-помилки) (як-є ядро1-запис-світу))'
MARK_LINE = '((я д р о 1 - з а п и с - п о м и л к и) я д р о 1 - з а п и с - с в і т у)'
HEADER = ('SENS Core1 REPL', 'Допущених', 'Двійковий', 'Команди')

def call(name, args):
    return '(' + name + ''.join(' ' + a for a in args) + ')'

def run_def(d):
    """Один процес REPL на визначення: між викликами — унікальний маркер."""
    lines, forms_ = [], []
    for pn in PROFILES:
        args = PROFILES[pn](d)
        forms_.append((pn, args, call(d['name'], args)))
        lines.append(MARK)
        lines.append(forms_[-1][2])
    p = subprocess.run([repl, root], input='\n'.join(lines + [':quit']) + '\n',
                       capture_output=True, text=True, timeout=180)
    out = [l for l in p.stdout.split('\n') if l and not l.startswith(HEADER)]
    errs = [l.split('помилка: ', 1)[1].strip() for l in p.stderr.split('\n') if 'помилка: ' in l]
    segments, cur, started = [], [], False
    for l in out:
        if l == MARK_LINE:
            if started:
                segments.append(cur)
            cur, started = [], True
        else:
            cur.append(l)
    if started:
        segments.append(cur)
    res = {}
    for (pn, args, form), seg in zip(forms_, segments):
        res[pn] = {'args': args, 'form': form, 'out': '|'.join(seg) if seg else None}
    failed = [pn for pn, _, _ in forms_ if res[pn]['out'] is None]
    for pn, msg in zip(failed, errs):
        res[pn]['err'] = msg
    for pn, _, _ in forms_:
        res[pn].setdefault('err', '(виводу немає й тексту помилки немає)')
    return res

print('  %-42s %-7s %-8s %-9s %-9s' % ('визначення', 'атом', 'список', 'порожній', 'за-типом'))
results = OrderedDict()
for d in defs:
    r = run_def(d)
    results[d['name']] = r
    cells = ['вивід' if r[pn]['out'] is not None else 'відмова' for pn in PROFILES]
    print('  %-42s %-7s %-8s %-9s %-9s' % (d['name'], *cells))

# ── підрахунки ──────────────────────────────────────────────────────────────
total = len(results)
vyklykiv = total * len(PROFILES)
atom_ok = [n for n, r in results.items() if r['атом']['out'] is not None]
list_ok = [n for n, r in results.items() if r['список']['out'] is not None]
empty_ok = [n for n, r in results.items() if r['порожній']['out'] is not None]
typed_ok = [n for n, r in results.items() if r['за-типом']['out'] is not None]
any_ok = [n for n, r in results.items() if any(v['out'] is not None for v in r.values())]

print()
print('--- 6а. підрахунок (з фактичного виводу вище)')
print('  визначень у проєкції: %d' % total)
print('  виконано викликів (визначень × наборів): %d' % vyklykiv)
print('  дали ХОЧ ОДИН непомилковий вивід: %d' % len(any_ok))
print('    на атомному наборі (як міряв старий свідок): %d' % len(atom_ok))
print('    на списковому наборі:                      %d' % len(list_ok))
print('    на порожньому наборі:                      %d' % len(empty_ok))
print('    на наборі за типом:                        %d' % len(typed_ok))
print('  не дали жодного виводу: %d' % (total - len(any_ok)))

print()
print('--- 6б. розподіл причин відмов (по одній причині на визначення)')
prychyny = Counter()
for n, r in results.items():
    if any(v['out'] is not None for v in r.values()):
        continue
    msg = r['за-типом']['err']
    if r['за-типом']['out'] is not None:
        msg = next(v['err'] for v in r.values() if v['out'] is None)
    prychyny[msg] += 1
for k, v in prychyny.most_common():
    print('    %3d  %s' % (v, k))

print()
print('--- 6в. визначення, що не дали жодного виводу (дослівні тексти)')
for n, r in results.items():
    if any(v['out'] is not None for v in r.values()):
        continue
    print('  %s' % n)
    for pn in PROFILES:
        v = r[pn]
        stan = ('вивід ' + v['out']) if v['out'] is not None else ('ВІДМОВА: ' + v['err'])
        print('      [%s] %s -> %s' % (pn, v['form'], stan))

print()
print('VYKONANNIA-PIDSYMOK total=%d vyklykiv=%d будь-який=%d атом=%d список=%d порожній=%d за-типом=%d'
      % (total, vyklykiv, len(any_ok), len(atom_ok), len(list_ok), len(empty_ok), len(typed_ok)))
PY
DRIVER_KOD=$?
cat "$WORK/matrix.log"
if [ "$DRIVER_KOD" -ne 0 ]; then
  echo "ПОМИЛКА-СВІДКА: драйвер суцільного прогону завершився з кодом $DRIVER_KOD" >&2
  exit 5
fi
PIDSYMOK=$(grep '^VYKONANNIA-PIDSYMOK ' "$WORK/matrix.log" | tail -n1)
if [ -z "$PIDSYMOK" ]; then
  echo 'ПОМИЛКА-СВІДКА: драйвер не надрукував підсумкового рядка' >&2
  exit 5
fi
chyslo() { echo "$PIDSYMOK" | sed -nE "s/.* $1=([0-9]+).*/\1/p"; }
VSI=$(chyslo total)
VYKLYKIV=$(chyslo vyklykiv)
BUD_YAKYI=$(chyslo будь-який)
NA_ATOMI=$(chyslo атом)
NA_SPYSKU=$(chyslo список)
ZA_TYPOM=$(chyslo за-типом)

# ── перевірки цілісності суцільного прогону (додано, не послаблено) ─────────
# Старий свідок міряв рівно 129 викликів; тепер їх мусить бути 129 × 4.
if [ "$VSI" -eq 129 ]; then
  ok 'суцільний прогін: усі визначення проєкції охоплено' "$VSI визначень"
else
  niv 'суцільний прогін: усі визначення проєкції охоплено' "очікували 129, а маємо $VSI"
fi
if [ "$VYKLYKIV" -eq $((VSI * 4)) ]; then
  ok 'суцільний прогін: кількість викликів не зменшена' "$VYKLYKIV = $VSI × 4"
else
  niv 'суцільний прогін: кількість викликів не зменшена' "очікували $((VSI * 4)), а маємо $VYKLYKIV"
fi
# Атомний набір — той самий вимір, що давав 37. Він не мусить зрости, але
# й не сміє впасти: інакше матриця міряла б інше, ніж старий свідок.
ATOM_BASELINE=37
if [ "$NA_ATOMI" -ge "$ATOM_BASELINE" ]; then
  ok 'атомний набір не гірший за старий свідок' "$NA_ATOMI ≥ $ATOM_BASELINE"
else
  niv 'атомний набір не гірший за старий свідок' "$NA_ATOMI < $ATOM_BASELINE"
fi
# Головне число: хоч один із чотирьох наборів.
if [ "$BUD_YAKYI" -gt "$NA_ATOMI" ]; then
  ok 'підбір аргументів за типом підняв число' "$BUD_YAKYI > $NA_ATOMI (атом)"
else
  niv 'підбір аргументів за типом підняв число' "$BUD_YAKYI не більше за $NA_ATOMI"
fi

# ── підсумок ────────────────────────────────────────────────────────────────
echo '--- підсумок'
echo "  перевірок: ok=$OKIV НЕ-ВИКОНУЄТЬСЯ=$ZBOJIV"
echo "  суцільний прогін: $VSI визначень, $VYKLYKIV викликів"
echo "  визначень із хоч одним виводом: $BUD_YAKYI із $VSI"
echo "    на атомному наборі (старий вимір): $NA_ATOMI"
echo "    на списковому наборі:             $NA_SPYSKU"
echo "    на наборі за типом:               $ZA_TYPOM"
if [ "$ZBOJIV" -eq 0 ]; then
  echo "CORE1-VYKONANNIA: ВИКОНУЄТЬСЯ ЧАСТКОВО ok=$OKIV збоїв=0 виконується=$BUD_YAKYI із $VSI"
  echo "  Усі $OKIV перевірок пройдено; $((VSI - BUD_YAKYI)) визначень усе ще не дають"
  echo '  виводу — дослівні причини в розділі 6б, точні тексти в розділі 6в.'
  echo '  Код 0 означає: свідок справний і жодна перевірка не провалена. Він НЕ'
  echo '  означає, що виконується весь профіль Core1 — див. число вище.'
  exit 0
fi
if [ "$OKIV" -gt 0 ]; then
  echo "ВИСНОВОК: виконується ЧАСТКОВО — $OKIV перевірок пройдено, $ZBOJIV провалено."
  echo "CORE1-VYKONANNIA: ВИКОНУЄТЬСЯ ЧАСТКОВО ok=$OKIV збоїв=$ZBOJIV"
else
  echo 'ВИСНОВОК: жодне з перевірених визначень Core1 не дало результату.'
  echo 'CORE1-VYKONANNIA: НЕ ВИКОНУЄТЬСЯ'
fi
exit 1
