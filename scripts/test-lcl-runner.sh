#!/usr/bin/env bash
# Доводить реальний Lazarus/LCL плюс тотожність результату чинному CLI.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-ВИКОНАННЯ-БЛОК: відсутній lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ВИКОНАННЯ-БЛОК: відсутній xvfb-run' >&2; exit 127; }
./scripts/check-no-lcl.sh
./scripts/check-pin.sh
# Фізичні fixtures і виконавчий CLI проходять власні незалежні FPC тести.
bash ./scripts/test-binaryexec.sh
# Той самий реальний FPC адаптер координат — без GUI-власного decoder.
bash ./scripts/test-execfault.sh
mkdir -p build/lcl-runner/units
lazbuild --widgetset=gtk2 --build-all gui/sens-runner.lpi
BIN="$ROOT/build/lcl-runner/sens-runner"
[[ -x "$BIN" ]] || { echo 'LCL-ВИКОНАННЯ-БЛОК: немає GUI-бінарника' >&2; exit 1; }
GOOD="build/m0.2/binaryexec-valid.sens"
BAD="build/m0.2/binaryexec-invalid.sens"
NESTED="build/m0.2/execfault-nested.sens"
EOF_FILE="build/m0.2/execfault-eof.sens"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '\363' > "$TMP/пошкоджений.sens"
EXPECTED=$(./build/m0.2/bin/sensvykon --виконати "$GOOD")
[[ "$EXPECTED" == '(1)' ]] || { echo 'LCL-ВИКОНАННЯ-БЛОК: неочікуваний CLI результат' >&2; exit 1; }
LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x800x24' "$BIN" \
  --самоперевірка "$GOOD" "$BAD" "$NESTED" "$EOF_FILE" \
  "$TMP/пошкоджений.sens" "$EXPECTED" | tee "$TMP/лог"
grep -F 'LCL-ФІЗИЧНА-ПОМИЛКА-ГАРАЗД' "$TMP/лог"
# G5.35: уже злитий G5.34 фізичний D3-канал; без нового evaluator.
# Прямий режим вище залишається активним і проходить старі негативні тести.
timeout 180 bash ./scripts/test-potikd3.sh
CHANNEL="$ROOT/build/potikd3/bin/senspotikd3"
FIX="$ROOT/build/paketd3-cli/fixtures"
test -x "$CHANNEL"
for label in one one-answer late-bad d12 four bad-t5m; do
  test -s "$FIX/$label.sens"
done
LC_ALL=C.UTF-8 timeout 55 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка-канал external/sens "$CHANNEL" \
  "$FIX/one.sens" "$FIX/one-answer.sens" "$FIX/late-bad.sens" \
  "$FIX/d12.sens" "$FIX/four.sens" "$FIX/bad-t5m.sens" \
  >"$TMP/channel-out" 2>"$TMP/channel-err" || {
    cat "$TMP/channel-err" >&2
    cat "$TMP/channel-out" >&2
    exit 1
  }
test ! -s "$TMP/channel-err"
cat "$TMP/channel-out"
grep -Fq 'LCL-Д3-ПОСТІЙНИЙ-КАНАЛ-ГАРАЗД' "$TMP/channel-out"
grep -Fq 'PID=незмінний T5M=побайтово' "$TMP/channel-out"
grep -Fq 'пізня-відмова=очищено D12+=відхилено пакет=відхилено' "$TMP/channel-out"
grep -Fq 'відновлення=так REPL=ні Core4=не-виконується' "$TMP/channel-out"
echo 'LCL-Д3-КАНАЛ-CI-ГАРАЗД FPC=справжній Lazarus=GTK2 той-самий-PID=так'
# G5.39 — незалежний реальний FPC oracle для повної pinned укр проєкції.
# Старий фізичний тест та G5.35 не послаблено. Третій GUI/evaluator не створюємо.
timeout 180 bash ./scripts/test-ukr-physical-execution.sh
mkdir -p "$TMP/ukr" "$TMP/ukr-bin" "$TMP/ukr-units"
FPC_BIN="${FPC:-fpc}"
timeout 120 "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/ukr-units" -FE"$TMP/ukr-bin" \
  -osensukrvykon "$ROOT/src/sensukrvykon.lpr" >"$TMP/ukr-build.log" 2>&1 || {
    cat "$TMP/ukr-build.log" >&2
    exit 1
  }
