#!/usr/bin/env bash
# test-core1-argumenty.sh — чи ВИКОНУЄТЬСЯ визначення Core1, коли аргумент
# підібрано ЗА ТИПОМ, а не суцільно атомом `так`?
#
# Навіщо окремий свідок. `scripts/test-core1-vykonannia.sh` подає кожному з
# 96 визначень рівно атом `так` (call = name + 'так' * arity) і отримує 15 із
# 96. Це число міряє не мову, а сліпоту свідка: `перше`, `решта`, `сполучити`
# за природою працюють зі списками, тож атомний прогін заздалегідь прирікає
# їх на відмову. Цей свідок міряє те саме питання інакше — подаючи кожному
# визначенню кілька РІЗНИХ наборів аргументів і аргумент, підібраний за типом.
#
# Наявний свідок НЕ переписано й НЕ ослаблено: це окремий файл, і його числа
# друкуються тут лише для порівняння.
#
# Що робить скрипт:
#   1. збирає src/senscore1repl.lpr (єдиний інструмент, що приймає виклики у
#      сталому середовищі pinned Core1);
#   2. розбирає external/sens/lib/core1.lisp у 96 визначень (ім'я, параметри,
#      тіло) — форми беруться з файла, не вигадуються;
#   3. визначає тип КОЖНОГО параметра з його вживання у ТІЛІ визначення:
#      `перше/друге/третє/решта/порожній?` → список, арифметичні примітиви →
#      число, `атом?/тотожне?/однакові-атоми?` → атом, `(перше (перше X))`
#      → список пар; параметр, що лише передається далі, бере тип із
#      параметра викликаного визначення (та сама таблиця, до нерухомої точки);
#   4. подає КОЖНОМУ визначенню чотири різні набори аргументів:
#      атомний (`так`), списковий (список з трьох елементів), порожній (`()`)
#      і за-типом (кожен параметр окремо, за п.3);
#   5. рахує визначення, що дали ХОЧ ОДИН непомилковий вивід, окремо —
#      скільком дав вивід САМЕ списковий набір, окремо — набір за типом;
#   6. друкує розподіл причин відмов (як наявний свідок) і точний текст
#      помилки для кожного визначення, що не дав виводу;
#   7. містить негативний випадок: виклики, що МУСЯТЬ відмовити
#      (селектор Д3 над атомом, арифметика над не-числом), і перевіряє, що
#      вони справді відмовляють, а контрольний виклик — справді дає вивід.
#
# Чесність. Аргументи не підганяються під успіх: якщо визначення ламається
# на списку — це записано з дослівним текстом помилки. Число 15/96 узяте з
# наявного свідка й тут лише як baseline для порівняння.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
: "${FPC:=fpc}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/u" "$WORK/b"

command -v "$FPC" >/dev/null 2>&1 || { echo "НЕ ЗКОМПІЛЬОВАНО: немає FPC ($FPC)" >&2; exit 127; }
test -s external/sens/lib/core1.lisp || { echo 'ПОМИЛКА-ТЕСТУ: немає pinned core1.lisp' >&2; exit 2; }

echo "--- FPC: $("$FPC" -iV)"
"$FPC" -B -Mobjfpc -Fu"$ROOT/src" -FU"$WORK/u" -FE"$WORK/b" \
  -o"$WORK/repl" "$ROOT/src/senscore1repl.lpr" > "$WORK/build.log" 2>&1 || {
    echo 'НЕ ЗКОМПІЛЬОВАНО: REPL Core1 не зібрався' >&2
    cat "$WORK/build.log" >&2
    exit 3
  }
echo '--- REPL Core1 зібрано; джерело форм і типів: external/sens/lib/core1.lisp'

echo
echo '--- 1. матриця: чотири різні набори аргументів на кожне визначення'
python3 - "$WORK/repl" "$ROOT" > "$WORK/matrix.log" 2>&1 <<'PY'
import re, subprocess, sys
from collections import Counter, OrderedDict

repl, root = sys.argv[1], sys.argv[2]
CORE1 = root + '/external/sens/lib/core1.lisp'

# ── розбір core1.lisp ────────────────────────────────────────────────────────
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

# ── типи параметрів із ТІЛ (не з імен) ───────────────────────────────────────
SEL = {'перше': 1, 'друге': 2, 'третє': 3, 'решта': 0, 'порожній?': 0}
ARITH = {'додати', 'відняти', 'помножити', 'частка', 'остача', 'менше?', 'більше?', 'змінити-знак'}
# Множина атомних предикатів — ЛИШЕ імена, що справді є в чинному піні й
# справді приймають атом: атом? (примітив), тотожне? (примітив),
# однакові-атоми? (визначення, рядок 593). `назви-рівні?` (рядок 74) сюди
# НЕ входить: воно саме спускається в список (рядки 78–84), тож оголосити
# його аргументи атомами означало б збрехати про пін.
ATOMP = {'атом?', 'тотожне?', 'однакові-атоми?'}
BYSIDE = {d['name']: d for d in defs}

