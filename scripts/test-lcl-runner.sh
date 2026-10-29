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
printf '\\300\\257' >"$TMP/ukr/пошкоджена.lisp"
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
echo 'LCL-ВИКОНАННЯ-ЗБІРКА-ГАРАЗД Lazarus=справжній екран=GTK2 результат=CLI адреси=трит-байт'
