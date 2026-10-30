#!/usr/bin/env bash
# G6.131: pinned D1–D10 «ук» / «укр» без рукописного Name→Bits.
# Збірка checked FPC та РЕАЛЬНИЙ Core1 REPL (стале середовище).
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
for tool in fpc timeout grep cmp git mktemp; do
  command -v "$tool" >/dev/null || { echo "CORE1-ПРОЄКЦІЇ-БЛОК: немає $tool" >&2;exit 127; }
done
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
test "$(git -C external/sens rev-parse HEAD)" = 2c498b35af53c085450eac6f51b87facf7f9aa47
# Static anti-duplication gate: жодного локального словника значень
# для доменних назв у виконуваному інтерфейсі.
if grep -Eq 'Mechanisms[[:space:]]*:|Name:[[:space:]]*\x27.*Bits:' src/senscore1repl.lpr; then
  echo 'CORE1-ПРОЄКЦІЇ-ЗБІЙ: дубльований Name→Bits реєстр у REPL' >&2;exit 1
fi
grep -Fq 'LoadPinnedProjections(' src/senscore1repl.lpr
grep -Fq 'SameKey(Key,Previous)' src/senscore1repl.lpr
grep -Fq 'KeyBits(Previous)' src/senscore1repl.lpr
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2;tail -n 60 "$f" >&2; }
  done
fi;rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
timeout 240s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  '-orepl' "$ROOT/src/senscore1repl.lpr" \
  >"$TMP/build.log" 2>&1 || { cat "$TMP/build.log" >&2;exit 1; }
test -x "$TMP/bin/repl"
# Потрібно перевірити не тільки правильне ім’я, а фактичну роботу
# pinned обчислювача і продовження сеансу після відмови.
cat >"$TMP/session.in" <<'INPUT'
(додати 2 3)
(відняти 7 3)
(порожнє? (як-є ()))
(порожній? (як-є ()))
(визначити подвоїти-нове (функція (а) (додати а а)))
(подвоїти-нове 9)
(визначити тіньова-пара (функція (модуль) (додати модуль 1)))
(тіньова-пара 9)
(застосувати (як-є ()) (як-є ()))
(додати 2)
(додати 3 4)
:quit
INPUT
timeout 100s "$TMP/bin/repl" "$ROOT" \
  <"$TMP/session.in" >"$TMP/out.log" 2>"$TMP/err.log"
# G3.68: реальна початкова кількість взята з чинного pinned
# Core1 runtime. Зміна 92→94 уже перевіряється окремим census gate;
# два успішні DEFINE мусять дати послідовно 95 та 96.
grep -Fxq 'Допущених визначень: 94 із 96.' "$TMP/out.log"
grep -vE '^(SENS Core1 REPL|Допущених визначень|Двійковий літерал|Команди:)' \
  "$TMP/out.log" >"$TMP/body.log"
# Оскільки кожну допустиму назву бере pinned каталог, ці перевірки
# перевіряють САМЕ виконання, а не статичне порівняння двох хештаблиць.
cat >"$TMP/expected" <<'EXPECTED'
5
4
1
1
визначено; усього 95
18
визначено; усього 96
10
7
EXPECTED
cmp "$TMP/expected" "$TMP/body.log"
grep -q 'помилка:' "$TMP/err.log"
grep -q 'арність' "$TMP/err.log"
# Непідтримана pinned голова відхиляється на рівні Core1 evaluator.
test "$(grep -c 'помилка:' "$TMP/err.log")" -ge 2
# Вже наявні 8 перевірок реального pinned Core1 і рекурсії
timeout 240s bash scripts/test-core1-repl.sh "$ROOT" >"$TMP/old.log" 2>"$TMP/old.err"
grep -Fq 'CORE1-REPL-PASS checks=9' "$TMP/old.log"
echo 'CORE1-PINNED-ПРОЄКЦІЇ-ГОТОВО uk=так ukr=так core1-session=так legacy-registry=ні aliases=2 lexical-shadow=так негативів=2 recovery=так regression=8'