def walk(node, fn, rests=0, outer=0):
    """Обхід тіла: fn(node, rests, outer), де outer — сума індексів
    охопних селекторів, rests — скільки «решта» застосовано вище."""
    if not isinstance(node, list):
        return
    fn(node, rests, outer)
    h = node[0] if node and isinstance(node[0], str) else None
    child_outer = outer + SEL[h] if h in SEL else outer
    child_rests = rests + 1 if h == 'решта' else rests
    for c in node:
        walk(c, fn, child_rests, child_outer)

# глибина селектора, потрібна параметрові як списку
def scan(d):
    depth = {p: 0 for p in d['params']}
    marks = {p: set() for p in d['params']}
    calls = {p: [] for p in d['params']}   # (callee, індекс параметра)

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
        # селектор над результатом селектора: (перше (перше X)) → X — список пар
        if (head in SEL and head != 'решта' and isinstance(node[1], list)
                and node[1] and node[1][0] in SEL and node[1][0] != 'решта'):
            for inner in node[1][1:]:
                if isinstance(inner, str) and inner in marks:
                    marks[inner].add('список-пар')
    walk(d['body'], visit)
    return marks, depth, calls

info = {d['name']: scan(d) for d in defs}

# тип, що лише передається далі, береться з параметра викликаного визначення
def kind_of(name, idx):
    marks, depth, _ = info[name]
    p = defs_by_name[name]['params'][idx]
    m = marks[p]
    for k in ('число', 'список-пар', 'список', 'атом'):
        if k in m:
            return k
    return 'атом'

defs_by_name = {d['name']: d for d in defs}
for _ in range(6):                      # до нерухомої точки
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

# ── набори аргументів ────────────────────────────────────────────────────────
ATOM = 'так'
def lst(n):                              # список з n елементів так
    s = '()'
    for _ in range(n):
        s = '(сполучити так %s)' % s
    return s
def pairlist(n=2):                       # список із n пар (так так)
    s = '()'
    for _ in range(n):
        s = '(сполучити (сполучити так (сполучити так ())) %s)' % s
    return s

def typed_args(d):
    out = []
    for p in d['params']:
        k = kind(d, p)
        marks, depth, _ = info[d['name']]
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
# Вони не мусять існувати в core1.lisp — вони лише друкуються назад як
# унікальний рядок, якого не може дати жоден вивід (префікс `ядро1-` тут
# ужито САМЕ для того, щоб рядок не збігся зі справжнім виводом).
MARK = '(сполучити (як-є ядро1-запис-помилки) (як-є ядро1-запис-світу))'
MARK_LINE = '((я д р о 1 - з а п и с - п о м и л к и) я д р о 1 - з а п и с - с в і т у)'
HEADER = ('SENS Core1 REPL', 'Допущених', 'Двійковий', 'Команди')

def call(name, args):
    return '(' + name + ''.join(' ' + a for a in args) + ')'

def run_def(d):
    """Один процес REPL на визначення: між викликами — унікальний маркер.
    Маркер друкується ЗАВЖДИ, тож відрізки між маркерами дають рівно один
    результат (або жодного); порядок помилок у stderr збігається з порядком
    невдалих викликів."""
    lines, forms = [], []
    for pn in PROFILES:
        args = PROFILES[pn](d)
        forms.append((pn, args, call(d['name'], args)))
        lines.append(MARK)
        lines.append(forms[-1][2])
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
    for (pn, args, form), seg in zip(forms, segments):
        res[pn] = {'args': args, 'form': form,
                   'out': '|'.join(seg) if seg else None}
    failed = [pn for pn, _, _ in forms if res[pn]['out'] is None]
    for pn, msg in zip(failed, errs):
        res[pn]['err'] = msg
    for pn, _, _ in forms:
        res[pn].setdefault('err', '(виводу немає й тексту помилки немає)')
    return res

print('  %-42s %-7s %-7s %-9s %-9s' % ('визначення', 'атом', 'список', 'порожній', 'за-типом'))
results = OrderedDict()
for d in defs:
    r = run_def(d)
    results[d['name']] = r
    cells = []
    for pn in PROFILES:
        cells.append('вивід' if r[pn]['out'] is not None else 'відмова')
    print('  %-42s %-7s %-7s %-9s %-9s' % (d['name'], *cells))

