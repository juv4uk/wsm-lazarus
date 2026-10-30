#!/usr/bin/env bash
# G6.x — текстовий REPL на Free Vision, який РЕАЛЬНО обчислює.
#
# Що саме доводиться:
#   1. Проєкт збирається справжнім FPC разом із Free Vision (TApplication,
#      TMenuBar, TStatusLine, TWindow, TListBox, TStringCollection, TInputLine).
#   2. Бінарник запускається й завершується: без термінала він відмовляє
#      названим кодом 3, а не висить і не падає в InitVideo.
#   3. Headless-свідок: «--без-вікон "(додати 2 3)"» друкує рівно «5»,
#      і в stderr названо, що в образі лежить опкод add (01 D8) за зсувом 130.
#      Отже число приходить із машинної інструкції, а не з echo-loop.
#   4. Негативний свідок: «--без-вікон "(додати 2 3 4)"» відмовляє з кодом,
#      відмінним від 0, і не друкує жодного числа в stdout.
#   5. Якщо є script(1) — той самий обчислювач перевіряється у справжньому
#      псевдотерміналі: набрана форма + Enter дають у вікні «2 3) … 5».
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

TRAP_MSG='echo "SENS-REPL-TUI-ТЕСТ-ВІДМОВА рядок=$LINENO команда=$BASH_COMMAND" >&2'
trap "$TRAP_MSG" ERR