printf 'ні\n' >"$TMP/ukr/ні.lisp"
printf '(атом? так)\n' >"$TMP/ukr/атом.lisp"
printf 'car\n' >"$TMP/ukr/англійська.lisp"
printf '123\n' >"$TMP/ukr/число.lisp"
printf 'невідоме-слово\n' >"$TMP/ukr/невідома.lisp"
printf '\300\257' >"$TMP/ukr/пошкоджена.lisp"
: >"$TMP/ukr/порожня.lisp"
printf 'ні\nтак\n' >"$TMP/ukr/дві.lisp"
printf 'ні\n(як-є так ні)\n' >"$TMP/ukr/пізня.lisp"
printf 'ні\n' >"$TMP/ukr/нефізична.sens"
for kind in ні атом; do
  timeout 30 "$TMP/ukr-bin/sensukrvykon" --виконати-укр external/sens \
    "$TMP/ukr/$kind.lisp" "$TMP/ukr/$kind-відповідь.sens" \
    >"$TMP/ukr-$kind.out" 2>"$TMP/ukr-$kind.err" || {
      cat "$TMP/ukr-$kind.err" >&2
      cat "$TMP/ukr-$kind.out" >&2
      exit 1
    }
  test ! -s "$TMP/ukr-$kind.err"
  grep -Fq 'УКР-ФІЗИЧНЕ-ВИКОНАННЯ-ГАРАЗД форм=1' "$TMP/ukr-$kind.out"
done
cmp "$FIX/one-answer.sens" "$TMP/ukr/ні-відповідь.sens"
# Після двох ukr запитів виконується фізичний .sens, знову ukr,
# далі реальні негативи та відновлення БЕЗ зміни дитячого PID.
LC_ALL=C.UTF-8 timeout 65 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка-укр external/sens "$CHANNEL" "$FIX/one.sens" \
  "$TMP/ukr/ні.lisp" "$TMP/ukr/ні-відповідь.sens" \
  "$TMP/ukr/атом.lisp" "$TMP/ukr/атом-відповідь.sens" "$TMP/ukr" \
  >"$TMP/ukr-lcl.out" 2>"$TMP/ukr-lcl.err" || {
    cat "$TMP/ukr-lcl.err" >&2
    cat "$TMP/ukr-lcl.out" >&2
    exit 1
  }
test ! -s "$TMP/ukr-lcl.err"
cat "$TMP/ukr-lcl.out"
grep -Fq 'LCL-УКР-ФІЗИЧНЕ-D3-ГАРАЗД' "$TMP/ukr-lcl.out"
grep -Fq 'oracle=дійсний-FPC-T5M PID=незмінний' "$TMP/ukr-lcl.out"
grep -Fq 'D7=дані D12+=відхилено UTF8=суворо' "$TMP/ukr-lcl.out"
grep -Fq 'відновлення=так REPL=ні Core4=ні' "$TMP/ukr-lcl.out"
echo 'LCL-УКР-D3-CI-ГАРАЗД FPC=справжній Lazarus=GTK2 pinned=укр фізичний=канонічний'
# G5.44: реальний LCL Export нового canonical T5M з того самого D3 процесу.
# Свідки G3.17 та попередні GUI українська/помилки лишаються активними.
mkdir -p "$TMP/save"
printf 'недоторканний-файл\n' > "$TMP/save/зайнята.sens"
cp "$TMP/save/зайнята.sens" "$TMP/зайнята-до"
ln -s "$TMP/save/відсутня-ціль" "$TMP/save/посилання.sens"
LC_ALL=C.UTF-8 timeout 55 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка-збереження external/sens "$CHANNEL" \
  "$FIX/one.sens" "$FIX/one-answer.sens" "$FIX/late-bad.sens" \
  "$TMP/save" >"$TMP/save-lcl.out" 2>"$TMP/save-lcl.err" || {
    cat "$TMP/save-lcl.err" >&2
    cat "$TMP/save-lcl.out" >&2
    exit 1
  }