# ── підрахунки ───────────────────────────────────────────────────────────────
total = len(results)
any_ok = [n for n, r in results.items() if any(v['out'] is not None for v in r.values())]
list_ok = [n for n, r in results.items() if r['список']['out'] is not None]
typed_ok = [n for n, r in results.items() if r['за-типом']['out'] is not None]
atom_ok = [n for n, r in results.items() if r['атом']['out'] is not None]
empty_ok = [n for n, r in results.items() if r['порожній']['out'] is not None]

print()
print('--- 2. підрахунок (з фактичного виводу вище)')
print('  визначень у проєкції: %d' % total)
print('  дали ХОЧ ОДИН непомилковий вивід: %d' % len(any_ok))
print('    з них на атомному наборі:    %d' % len(atom_ok))
print('    з них на списковому наборі:  %d' % len(list_ok))
print('    з них на порожньому наборі:  %d' % len(empty_ok))
print('    з них на наборі за типом:    %d' % len(typed_ok))
print('  не дали жодного виводу: %d' % (total - len(any_ok)))

print()
print('--- 3. розподіл причин відмов (по одній причині на визначення;')
print('    узято причину набору «за-типом», а якщо він дав вивід — першу іншу)')
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
print('--- 3б. чи лишається відмова дефектом ЦИТУВАННЯ, а не типу аргументу')
def maie_tsytuvannia(node):
    """Чи є в тілі підформа (як-є …): саме її обчислення падає нижче."""
    if isinstance(node, list):
        if node and isinstance(node[0], str) and node[0] == 'як-є':
            return True
        return any(maie_tsytuvannia(c) for c in node)
    return False

def vyklyky(node, acc=None):
    """Імена визначень Core1, які тіло викликає."""
    if acc is None:
        acc = set()
    if isinstance(node, list):
        if node and isinstance(node[0], str) and node[0] in defs_by_name:
            acc.add(node[0])
        for c in node:
            vyklyky(c, acc)
    return acc

tsytuie = {n for n, d in defs_by_name.items() if maie_tsytuvannia(d['body'])}
# транзитивне замикання: хто доходить до (як-є …) через власні виклики
dokhodiat = set(tsytuie)
for _ in range(12):
    dodano = False
    for n, d in defs_by_name.items():
        if n not in dokhodiat and (vyklyky(d['body']) & dokhodiat):
            dokhodiat.add(n); dodano = True
    if not dodano:
        break

POV = 'пошкоджений фізичний інтервал вузла'
bez_vyhodu = [n for n, r in results.items() if not any(v['out'] is not None for v in r.values())]
z_tsym = [n for n in bez_vyhodu if any(v['err'] == POV for v in results[n].values())]
priamo = [n for n in z_tsym if n in tsytuie]
via = [n for n in z_tsym if n not in tsytuie and n in dokhodiat]
inakshe = [n for n in z_tsym if n not in dokhodiat]
print('  визначень без жодного виводу: %d' % len(bez_vyhodu))
print('  з них хоч раз дали «%s»: %d' % (POV, len(z_tsym)))
print('    у тілі є сама підформа (як-є …):              %d' % len(priamo))
print('    доходять до (як-є …) через виклики:           %d %s' % (len(via), via if via else ''))
print('    ні тіла, ні виклику з (як-є …):               %d %s' % (len(inakshe), inakshe if inakshe else ''))
if len(z_tsym) > 0:
    print('  Отже: обчислення (як-є дане) у тілі ВСЕ ЩЕ віддає «пошкоджений')
    print('  фізичний інтервал вузла» — цитата читає інтервали свого вузла з')
    print('  ЧУЖОГО масиву слів, і SliceOf (src/wsm.core1selektor.pas) їх відхиляє.')
    print('  Це не залежить від типу аргументу — див. розділ 6.')
else:
    print('  Отже: ЖОДНЕ визначення не відмовляє текстом «пошкоджений фізичний')
    print('  інтервал вузла». Цитата більше не читає інтервали свого вузла з')
    print('  чужого масиву слів. Оцінка спирається лише на числа вище;')
    print('  відмови, що лишилися, мають ІНШІ причини (див. розділ 3).')

print()
print('--- 4. дослівні результати набору «за-типом» (аргументи й вивід/помилка)')
for d in defs:
    r = results[d['name']]['за-типом']
    stan = ('вивід ' + r['out']) if r['out'] is not None else ('ВІДМОВА: ' + r['err'])
    print('  %s %s\n      %s' % (d['name'], r['form'], stan))

