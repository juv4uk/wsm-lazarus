#!/usr/bin/env bash
# G6.229 — гейт бюджету мусить НАЗИВАТИ причину в UI, а не лише падати.
#
# Навіщо: три PR цього сеансу були червоні з причини 'FPC-BUDGET-FAIL на push
# понад бюджет', але в GitHub API видно лише conclusion=failure з порожнім
# output — тому довелося вивантажувати логи кроку, щоб дізнатися одне слово.
# Тепер гейт друкує ::error title=...:: і пише зведення в GITHUB_STEP_SUMMARY.
#
# Перевіряємо у тимчасовому дереві, щоб не чіпати справжні workflow.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

CHECKS=0
ok()   { CHECKS=$((CHECKS+1)); echo "BUDGET-ANNOT-OK   $*"; }
bad()  { echo "BUDGET-ANNOT-ЗБІЙ $*" >&2; exit 1; }

mkdir -p "$TMP/.github/workflows" "$TMP/scripts"
cp "$ROOT/scripts/check-workflow-fpc-budget.sh" "$TMP/scripts/"

# 1) Чисте дерево: один дозволений push-workflow — гейт проходить.
cat > "$TMP/.github/workflows/core1-repl.yml" <<'YML'
name: core1-repl
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-24.04
    steps:
      - run: sudo apt-get install -y fp-compiler
YML
out=$(cd "$TMP" && bash scripts/check-workflow-fpc-budget.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "чисте дерево: гейт проходить" || bad "чисте дерево впало: $out"

# 2) Зайвий push-workflow — гейт падає І називає файл.
cat > "$TMP/.github/workflows/zai-vyi.yml" <<'YML'
name: зайвий
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-24.04
    steps:
      - run: sudo apt-get install -y fp-compiler
YML
out=$(cd "$TMP" && bash scripts/check-workflow-fpc-budget.sh 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "зайвий push: гейт падає" || bad "гейт не впав (rc=$rc)"
printf '%s' "$out" | grep -q 'FPC-BUDGET-FAIL на push' && ok "названо клас збою" || bad "немає рядка FPC-BUDGET-FAIL на push"
printf '%s' "$out" | grep -q 'zai-vyi.yml' && ok "названо конкретний файл" || bad "файл не названо"

# 3) Анотація для UI: ::error title=...:: з переліком файлів.
printf '%s' "$out" | grep -q '::error title=FPC-бюджет::' && ok "є ::error-анотація для UI" || bad "немає ::error-анотації"
printf '%s' "$out" | grep -q 'workflow_dispatch' && ok "анотація містить підказку виправлення" || bad "анотація без підказки"

# 4) Зведення для GITHUB_STEP_SUMMARY.
SUM="$TMP/summary.md"
(cd "$TMP" && GITHUB_STEP_SUMMARY="$SUM" bash scripts/check-workflow-fpc-budget.sh >/dev/null 2>&1 || true)
[ -s "$SUM" ] && ok "записано GITHUB_STEP_SUMMARY" || bad "GITHUB_STEP_SUMMARY порожній"
grep -q 'FPC-бюджет перевищено' "$SUM" && ok "зведення містить заголовок" || bad "зведення без заголовка"
grep -q 'zai-vyi.yml' "$SUM" && ok "зведення називає файл" || bad "зведення без файлу"

echo "BUDGET-ANNOT-PASS checks=$CHECKS"
