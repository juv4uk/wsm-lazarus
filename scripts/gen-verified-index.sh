#!/usr/bin/env bash
# G6.250 — ІНДЕКС verified-профілів, згенерований із репозиторію.
#
# Навіщо: за сеанс з'явилося 10 verified-модулів від різних агентів. Щоб
# побачити, що саме вже перевірено і чим, доводилося читати ls і шукати
# відповідники руками. Індекс генерується, тому не може розійтися з кодом.
#
# Це індекс РЕАЛІЗАЦІЙ, не реєстр мовних законів: жодного правила SENS тут
# не оголошується, лише перелік наявних механізмів і їхніх тестів.
set -uo pipefail
cd "$(dirname "$0")/.."

OUT=${1:-docs/verified-profiles.uk.md}

{
  echo '# Перевірені профілі: індекс'
  echo
  echo 'Згенеровано `scripts/gen-verified-index.sh` — не редагувати руками.'
  echo 'Кожен рядок — наявний модуль і його тест; відповідність перевіряє'
  echo '`scripts/check-verified-modules.sh`.'
  echo
  echo '| модуль | тест |'
  echo '|---|---|'
  for mod in src/wsm.verified*.pas; do
    [ -e "$mod" ] || continue
    name=$(basename "$mod" .pas); name=${name#wsm.}
    test_sh="scripts/test-${name}.sh"
    if [ -f "$test_sh" ]; then
      echo "| \`$mod\` | \`$test_sh\` |"
    else
      echo "| \`$mod\` | — (історична назва тесту) |"
    fi
  done
  echo
  echo '## Агрегатори'
  echo
  echo '- `scripts/test-verified-all.sh` — усі `test-verified*.sh` одним кроком у PR-прогоні.'
  echo '- `scripts/check-verified-modules.sh` — модуль мусить мати свій тест.'
} > "$OUT"

echo "VERIFIED-INDEX-ЗГЕНЕРОВАНО $OUT рядків=$(wc -l < "$OUT" | tr -d ' ')"