# ── машиночитний підсумок для bash-обгортки ──────────────────────────────────
print()
print('ARGUMENTY-PIDSYMOK total=%d будь-який=%d атом=%d список=%d порожній=%d за-типом=%d'
      % (total, len(any_ok), len(atom_ok), len(list_ok), len(empty_ok), len(typed_ok)))
PY
DRIVER_KOD=$?
cat "$WORK/matrix.log"
if [ "$DRIVER_KOD" -ne 0 ]; then
  echo "ПОМИЛКА-СВІДКА: драйвер матриці завершився з кодом $DRIVER_KOD" >&2
  exit 5
fi
PIDSYMOK=$(grep '^ARGUMENTY-PIDSYMOK ' "$WORK/matrix.log" | tail -n1)
if [ -z "$PIDSYMOK" ]; then
  echo 'ПОМИЛКА-СВІДКА: драйвер не надрукував підсумкового рядка' >&2
  exit 5
fi
chyslo() { echo "$PIDSYMOK" | sed -nE "s/.* $1=([0-9]+).*/\1/p"; }
VSI=$(chyslo total)
BUD_YAKYI=$(chyslo будь-який)
NA_SPYSKU=$(chyslo список)
ZA_TYPOM=$(chyslo за-типом)

echo
echo '--- 5. негативний випадок: виклики, що МУСЯТЬ відмовити'
NEG_FAIL=0
# Один рядок — один прогін, щоб помилка не змішувалася з наступним викликом.
progin() {
  local nazva="$1" forma="$2" oznaka="$3" ochikuvane="${4:-}" vyhid pomylka
  printf '%s\n:quit\n' "$forma" > "$WORK/in"
  timeout 60s "$WORK/repl" "$ROOT" < "$WORK/in" > "$WORK/out" 2> "$WORK/err"
  vyhid=$(grep -v -E '^(SENS Core1 REPL|Допущених визначень|Двійковий літерал|Команди:)' \
            "$WORK/out" | tr '\n' '|' | sed 's/|$//')
  pomylka=$(sed 's/^[^;]*; помилка: //' "$WORK/err" | grep -v 'сеанс завершено' | tr '\n' '|' | sed 's/|$//')
  if [ "$oznaka" = 'мусить-відмовити' ]; then
    if [ -n "$ochikuvane" ] && ! printf '%s' "$pomylka" | grep -qF "$ochikuvane"; then
      printf 'ПРОВАЛ %s -> відмова є, але інша: %s (ждали: %s)\n' "$nazva" "$pomylka" "$ochikuvane"
      NEG_FAIL=$((NEG_FAIL + 1))
    elif [ -z "$vyhid" ] && [ -n "$pomylka" ]; then
      printf 'ok %s -> відмовив, як і мусив: %s\n' "$nazva" "$pomylka"
    else
      printf 'ПРОВАЛ %s -> мусив відмовити, а дав: %s\n' "$nazva" "${vyhid:-<нічого>}"
      NEG_FAIL=$((NEG_FAIL + 1))
    fi
  else
    if [ -n "$vyhid" ]; then
      printf 'ok %s -> контроль дав вивід: %s\n' "$nazva" "$vyhid"
    else
      printf 'ПРОВАЛ %s -> контроль мусив дати вивід, а відмовив: %s\n' "$nazva" "$pomylka"
      NEG_FAIL=$((NEG_FAIL + 1))
    fi
  fi
}
# Імена — з ЧИННОГО піна 2c498b35, external/sens/lib/core1.lisp:
#   другий-елемент — визначення, рядок 31;
#   додати         — примітив, вжитий у тілі назви-рівні? (рядок 111).
# Префікса `ядро1-` чинний пін не має. Тут стояли імена зі СТАРОГО піна, і
# саме тому кожен виклик нижче відмовляв текстом «це визначення Core1 не
# підтримане цим зрізом»: і «негативний», і контрольний випадок проходили з
# НЕПРАВИЛЬНОЇ причини. Тепер очікуваний текст відмови заданий явно, тож
# відмова мусить бути САМЕ семантична, а не «такого імені немає».
# Д3-селектор над атомом: другий елемент атома не існує — мусить бути відмова.
progin 'другий-елемент / атом' '(другий-елемент так)' \
       'мусить-відмовити' 'потребує фізичного списку'
# Арифметика над не-числом: `так` — D1, не D24 — мусить бути відмова.
progin 'додати / не-число' '(додати так так)' \
       'мусить-відмовити' 'не є числовим доменом'
