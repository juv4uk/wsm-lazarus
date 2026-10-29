#!/usr/bin/env bash
# G5.76: перевірка обмеженого Pascal D3 stdin-адаптера, не незалежний SENS oracle.
# Вхідні українські форми походять з pinned D3:001 (укр=як-є).
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc timeout cmp grep head tr; do
  command -v "$tool" >/dev/null || { echo "D3-ВХІД-БЛОК: потрібен $tool" >&2; exit 127; }
done
./scripts/check-pin.sh
grep -F '(001 (ук як-є) (укр як-є)' external/sens/lib/domains/d3.lisp >/dev/null || {
  echo 'D3-ВХІД-БЛОК: pinned український D3:001 змінився' >&2
  exit 2
}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$TMP/units" -FE"$TMP/bin" -osens-oracle "$ROOT/src/sens_oracle.lpr"
BIN="$TMP/bin/sens-oracle"
test -x "$BIN"
CHECKS=0

# Вихід завжди порівнюємо байт-у-байт, а не за префіксом OK.
prohon() {
  local nazva="$1" kod="$2"
  if timeout 45s "$BIN" < "$TMP/in" > "$TMP/out" 2> "$TMP/err"; then
    actual=0
  else
    actual=$?
  fi
  if test "$actual" -ne "$kod" || ! cmp -s "$TMP/out" "$TMP/expected"; then
    echo "D3-ВХІД-ПОМИЛКА: $nazva код=$actual очікувано=$kod" >&2
    echo '--- отримано ---' >&2
    cat "$TMP/out" "$TMP/err" >&2
    echo '--- очікувано ---' >&2
    cat "$TMP/expected" >&2
    exit 1
  fi
  CHECKS=$((CHECKS + 1))
  echo "  добре  $nazva"
}

uspikh() {
  local nazva="$1" forma="$2" vidpovid="$3"
  printf '%s\n' "$forma" > "$TMP/in"
  printf 'READY\nOK\t%s\n' "$vidpovid" > "$TMP/expected"
  prohon "$nazva" 0
}

vidmova() {
  local nazva="$1" forma="$2"
  printf '%s\n' "$forma" > "$TMP/in"
  if timeout 45s "$BIN" < "$TMP/in" > "$TMP/out" 2> "$TMP/err"; then
    echo "D3-ВХІД-ПОМИЛКА: $nazva не відхилено" >&2
    exit 1
  else
    kod=$?
  fi
  test "$kod" -eq 2 || { echo "D3-ВХІД-ПОМИЛКА: $nazva код=$kod" >&2; exit 1; }
  test "$(head -n 1 "$TMP/out")" = READY
  test "$(grep -c '^ERR' "$TMP/out")" -eq 1
  test "$(grep -c '^OK' "$TMP/out" || :)" -eq 0
  CHECKS=$((CHECKS + 1))
  echo "  добре  $nazva (відмова)"
}

uspikh 'сполучити-так-порожнє' '(сполучити так ())' '(1)'
uspikh 'перше-списку'          '(перше (сполучити так ()))' '1'
uspikh 'решта-списку'          '(решта (сполучити так ()))' '()'
uspikh 'точна-укр-цитата'      '(як-є кіт)' '(1110010 1110011 1101110)'
uspikh 'умова-істинна'         '(за-умовою (так ні) (так так))' '0'
uspikh 'порожнє-значення'      '()' '()'
vidmova 'хибна-назва-D3'        '(цитата так)'
vidmova 'селектор-порожнього'  '(перше ())'
vidmova 'невідома-голова'      '(невідоме так)'

# Один write містить кілька форм: попередній 4096-byte Read губив хвіст.
printf '%s\n' 'ні' '(як-є кіт)' '(перше (сполучити так ()))' > "$TMP/in"
printf 'READY\nOK\t0\nOK\t(1110010 1110011 1101110)\nOK\t1\n' > "$TMP/expected"
prohon 'три-форми-в-одному-read' 0

# Останній рядок без LF теж має бути реально виконаний.
printf 'так' > "$TMP/in"
printf 'READY\nOK\t1\n' > "$TMP/expected"
prohon 'останній-рядок-без-LF' 0

# LF рівно за межею 4096; наступна форма має залишитися в черзі.
printf '%4095sтак\nні\n' '' > "$TMP/in"
printf 'READY\nOK\t1\nOK\t0\n' > "$TMP/expected"
prohon 'перехід-межі-4096' 0

# Пізня помилка перериває потокову сесію: третю форму НЕ виконувати.
printf 'так\n(перше ())\nні\n' > "$TMP/in"
if timeout 45s "$BIN" < "$TMP/in" > "$TMP/out" 2> "$TMP/err"; then
  echo 'D3-ВХІД-ПОМИЛКА: пізню помилку проігноровано' >&2
  exit 1
else
  kod=$?
fi
test "$kod" -eq 2
test "$(head -n 1 "$TMP/out")" = READY
test "$(grep -c '^OK' "$TMP/out")" -eq 1
test "$(grep -c '^ERR' "$TMP/out")" -eq 1
CHECKS=$((CHECKS + 1))

# Межа 1 МіБ: нуль часткових OK, один ERR, status=2.
head -c 1048577 /dev/zero | tr '\000' ' ' > "$TMP/in"
printf '\n' >> "$TMP/in"
if timeout 45s "$BIN" < "$TMP/in" > "$TMP/out" 2> "$TMP/err"; then
  echo 'D3-ВХІД-ПОМИЛКА: переповнений рядок прийнято' >&2
  exit 1
else
  kod=$?
fi
test "$kod" -eq 2
test "$(head -n 1 "$TMP/out")" = READY
grep -F 'форма перевищила 1 МіБ' "$TMP/out" >/dev/null
test "$(grep -c '^OK' "$TMP/out" || :)" -eq 0
CHECKS=$((CHECKS + 1))

echo "D3-ВХІД-ГАРАЗД перевірок=$CHECKS FPC=справжній багаторядковість=так EOF=так буфер=4096 розмір=1048576 незалежний-оракул=ні"
