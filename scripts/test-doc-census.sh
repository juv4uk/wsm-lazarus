#!/usr/bin/env bash
# G6.254 — самоперевірка гейта «census у документі = census у тесті».
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CHECKS=0
ok()  { CHECKS=$((CHECKS+1)); echo "DOCCENSUS-OK   $*"; }
bad() { echo "DOCCENSUS-ЗБІЙ $*" >&2; exit 1; }

mkdir -p "$TMP/scripts" "$TMP/docs" "$TMP/external/sens/lib"
cp "$ROOT/scripts/check-doc-census.sh" "$TMP/scripts/"

# Повна копія піна: 120 визначень.
for i in $(seq 1 120); do echo "(визначити f$i (функція (x) x))"; done > "$TMP/external/sens/lib/core1.lisp"

printf 'EXPECTED_ADMITTED="${CORE1_EXPECTED_ADMITTED:-110}"\n' > "$TMP/scripts/test-core1-repl.sh"

# 1) Документ збігається з тестом — проходить.
printf 'селектор приймає 110 із 120 фізичних визначень pinned\n' > "$TMP/docs/native-system-roadmap.uk.md"
out=$(cd "$TMP" && bash scripts/check-doc-census.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "збіг проходить" || bad "впало на збігу: $out"

# 2) Документ відстав від тесту — падає і називає обидва числа.
printf 'селектор приймає 104 із 120 фізичних визначень pinned\n' > "$TMP/docs/native-system-roadmap.uk.md"
out=$(cd "$TMP" && bash scripts/check-doc-census.sh 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "розбіжність валить гейт" || bad "не впало (rc=$rc)"
printf '%s' "$out" | grep -q 'каже «приймає 104», а тест очікує 110' && ok "названо обидва числа" || bad "числа не названо"

# 3) Оголошене в документі не збігається з піном — падає.
printf 'селектор приймає 110 із 99 фізичних визначень pinned\n' > "$TMP/docs/native-system-roadmap.uk.md"
out=$(cd "$TMP" && bash scripts/check-doc-census.sh 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "розбіжність оголошеного валить гейт" || bad "не впало (rc=$rc)"

# 4) Обрізана копія піна — попередження, не збій (стан середовища, не дрейф).
printf 'селектор приймає 110 із 120 фізичних визначень pinned\n' > "$TMP/docs/native-system-roadmap.uk.md"
for i in $(seq 1 96); do echo "(визначити f$i (функція (x) x))"; done > "$TMP/external/sens/lib/core1.lisp"
out=$(cd "$TMP" && bash scripts/check-doc-census.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "обрізаний пін не валить гейт" || bad "обрізаний пін помилково валить: $out"
printf '%s' "$out" | grep -q 'DOC-CENSUS-УВАГА' && ok "попередження названо" || bad "попередження не названо"

# 5) У CI є ::error-анотація.
printf 'селектор приймає 104 із 120 фізичних визначень pinned\n' > "$TMP/docs/native-system-roadmap.uk.md"
for i in $(seq 1 120); do echo "(визначити f$i (функція (x) x))"; done > "$TMP/external/sens/lib/core1.lisp"
out=$(cd "$TMP" && GITHUB_ACTIONS=true bash scripts/check-doc-census.sh 2>&1)
printf '%s' "$out" | grep -q '::error title=census у документації::' && ok "є анотація для UI" || bad "немає анотації"

echo "DOCCENSUS-PASS checks=$CHECKS"
