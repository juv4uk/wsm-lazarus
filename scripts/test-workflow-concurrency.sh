#!/usr/bin/env bash
# G6.241 — самоперевірка гейта «PR-workflow скасовує застарілі прогони».
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CHECKS=0
ok()  { CHECKS=$((CHECKS+1)); echo "WCONC-OK   $*"; }
bad() { echo "WCONC-ЗБІЙ $*" >&2; exit 1; }

mkdir -p "$TMP/.github/workflows" "$TMP/scripts"
cp "$ROOT/scripts/check-workflow-concurrency.sh" "$TMP/scripts/"

# 1) PR-прогін з concurrency — проходить.
cat > "$TMP/.github/workflows/a.yml" <<'YML'
name: a
on:
  pull_request:
    paths: ['x']
concurrency:
  group: a-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: sudo apt-get install -y fp-compiler
YML
out=$(cd "$TMP" && bash scripts/check-workflow-concurrency.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "PR-прогін з concurrency проходить" || bad "впало: $out"

# 2) PR-прогін без concurrency — падає.
cat > "$TMP/.github/workflows/b.yml" <<'YML'
name: b
on:
  pull_request:
    paths: ['y']
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: sudo apt-get install -y fp-compiler
YML
out=$(cd "$TMP" && bash scripts/check-workflow-concurrency.sh 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "PR-прогін без concurrency валить гейт" || bad "не впало (rc=$rc)"
printf '%s' "$out" | grep -q 'b.yml: pull_request-прогін без concurrency' && ok "названо файл і причину" || bad "файл не названо"

# 3) concurrency без cancel-in-progress — падає.
cat > "$TMP/.github/workflows/b.yml" <<'YML'
name: b
on:
  pull_request:
    paths: ['y']
concurrency:
  group: b
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: sudo apt-get install -y fp-compiler
YML
out=$(cd "$TMP" && bash scripts/check-workflow-concurrency.sh 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "без cancel-in-progress валить гейт" || bad "не впало (rc=$rc)"
printf '%s' "$out" | grep -q 'без cancel-in-progress' && ok "названо причину" || bad "причину не названо"

# 4) Нічний schedule-прогін без concurrency — НЕ валить (скасування там шкідливе).
rm -f "$TMP/.github/workflows/b.yml"
cat > "$TMP/.github/workflows/c.yml" <<'YML'
name: c
on:
  schedule:
    - cron: '0 3 * * *'
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: sudo apt-get install -y fp-compiler
YML
out=$(cd "$TMP" && bash scripts/check-workflow-concurrency.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "нічний schedule не вимагає concurrency" || bad "нічний прогін помилково заважає: $out"

# 5) У CI є ::error-анотація.
cat > "$TMP/.github/workflows/b.yml" <<'YML'
name: b
on:
  pull_request:
    paths: ['y']
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: sudo apt-get install -y fp-compiler
YML
out=$(cd "$TMP" && GITHUB_ACTIONS=true bash scripts/check-workflow-concurrency.sh 2>&1)
printf '%s' "$out" | grep -q '::error title=CI-черга::' && ok "є анотація для UI" || bad "немає анотації"

echo "WCONC-PASS checks=$CHECKS"
