#!/usr/bin/env bash
# G3.20: український укр input -> pinned physical T5M -> реальний D3,
# жодного альтернативного evaluator, тільки атомарний новий .sens.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'УКР-ВИКОНАННЯ-БЛОК: потрібен справжній FPC' >&2
  exit 127
}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/inputs" "$TMP/outputs" "$TMP/reference"

for entry in sensukrvykon sensukrlisp senspaketd3; do
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$TMP/units" -FE"$TMP/bin" -o"$entry" "$ROOT/src/$entry.lpr" \
    >"$TMP/compile-$entry.log" 2>&1 || {
      cat "$TMP/compile-$entry.log" >&2
      exit 1
    }
done
NEW="$TMP/bin/sensukrvykon"
PACK="$TMP/bin/sensukrlisp"
OLD="$TMP/bin/senspaketd3"
CHECKS=0

ok() {
  local id="$1" count="$2"
  "$NEW" --виконати-укр external/sens "$TMP/inputs/$id.lisp" \
    "$TMP/outputs/$id.sens" >"$TMP/ok-$id.log" 2>"$TMP/ok-$id.err"
  test ! -s "$TMP/ok-$id.err"
  grep -Fq "УКР-ФІЗИЧНЕ-ВИКОНАННЯ-ГАРАЗД форм=$count" "$TMP/ok-$id.log"
  "$PACK" --пакувати-ук "$TMP/inputs/$id.lisp" \
    "$TMP/reference/$id.sens" >"$TMP/pack-$id.log" 2>&1
  "$OLD" --пакет external/sens "$TMP/reference/$id.sens" \
    "$TMP/reference/$id-answer.sens" >"$TMP/old-$id.log" 2>&1
  cmp "$TMP/outputs/$id.sens" "$TMP/reference/$id-answer.sens"
  CHECKS=$((CHECKS+1))
}

bad() {
  local reason="$1"; shift
  if "$NEW" "$@" >"$TMP/reject.out" 2>"$TMP/reject.err"; then
    echo "УКР-ВИКОНАННЯ-ПОМИЛКА: прийнято $reason" >&2
    exit 1
  fi
  if test -s "$TMP/reject.out" || ! grep -Fq 'ПОМИЛКА-УКР-ВИКОНАННЯ' "$TMP/reject.err"; then
    echo "УКР-ВИКОНАННЯ-ПОМИЛКА: часткова публікація або немає діагностики: $reason" >&2
    cat "$TMP/reject.out" "$TMP/reject.err" >&2
    exit 1
  fi
  CHECKS=$((CHECKS+1))
}

printf 'ні\n' >"$TMP/inputs/one.lisp"
printf '(сполучити ні так)\nні\nтак\n(атом? так)\n' >"$TMP/inputs/four.lisp"
for ((i=0; i<64; i++)); do printf 'так\n'; done >"$TMP/inputs/sixtyfour.lisp"
ok one 1
ok four 4
ok sixtyfour 64

# Після справжнього виконання відповідь є T5M, а не echo українського тексту.
if cmp -s "$TMP/inputs/one.lisp" "$TMP/outputs/one.sens"; then
  echo 'УКР-ВИКОНАННЯ-ПОМИЛКА: повернуто вхідний текст' >&2
  exit 1
fi
CHECKS=$((CHECKS+1))

printf 'ні\n(як-є так ні)\n' >"$TMP/inputs/late.lisp"
bad 'пізня D3-помилка' --виконати-укр external/sens \
  "$TMP/inputs/late.lisp" "$TMP/outputs/late.sens"
grep -Fq 'форма=2' "$TMP/reject.err"
test ! -e "$TMP/outputs/late.sens"
CHECKS=$((CHECKS+1))

for ((i=0; i<65; i++)); do printf 'так\n'; done >"$TMP/inputs/65.lisp"
bad '65 форм' --виконати-укр external/sens "$TMP/inputs/65.lisp" "$TMP/outputs/65.sens"
test ! -e "$TMP/outputs/65.sens"
printf 'car\n' >"$TMP/inputs/english.lisp"
bad 'англійська голова не є укр' --виконати-укр external/sens \
  "$TMP/inputs/english.lisp" "$TMP/outputs/english.sens"
printf '123\n' >"$TMP/inputs/numbers.lisp"
bad 'непідтверджена D12+ числова проєкція' --виконати-укр external/sens \
  "$TMP/inputs/numbers.lisp" "$TMP/outputs/numbers.sens"
printf 'неіснуюча-українська-назва\n' >"$TMP/inputs/unknown.lisp"
bad 'невідоме укр' --виконати-укр external/sens \
  "$TMP/inputs/unknown.lisp" "$TMP/outputs/unknown.sens"
printf '\300\257' >"$TMP/inputs/invalid.lisp"
bad 'некоректний UTF-8' --виконати-укр external/sens \
  "$TMP/inputs/invalid.lisp" "$TMP/outputs/invalid.sens"
: >"$TMP/inputs/empty.lisp"
bad 'порожній вхід' --виконати-укр external/sens \
  "$TMP/inputs/empty.lisp" "$TMP/outputs/empty.sens"
bad 'відсутній файл' --виконати-укр external/sens \
  "$TMP/inputs/missing.lisp" "$TMP/outputs/missing.sens"
bad 'хибний корінь' --виконати-укр "$TMP/absent-authority" \
  "$TMP/inputs/one.lisp" "$TMP/outputs/absent.sens"
bad 'відсутній каталог результату' --виконати-укр external/sens \
  "$TMP/inputs/one.lisp" "$TMP/absent-dir/answer.sens"
printf 'незмінний файл\n' >"$TMP/outputs/occupied.sens"
cp "$TMP/outputs/occupied.sens" "$TMP/occupied-copy"
bad 'наявний вихід' --виконати-укр external/sens \
  "$TMP/inputs/one.lisp" "$TMP/outputs/occupied.sens"
cmp "$TMP/outputs/occupied.sens" "$TMP/occupied-copy"
ln -s "$TMP/missing-target" "$TMP/outputs/dangling.sens"
bad 'символьне посилання' --виконати-укр external/sens \
  "$TMP/inputs/one.lisp" "$TMP/outputs/dangling.sens"
test -L "$TMP/outputs/dangling.sens"
test ! -e "$TMP/missing-target"
bad 'не двійковий результат' --виконати-укр external/sens \
  "$TMP/inputs/one.lisp" "$TMP/outputs/forbidden.lisp"
bad 'не український вхід' --виконати-укр external/sens \
  "$TMP/outputs/one.sens" "$TMP/outputs/forbidden.sens"
bad 'невідомий режим' --не-виконувати external/sens \
  "$TMP/inputs/one.lisp" "$TMP/outputs/mode.sens"

# Після негативів нормальна незалежна форма виконується повторно.
cp "$TMP/inputs/one.lisp" "$TMP/inputs/recovery.lisp"
ok recovery 1
cmp "$TMP/outputs/one.sens" "$TMP/outputs/recovery.sens"
echo "УКР-ФІЗИЧНЕ-D3-ГАРАЗД: FPC виконано; перевірок=$CHECKS; oracle=чинний-фізичний-D3; T5M=байт-у-байт; невідомі/D12+=відхилено; REPL/Core4=не-доведено"
