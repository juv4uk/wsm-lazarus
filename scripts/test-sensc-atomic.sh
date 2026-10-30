#!/usr/bin/env bash
# G6.128 — host атомарність приватного SIR1, без семантичних припущень.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v fpc >/dev/null || { echo 'SIR1-БЛОК: немає FPC' >&2; exit 127; }
./scripts/check-no-lcl.sh
mkdir -p build/m0.2/sir1-atomic-units build/m0.2/bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/sir1-atomic-units" -FE"$ROOT/build/m0.2/bin" \
  -osensc "$ROOT/src/sensc.lpr"
BIN="$ROOT/build/m0.2/bin/sensc"
TMP=$(mktemp -d "$ROOT/build/m0.2/sir1-atomic.XXXXXXXX")
trap 'rm -rf "$TMP"' EXIT
printf '(перша)\n(друга)\n' > "$TMP/перша.lisp"
printf '(третя)\n' > "$TMP/друга.lisp"

(umask 000; "$BIN" --compile-ir "$TMP/перша.lisp" "$TMP/перша.sir" > "$TMP/створено")
"$BIN" --compile-ir "$TMP/перша.lisp" "$TMP/повтор.sir" > /dev/null
"$BIN" --compile-ir "$TMP/друга.lisp" "$TMP/інша.sir" > /dev/null
cmp "$TMP/перша.sir" "$TMP/повтор.sir"
"$BIN" --verify-ir "$TMP/перша.sir" > "$TMP/перевірено"
"$BIN" --inspect-ir "$TMP/перша.sir" > "$TMP/статистика"
grep -q 'SENSC-IR-OK' "$TMP/створено"
grep -q 'SENSC-SIR1-VERIFY-OK structural-only=1' "$TMP/перевірено"
grep -q 'structural-only=1' "$TMP/статистика"
test "$(stat -c %a "$TMP/перша.sir")" = 600
test "$(stat -c %h "$TMP/перша.sir")" = 1

reject() {
  local label=$1
  shift
  if "$@" > "$TMP/неуспіх.out" 2> "$TMP/неуспіх.err"; then
    echo "SIR1-ПРОВАЛ: прийнято $label" >&2
    exit 1
  fi
  if [[ -s "$TMP/неуспіх.out" ]] ||
     ! grep -q 'SENSC-FAIL' "$TMP/неуспіх.err"; then
    echo "SIR1-ПРОВАЛ: некоректна діагностика $label" >&2
    cat "$TMP/неуспіх.err" >&2
    exit 1
  fi
}

cp "$TMP/перша.sir" "$TMP/захищена-копія"
reject 'існуючий вихід' "$BIN" --compile-ir "$TMP/друга.lisp" "$TMP/перша.sir"
cmp "$TMP/перша.sir" "$TMP/захищена-копія"

cp "$TMP/перша.lisp" "$TMP/початковий-текст"
reject 'вхід як ціль' "$BIN" --compile-ir "$TMP/перша.lisp" "$TMP/перша.lisp"
cmp "$TMP/перша.lisp" "$TMP/початковий-текст"

ln -s "$TMP/несуттєва-ціль" "$TMP/посилання.sir"
reject 'висяче посилання' "$BIN" --compile-ir "$TMP/перша.lisp" "$TMP/посилання.sir"
[[ -L "$TMP/посилання.sir" && ! -e "$TMP/несуттєва-ціль" ]]

printf '(незакрита\n' > "$TMP/пошкоджена.lisp"
reject 'некоректне джерело' "$BIN" --compile-ir "$TMP/пошкоджена.lisp" "$TMP/пошкоджена.sir"
[[ ! -e "$TMP/пошкоджена.sir" ]]
reject 'відсутній каталог' "$BIN" --compile-ir "$TMP/перша.lisp" "$TMP/відсутній/результат.sir"
[[ ! -e "$TMP/відсутній/результат.sir" ]]

("$BIN" --compile-ir "$TMP/перша.lisp" "$TMP/гонка.sir" > "$TMP/гонка1.out" 2> "$TMP/гонка1.err") &
PID1=$!
("$BIN" --compile-ir "$TMP/друга.lisp" "$TMP/гонка.sir" > "$TMP/гонка2.out" 2> "$TMP/гонка2.err") &
PID2=$!
S1=0; S2=0
wait "$PID1" || S1=$?
wait "$PID2" || S2=$?
if (( (S1 == 0) + (S2 == 0) != 1 )); then
  echo "SIR1-ПРОВАЛ: гонка дала коди $S1 / $S2" >&2
  exit 1
fi
if ! cmp -s "$TMP/гонка.sir" "$TMP/перша.sir" &&
   ! cmp -s "$TMP/гонка.sir" "$TMP/інша.sir"; then
  echo 'SIR1-ПРОВАЛ: конкурентний вихід пошкоджений' >&2
  exit 1
fi
for N in 1 2; do
  if [[ "$N" == 1 && "$S1" != 0 ]] || [[ "$N" == 2 && "$S2" != 0 ]]; then
    [[ ! -s "$TMP/гонка$N.out" ]] && grep -q 'SENSC-FAIL' "$TMP/гонка$N.err" || {
      echo "SIR1-ПРОВАЛ: невірна діагностика гонки $N" >&2
      exit 1
    }
  fi
done
test "$(stat -c %a "$TMP/гонка.sir")" = 600
test "$(stat -c %h "$TMP/гонка.sir")" = 1
"$BIN" --verify-ir "$TMP/гонка.sir" >/dev/null
if find "$TMP" -maxdepth 1 -type f -name 'sir??????' -print -quit | grep -q .; then
  echo 'SIR1-ПРОВАЛ: залишений тимчасовий файл' >&2
  exit 1
fi
echo 'SIR1-АТОМАРНІСТЬ-ГАРАЗД FPC=так приватність=0600 no-clobber=так symlink=відмова race=1-of-2 cleanup=так'
echo 'SIR1-МЕЖА структурний-IR=так native-codegen=ні .sens-канон=ні'