# Контроль: ті самі визначення на аргументі свого типу — мусять дати вивід.
progin 'другий-елемент / список' '(другий-елемент (сполучити так (сполучити так ())))' 'мусить-дати'
progin 'додати / числа' '(додати 1 2)' 'мусить-дати'

echo
echo '--- 6. диференційний дослід: доля виклику залежить не від аргументу,'
echo '    а від того, чи досягає тіло підформи (як-є …). Обидві гілки МУСЯТЬ'
echo '    дати вивід: цитата повертає дане, не обчислюючи його.'
# (помилка? так) іде гілкою (атом? …) і цитати не обчислює — мусить дати вивід.
# `помилка?` — визначення, рядок 49.
progin 'помилка? / атом — гілка без цитати' '(помилка? так)' 'мусить-дати'
# (помилка? (сполучити так ())) іде гілкою (назви-рівні? … (як-є …))
# і МУСИТЬ дати вивід: за pinned core1.lisp (обчислити-форму-ядра, рядок 396,
# гілка «(назва-цитування? (перше вираз)) → (друге вираз)», рядки 411–412)
# цитата повертає саме дане, не обчислюючи його. Раніше тут стояло
# «мусить-відмовити» з текстом «пошкоджений фізичний інтервал вузла» — це
# було закріплення ДЕФЕКТУ в свідкові, а не вимога мови. Вимогу виправлено
# на мовну.
progin 'помилка? / список — гілка з цитатою' '(помилка? (сполучити так ()))' \
       'мусить-дати'
# Цитата не обчислює свій аргумент — два незалежні доводи.
# 1) Те саме ім'я без цитати — відмова лексичного середовища, під цитатою —
#    дане, без жодного обчислення.
# `атом?` — примітив, вжитий у тілах помилка? (рядок 52) і назви-рівні? (78).
progin 'цитата не обчислює: імʼя без цитати' '(атом? невідоме)' \
       'мусить-відмовити' 'лексичним середовищем'
progin 'цитата не обчислює: те саме імʼя під цитатою' '(атом? (як-є невідоме))' 'мусить-дати'
# 2) Форма (сполучити так ()) як ДАНЕ — це три слова, тож другий елемент —
#    `так` (вивід 1). Якби цитата обчислювала аргумент, він став би парою
#    (так), і виклик відмовив би «D4:1001 потребує щонайменше два значення»
#    (так поводиться той самий вираз БЕЗ цитати — див. рядок нижче).
progin 'цитата не обчислює: (сполучити так ()) як дане' \
       '(другий-елемент (як-є (сполучити так ())))' 'мусить-дати'
progin 'контроль: той самий вираз БЕЗ цитати обчислюється' \
       '(другий-елемент (сполучити так ()))' \
       'мусить-відмовити' 'D4:1001 потребує щонайменше два значення'

echo
echo '--- підсумок'
if [ "$NEG_FAIL" -ne 0 ]; then
  echo "ARGUMENTY: ЗБІЙ СВІДКА — негативний/контрольний випадок не повівся як мусив ($NEG_FAIL)"
  exit 4
fi
echo 'ARGUMENTY-NEGATYV-OK: усі «мусить-відмовити» відмовили (з очікуваним текстом),'
echo '  усі контролі дали вивід'
echo
BASELINE=15
echo "  визначень у проєкції: $VSI"
echo "  число ДО  (наявний свідок test-core1-vykonannia.sh, аргумент — атом так): $BASELINE із $VSI"
echo "  число ПІСЛЯ (цей свідок, хоч один із чотирьох наборів):                    $BUD_YAKYI із $VSI"
echo "  з них на списковому наборі:  $NA_SPYSKU"
echo "  з них на наборі за типом:    $ZA_TYPOM"
echo
if [ "$BUD_YAKYI" -le "$BASELINE" ]; then
  echo "ARGUMENTY: НЕ ВИКОНАНО — число не зросло ($BUD_YAKYI не більше за $BASELINE)."
  echo '  Підбір аргументів за типом нічого не змінив; див. розділ 3 з причинами.'
  exit 1
fi
echo "ARGUMENTY: ВИКОНАНО ЧАСТКОВО — аргументи за типом підняли число з $BASELINE до $BUD_YAKYI із $VSI."
echo "  Усе ще відмовляють $((VSI - BUD_YAKYI)) визначень. Причину НЕ вгадуємо:"
echo '  дослівний розподіл причин — у розділі 3, точні тексти — у розділі 4.'
echo '  Якщо в розділі 3б стоїть 0 на «пошкоджений фізичний інтервал вузла»,'
echo '  то цитата більше не є причиною відмов цього зрізу.'
exit 0
