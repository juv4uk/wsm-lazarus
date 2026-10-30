#!/usr/bin/env bash
# G6.254 — число census у дорожній карті мусить збігатися з тестом REPL.
#
# Навіщо: після кожного бампа піна/відбірника census зростає, і число
# доводилося правити в ДВОХ місцях: у `test-core1-repl.sh` і в тексте
# `docs/native-system-roadmap.uk.md`. Документ відстав на два значення
# (104 проти 112) і ніхто цього не бачив — тест зелений, бо він про інше.
#
# Тепер джерело правди одне: `EXPECTED_ADMITTED` у тесті. Цей гейт падає,
# якщо документ розійшовся з ним, і називає обидва числа.
set -uo pipefail
cd "$(dirname "$0")/.."

TEST=scripts/test-core1-repl.sh
DOC=docs/native-system-roadmap.uk.md

[ -f "$TEST" ] || { echo "DOC-CENSUS-FAIL немає $TEST" >&2; exit 1; }
[ -f "$DOC" ]  || { echo "DOC-CENSUS-FAIL немає $DOC" >&2; exit 1; }

# 1) допущене число з тесту
ADM=$(grep -oE 'CORE1_EXPECTED_ADMITTED:-[0-9]+' "$TEST" | grep -oE '[0-9]+$' | head -1)
[ -n "$ADM" ] || { echo "DOC-CENSUS-FAIL у $TEST не знайдено EXPECTED_ADMITTED" >&2; exit 1; }

# 2) оголошене число з pinned core1.lisp (як у самому тесті)
DECL=$(grep -c '^(визначити' external/sens/lib/core1.lisp 2>/dev/null || echo 0)

# 3) числа з дорожньої карти
DOC_ADM=$(grep -oE 'приймає [0-9]+ із [0-9]+ фізичних визначень' "$DOC" | grep -oE '[0-9]+' | head -1)
DOC_DECL=$(grep -oE 'приймає [0-9]+ із [0-9]+ фізичних визначень' "$DOC" | grep -oE '[0-9]+' | tail -1)

fail=0
if [ "$DOC_ADM" != "$ADM" ]; then
  echo "DOC-CENSUS-FAIL дорожня карта каже «приймає $DOC_ADM», а тест очікує $ADM" >&2
  fail=1
fi
# Оголошене число звіряємо ЛИШЕ на повній копії піна. Локальна копія буває
# неповною (sparse-checkout не витягує частину шляхів через українські імена),
# і тоді grep бачить менше визначень — це стан середовища, а не дрейф доказу.
# Поріг 100 відділяє повну копію (129) від обрізаної (96), не вдаючи точності.
if [ "$DECL" -ge 100 ]; then
  if [ -n "$DOC_DECL" ] && [ "$DOC_DECL" != "$DECL" ]; then
    echo "DOC-CENSUS-FAIL дорожня карта каже «із $DOC_DECL», а pinned core1.lisp оголошує $DECL" >&2
    fail=1
  fi
else
  echo "DOC-CENSUS-УВАГА локальна копія піна неповна (оголошено $DECL) — звірку оголошеного пропущено" >&2
fi

if [ "$fail" -ne 0 ]; then
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error title=census у документації::$DOC розійшовся з $TEST; оновіть число в документі" >&2
  fi
  exit 1
fi
echo "DOC-CENSUS-PASS допущено=$ADM оголошено=$DECL"
