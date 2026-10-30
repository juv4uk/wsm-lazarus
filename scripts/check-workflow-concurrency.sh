#!/usr/bin/env bash
# G6.241 — pull_request-workflow з FPC мусить скасовувати застарілі прогони.
#
# Навіщо: 30.10 CI стояв у черзі десятками хвилин, бо кожен новий push того
# самого PR ставав у чергу за попереднім замість скасування. Власник прямо
# вимагає не витрачати енергію на зайве — а паралельні прогони того самого
# PR і є зайве.
#
# Перевіряємо лише ті workflow, що (а) ставлять fp-compiler і (б) мають
# pull_request-тригер: саме вони множаться на кожен push. Нічні schedule-
# прогони НЕ скасовуємо — там скасування зламало б сенс.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
checked=0
for f in .github/workflows/*.yml; do
  [ -e "$f" ] || continue
  grep -q 'fp-compiler' "$f" || continue
  # тригер pull_request у блоці on:
  awk '/^on:[[:space:]]*$/{inon=1;next} inon && /^[^[:space:]#]/{inon=0} inon && /^  pull_request:/{found=1} END{exit(found?0:1)}' "$f" || continue
  checked=$((checked+1))
  if ! grep -q '^concurrency:' "$f"; then
    echo "WORKFLOW-CONCURRENCY-FAIL $f: pull_request-прогін без concurrency — застарілі прогони не скасовуються" >&2
    fail=1
    continue
  fi
  if ! grep -q 'cancel-in-progress' "$f"; then
    echo "WORKFLOW-CONCURRENCY-FAIL $f: є concurrency, але без cancel-in-progress" >&2
    fail=1
    continue
  fi
  echo "WORKFLOW-CONCURRENCY-OK   $f"
done

if [ "$fail" -ne 0 ]; then
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error title=CI-черга::pull_request-workflow без cancel-in-progress множить чергу; додайте блок concurrency" >&2
  fi
  exit 1
fi
echo "WORKFLOW-CONCURRENCY-PASS перевірено=$checked"
