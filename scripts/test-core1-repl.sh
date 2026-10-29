#!/usr/bin/env bash
# G5.70 — REPL Core1: читання проєкції, виконання у сталому середовищі,
# друк результату. Перевіряємо саме сеанс: кілька рядків поспіль,
# помилки не завершують сеанс, відмова голови-механізму явна.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/u" "$WORK/b"
FAIL=0

ok() { printf 'CORE1-REPL-OK   %s\n' "$1"; }
bad() { printf 'CORE1-REPL-ЗБІЙ %s\n' "$1"; FAIL=1; }

if ! fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" -FU"$WORK/u" \
     -FE"$WORK/b" -o"$WORK/repl" "$ROOT/src/senscore1repl.lpr" \
     > "$WORK/build.log" 2>&1; then
  bad "збірка REPL"
  cat "$WORK/build.log"
  exit 1
fi
ok "збірка REPL"

cat > "$WORK/session.in" <<'SESSION'
(додати 2 3)
(ядро1-помножити 6 7)
(менше? 2 3)
(частка 7 2)
(змінити-знак 5)
(додати 2)
(невідоме-імʼя 1)
(додати 2 3)
:quit
SESSION

cat > "$WORK/expected" <<'EXPECTED'
5
42
1
3
-5
5
EXPECTED

"$WORK/repl" "$ROOT" < "$WORK/session.in" > "$WORK/out" 2> "$WORK/err"
RC=$?

grep -vE '^(SENS Core1 REPL|Допущених визначень|Двійковий літерал|Команди:)' \
  "$WORK/out" > "$WORK/out.body"

if [ "$RC" -ne 0 ]; then
  bad "код виходу сеансу $RC"
else
  ok "код виходу 0"
fi

if diff -q "$WORK/expected" "$WORK/out.body" > /dev/null; then
  ok "три результати поспіль"
else
  bad "результати сеансу"
  diff "$WORK/expected" "$WORK/out.body" || true
fi

# Помилка рядка не завершує сеанс: після трьох відмов іде четвертий результат.
if [ "$(tail -1 "$WORK/out.body")" = "5" ]; then
  ok "сеанс живий після двох відмов"
else
  bad "сеанс обірвався на помилці"
fi

if grep -q 'голова-механізм' "$WORK/err"; then
  bad "голова-механізм досі відхиляється"
else
  ok "голови-механізмів виконуються"
fi

if grep -q 'арність' "$WORK/err"; then
  ok "невірна арність названа"
else
  bad "невірна арність не названа"
fi

if grep -q 'невідоме' "$WORK/err"; then
  ok "невідоме імʼя назване"
else
  bad "невідоме імʼя не назване"
fi

if [ "$FAIL" -ne 0 ]; then
  echo "CORE1-REPL-FAIL"
  exit 1
fi
echo "CORE1-REPL-PASS checks=6"
echo "CORE1-REPL-LIMIT=not-full-SENS-no-user-definitions-no-GC"