[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo 'SENS-REPL-TUI-БЛОК: потрібен Linux x86-64' >&2; exit 127; }
for exe in fpc timeout mktemp grep sed cmp; do
  command -v "$exe" >/dev/null || {
    echo "SENS-REPL-TUI-БЛОК: відсутній $exe" >&2; exit 127; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/u" "$TMP/b"

FPC_BIN=${FPC:-fpc}
set -e

# --- 0. Збірка -------------------------------------------------------
# Free Vision живе в окремому пакунку FPC (fp-units-fv); якщо його немає,
# компілятор скаже «Fatal: Can't find unit App» — це названа відмова, а не
# привід вважати перевірку зеленою.
if ! timeout 240s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
     -Fu"$ROOT/src" -FU"$TMP/u" -FE"$TMP/b" \
     -osensrepltui "$ROOT/src/sensrepltui.lpr" >"$TMP/build.log" 2>&1; then
  echo 'SENS-REPL-TUI-ЗБІЙ: збірка sensrepltui.lpr' >&2
  cat "$TMP/build.log" >&2
  exit 1
fi
BIN="$TMP/b/sensrepltui"
[[ -x "$BIN" ]] || {
  echo "SENS-REPL-TUI-ЗБІЙ: немає бінарника $BIN" >&2; exit 1; }
echo 'SENS-REPL-TUI-OK збірка Free Vision + D12'

CHECKS=0
ok() { CHECKS=$((CHECKS+1)); echo "SENS-REPL-TUI-OK $1"; }
bad() { echo "SENS-REPL-TUI-ЗБІЙ $1" >&2; exit 1; }

# Навмисну відмову беремо в конструкцію «команда || код=$?»: це умова,
# тому ні set -e, ні ERR-пастка на неї не спрацьовують.

# --- 1. Бінарник запускається й завершується без термінала -----------
RC=0
timeout 20s "$BIN" </dev/null >"$TMP/tui.out" 2>"$TMP/tui.err" || RC=$?
[[ "$RC" -eq 3 ]] || bad "без термінала код $RC, а не 3"
grep -Fq 'SENS-REPL-TUI-ВІДМОВА' "$TMP/tui.err" || \
  bad 'відмова без термінала не названа'
[[ ! -s "$TMP/tui.out" ]] || bad 'без термінала щось надруковано в stdout'
ok 'бінарник запускається й завершується (без термінала код 3)'

# --- 2. Справжній псевдотермінал: Enter справді обчислює -------------
# Набираємо форму, Enter, потім Alt-X. Літери можуть бути перекодовані
# консольним драйвером Free Vision (CP437 → UTF-8), тому звіряємо
# ASCII-частини рядка історії: «2 3)» і « 5» поруч.
if command -v script >/dev/null; then
  PRC=0
  { printf '(додати 2 3)'; sleep 2; printf '\r'; sleep 2; printf '\033x'; sleep 1; } |
    timeout 45s script -q -c "$BIN" /dev/null >"$TMP/pty.out" 2>"$TMP/pty.err" ||
    PRC=$?
  [[ "$PRC" -eq 0 ]] || {
    echo "SENS-REPL-TUI-ЗБІЙ: TUI у псевдотерміналі завершився кодом $PRC" >&2
    head -c 400 "$TMP/pty.err" >&2 || true
    exit 1
  }
  sed -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' -e 's/\x1b[()][AB0]//g' \
    "$TMP/pty.out" >"$TMP/pty.txt" 2>/dev/null || cp "$TMP/pty.out" "$TMP/pty.txt"
  grep -aq '2 3)' "$TMP/pty.txt" || bad 'у вікні немає набраної форми'
  grep -aq '2 3).*5' "$TMP/pty.txt" || \
    bad 'у вікні немає результату 5 поруч із формою'
  ok 'TUI у псевдотерміналі: Enter обчислив, Alt-X завершив (код 0)'
else
  echo 'SENS-REPL-TUI-ПРИМІТКА немає script(1) — TUI без pty не перевіряється' >&2
fi

# --- 3. Headless-свідок: справжнє обчислення -------------------------
# Форма → очікуваний stdout. Кожен випадок іде через той самий шлях, що
# й вікно: розбір → ELF із add → запуск → stdout.
headless() {  # $1 — текст форми, $2 — очікуваний stdout
  local zapyt="$1" wanted="$2" rc
  rc=0
  timeout 30s "$BIN" --без-вікон "$zapyt" >"$TMP/hl.out" 2>"$TMP/hl.err" || rc=$?
  [[ "$rc" -eq 0 ]] || {
    echo "SENS-REPL-TUI-ЗБІЙ: код $rc для «$zapyt»" >&2
    cat "$TMP/hl.err" >&2
    exit 1
  }
  [[ "$(cat "$TMP/hl.out")" == "$wanted" ]] || {
    echo "SENS-REPL-TUI-ЗБІЙ: «$zapyt» дала «$(cat "$TMP/hl.out")»," \
      "а не «$wanted»" >&2
    cat "$TMP/hl.err" >&2
    exit 1
  }
  grep -Fq 'опкод-add=01d8' "$TMP/hl.err" || {
    echo "SENS-REPL-TUI-ЗБІЙ: немає свідка опкоду add для «$zapyt»" >&2
    cat "$TMP/hl.err" >&2
    exit 1
  }
  grep -Fq 'зсув-у-файлі=130' "$TMP/hl.err" || {
    echo "SENS-REPL-TUI-ЗБІЙ: зсув опкоду не 130 для «$zapyt»" >&2
    exit 1
  }
}

headless '(додати 2 3)' '5'
ok 'headless «(додати 2 3)» → 5 (вимога задачі буквально)'
headless '(додати 0 0)' '0'
headless '(додати -5 2)' '-3'
headless '(додати 2047 -2048)' '-1'
ok 'headless межі D12: 0+0, -5+2, 2047+(-2048)'

# Рівно байти «5\n», без жодного зайвого байта в stdout.
timeout 30s "$BIN" --без-вікон '(додати 2 3)' >"$TMP/piat.out" 2>/dev/null
printf '5\n' >"$TMP/piat.wanted"
cmp "$TMP/piat.wanted" "$TMP/piat.out" || bad 'stdout не рівно «5\n»'
ok 'stdout рівно «5\n» — жодного декору навколо числа'

# --- 4. Негативні свідки: відмова, а не тихе число -------------------
vidmova() {  # $1 — текст, $2 — підрядок діагностики
  local zapyt="$1" oznaka="$2" rc
  rc=0
  timeout 30s "$BIN" --без-вікон "$zapyt" >"$TMP/neg.out" 2>"$TMP/neg.err" || rc=$?
  [[ "$rc" -ne 0 ]] || {
    echo "SENS-REPL-TUI-ЗБІЙ: «$zapyt» прийнято (код 0)" >&2
    exit 1
  }
  [[ ! -s "$TMP/neg.out" ]] || {
    echo "SENS-REPL-TUI-ЗБІЙ: «$zapyt» щось надрукувала в stdout" >&2
    exit 1
  }
  grep -Fq 'SENS-REPL-БЕЗ-ВІКОН-ВІДМОВА' "$TMP/neg.err" || {
    echo "SENS-REPL-TUI-ЗБІЙ: відмова не названа для «$zapyt»" >&2
    cat "$TMP/neg.err" >&2
    exit 1
  }
  grep -Fq "$oznaka" "$TMP/neg.err" || {
    echo "SENS-REPL-TUI-ЗБІЙ: немає «$oznaka» для «$zapyt»" >&2
    cat "$TMP/neg.err" >&2
    exit 1
  }
}

vidmova '(додати 2 3 4)' 'зайвий доданок'
ok 'негативний свідок «(додати 2 3 4)» → відмова з кодом ≠ 0'
vidmova '(додати 2)' 'рівно два доданки'
vidmova '(додати 2 3' 'не закрита'
vidmova '(додати 2 3) хвіст' 'зайвий текст'
vidmova '(add 2 3)' '«додати»'
vidmova '(додати 5000 1)' 'D12'
vidmova '(додати 2048 0)' 'D12'
ok 'негативні свідки: арність, дужки, англійська голова, межа D12'

# Хибний виклик без форми — теж названа відмова.
VRC=0
timeout 20s "$BIN" --без-вікон >"$TMP/vyk.out" 2>"$TMP/vyk.err" || VRC=$?
[[ "$VRC" -ne 0 ]] || bad 'виклик без форми прийнято'
grep -Fq 'виклик:' "$TMP/vyk.err" || bad 'підказка виклику не названа'
ok 'виклик без форми → відмова з підказкою'

# --- 5. Каркас: правильні типи Free Vision --------------------------
# Меню й статус-рядок українською; користувацькі команди від 100;
# обʼєкт застосунку — через New(PSensReplApp, Init); історія — TListBox
# над TStringCollection, не абстрактний TListViewer.
grep -Fq "'~Ф~айл'" "$ROOT/src/sensrepltui.lpr" || bad 'меню «Файл» не українське'
grep -Fq "'~С~ередовище'" "$ROOT/src/sensrepltui.lpr" || \
  bad 'меню «Середовище» не українське'
grep -Fq 'cmSensOsnova = 100' "$ROOT/src/sensrepltui.lpr" || \
  bad 'межа користувацьких команд не 100'
grep -Fq 'New(PSensReplApp, Init)' "$ROOT/src/sensrepltui.lpr" || \
  bad 'обʼєкт застосунку не створюється через New(PSensReplApp, Init)'
grep -Fq 'New(PListBox, Init(R, 1, Smuh))' "$ROOT/src/sensrepltui.lpr" || \
  bad 'історія не TListBox'
grep -Fq 'New(PStringCollection, Init(0, 10))' "$ROOT/src/sensrepltui.lpr" || \
  bad 'історія не над TStringCollection'
grep -Fq 'New(PInputLine, Init(R, VelychinaVvodu))' "$ROOT/src/sensrepltui.lpr" || \
  bad 'немає поля вводу TInputLine'
grep -Fq 'New(PListViewer' "$ROOT/src/sensrepltui.lpr" && \
  bad 'історія створює абстрактний TListViewer'
ok 'каркас: меню українською, команди від 100, TListBox+TStringCollection, New(…, Init)'

echo "SENS-REPL-TUI-ГАРАЗ перевірок=$CHECKS headless=4" \
  "негативних=8 опкод-add=01d8 зсув=130"
echo "SENS-REPL-TUI-МЕЖА=вікно-малює-TApplication-число-рахує-машинна-add" \
  "форма-лише-(додати-N-M)-без-середовища-сеансу"