test ! -s "$TMP/save-lcl.err"
cat "$TMP/save-lcl.out"
grep -Fq 'LCL-D3-ЗБЕРЕЖЕННЯ-ГАРАЗД' "$TMP/save-lcl.out"
grep -Fq 'no-clobber=так symlink=відхилено' "$TMP/save-lcl.out"
grep -Fq 'після-відмови=порожньо PID=незмінний' "$TMP/save-lcl.out"
cmp "$FIX/one-answer.sens" "$TMP/save/нова.sens"
cmp "$FIX/one-answer.sens" "$TMP/save/відновлена.sens"
cmp "$TMP/зайнята-до" "$TMP/save/зайнята.sens"
test -L "$TMP/save/посилання.sens"
test ! -e "$TMP/save/відсутня-ціль"
test ! -e "$TMP/save/після-відмови.sens"
test ! -e "$TMP/save/не-канон.lisp"
test ! -e "$TMP/save/завчасно.sens"
# У цільовому каталозі не лишилось приватних senXXXXXX temp.
test "$(find "$TMP/save" -maxdepth 1 -type f | wc -l)" -eq 3
echo 'LCL-D3-ЗБЕРЕЖЕННЯ-CI-ГАРАЗД GTK2=справжній фізичні-байти=точні переписування=ні'
# G5.46 — pinned шість проєкцій з фактично виконаної канонічної D3-відповіді.
# Той самий GUI/канал/тести. Окремі D7 і W12 — тільки read-only проєкції.
LC_ALL=C.UTF-8 timeout 65 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка-проєкцій external/sens "$CHANNEL" \
  "$FIX/one.sens" "$FIX/one-answer.sens" \
  "$TMP/ukr/атом.lisp" "$TMP/ukr/атом-відповідь.sens" \
  "$FIX/late-bad.sens" "$FIX/d12.sens" \
  >"$TMP/projections-lcl.out" 2>"$TMP/projections-lcl.err" || {
    cat "$TMP/projections-lcl.err" >&2
    cat "$TMP/projections-lcl.out" >&2
    exit 1
  }
test ! -s "$TMP/projections-lcl.err"
cat "$TMP/projections-lcl.out"
grep -Fq "LCL-ШІСТЬ-ПРОЄКЦІЙ-ГАРАЗД" "$TMP/projections-lcl.out"
grep -Fq "ук/укр/san/en/LISP/sym=pinned D7-дужка=лише-дані" "$TMP/projections-lcl.out"
grep -Fq "W12=без-проєкції D12+=не-виконано" "$TMP/projections-lcl.out"
grep -Fq "після-відмови=порожньо PID=незмінний" "$TMP/projections-lcl.out"
echo 'LCL-ШІСТЬ-ПРОЄКЦІЙ-CI-ГАРАЗД pinned=D1..D10 D7=тільки-дані Lazarus=GTK2'
# G5.49: реальні 1/4/64 FPC фізичні D3 форми у ДВОХ незалежних GUI PID.
# Залишаємо старі single, укр, pinned-проєкції і безпечний експорт.
LC_ALL=C.UTF-8 timeout 80 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка-пакета external/sens "$CHANNEL" \
  "$FIX/one.sens" "$FIX/one-answer.sens" \
  "$FIX/four.sens" "$FIX/four-answer.sens" \
  "$FIX/64.sens" "$FIX/64-answer.sens" \
  "$FIX/late-bad.sens" "$FIX/d12.sens" \
  "$FIX/65.sens" "$FIX/bad-t5m.sens" \
  >"$TMP/batch-lcl.out" 2>"$TMP/batch-lcl.err" || {
    cat "$TMP/batch-lcl.err" >&2
    cat "$TMP/batch-lcl.out" >&2
    exit 1
  }
test ! -s "$TMP/batch-lcl.err"
cat "$TMP/batch-lcl.out"
grep -Fq "LCL-ПАКЕТ-D3-ГАРАЗД" "$TMP/batch-lcl.out"
grep -Fq "T5M=байт-у-байт коренів=1/4/64" "$TMP/batch-lcl.out"
grep -Fq "PID-пакет=незмінний PID-single=незмінний" "$TMP/batch-lcl.out"
grep -Fq "пізня-помилка=очищено D12+=відхилено 65=відхилено" "$TMP/batch-lcl.out"
echo 'LCL-ПАКЕТ-D3-CI-ГАРАЗД FPC=справжній Lazarus=GTK2 D2=1/4/64'
echo 'LCL-ВИКОНАННЯ-ЗБІРКА-ГАРАЗД Lazarus=справжній екран=GTK2 результат=CLI адреси=трит-байт'
