#!/usr/bin/env bash
# G4.43: структурний перепис української Core4.lisp ≠ допуск/виконання
# фізичної Core4.sens. Лише ратифікований upstream визначає закони.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc grep sed cmp cp mktemp; do
  command -v "$tool" >/dev/null || {
    echo "CORE4-ПЕРЕПИС-БЛОК: немає $tool" >&2; exit 127;
  }
done
./scripts/check-pin.sh
# Ці тести виконують дійсну фізичну Core4 програму/виклики,
# а не тільки оцінюють декларативне число у лічильнику.
timeout 240s bash ./scripts/test-core4manifest.sh
timeout 240s bash ./scripts/test-core4runtime.sh
mkdir -p build/m0.2/core4-pokryttia-units build/m0.2/bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core4-pokryttia-units" \
  -FE"$ROOT/build/m0.2/bin" -osenscore4pokryttia \
  "$ROOT/src/senscore4pokryttia.lpr"
CLI="$ROOT/build/m0.2/bin/senscore4pokryttia"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$CLI" --перепис "$ROOT" >"$TMP/перший" 2>"$TMP/перший.err"
"$CLI" --перепис "$ROOT" >"$TMP/другий" 2>"$TMP/другий.err"
cmp "$TMP/перший" "$TMP/другий"
grep -Fq '0 unfreed memory blocks : 0' "$TMP/перший.err"
grep -Fq '0 unfreed memory blocks : 0' "$TMP/другий.err"
test "$(wc -l <"$TMP/перший")" -eq 1
# Незалежний лише ЛЕКСИЧНИЙ підрахунок pinned людського джерела.
# Ніякий збіг spelling не уповноважує виклик у native runtime.
COUNT=$(LC_ALL=C grep -c '^[(]визначити ' "$ROOT/external/sens/lib/core4.lisp")
test "$COUNT" -eq 1223 || {
  echo "CORE4-ПЕРЕПИС-ПРОВАЛ: pinned lexical count $COUNT != 1223" >&2; exit 1;
}
LINE=$(cat "$TMP/перший")
[[ "$LINE" == "CORE4-ПЕРЕПИС-ГАРАЗД форм-укр=$COUNT визначень-укр=$COUNT "* ]] || {
  echo "CORE4-ПЕРЕПИС-ПРОВАЛ: неповна структурна українська звірка: $LINE" >&2; exit 1;
}
[[ "$LINE" == *' завантажено-фізично=3 виконання-всіх=не-доведено' ]] || {
  echo "CORE4-ПЕРЕПИС-ПРОВАЛ: не збережено межу реального runtime: $LINE" >&2; exit 1;
}
[[ "$LINE" =~ тіл-списків=([0-9]+)[[:space:]]тіл-атомів=([0-9]+)[[:space:]]тіл-рядків=([0-9]+)[[:space:]]тіл-інших=([0-9]+) ]] || {
  echo "CORE4-ПЕРЕПИС-ПРОВАЛ: немає структурних категорій" >&2; exit 1;
}
SUM=$((10#${BASH_REMATCH[1]}+10#${BASH_REMATCH[2]}+10#${BASH_REMATCH[3]}+10#${BASH_REMATCH[4]}))
test "$SUM" -eq "$COUNT" || {
  echo "CORE4-ПЕРЕПИС-ПРОВАЛ: класи тіла не покривають всі визначення" >&2; exit 1;
}
mkdir -p "$TMP/хибний/external/sens/lib"
cp "$ROOT/external/sens/lib/core4.lisp" "$TMP/хибний/external/sens/lib/core4.lisp"
cp "$ROOT/external/sens/lib/core4.sens" "$TMP/хибний/external/sens/lib/core4.sens"
reject() {
  if "$@" >"$TMP/частковий-stdout" 2>"$TMP/помилка"; then
    echo 'CORE4-ПЕРЕПИС-ПРОВАЛ: хибне джерело допущено' >&2; exit 1;
  fi
  test ! -s "$TMP/частковий-stdout" || {
    echo 'CORE4-ПЕРЕПИС-ПРОВАЛ: частковий stdout після відмови' >&2; exit 1;
  }
  grep -Fq 'CORE4-ПЕРЕПИС-ВІДМОВА:' "$TMP/помилка" || {
    cat "$TMP/помилка" >&2; exit 1;
  }
}
reject "$CLI" --невідомо "$ROOT"
reject "$CLI" --перепис "$TMP/неіснуючий"
printf '(незакрита' >"$TMP/хибний/external/sens/lib/core4.lisp"
reject "$CLI" --перепис "$TMP/хибний"
printf '\300\257' >"$TMP/хибний/external/sens/lib/core4.lisp"
reject "$CLI" --перепис "$TMP/хибний"
: >"$TMP/хибний/external/sens/lib/core4.lisp"
reject "$CLI" --перепис "$TMP/хибний"
printf '(визначити один ())\n' >"$TMP/хибний/external/sens/lib/core4.lisp"
reject "$CLI" --перепис "$TMP/хибний"  # 1 у проєкції != 3 фізично завантажених
cp "$ROOT/external/sens/lib/core4.lisp" "$TMP/хибний/external/sens/lib/core4.lisp"
printf '\377' >"$TMP/хибний/external/sens/lib/core4.sens"
reject "$CLI" --перепис "$TMP/хибний"
rm "$TMP/хибний/external/sens/lib/core4.sens"
reject "$CLI" --перепис "$TMP/хибний"
echo "CORE4-ПЕРЕПИС-ТЕСТ-ГАРАЗД форм=$COUNT завантажено=3 структурний-стан=так негативні=7 пам'ять=0"
