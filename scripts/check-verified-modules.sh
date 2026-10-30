#!/usr/bin/env bash
# G6.240 — КОЖЕН verified-модуль мусить мати свій тест.
#
# Навіщо: за сеанс додано 10 verified-профілів різними агентами. Правило
# «модуль + тест» ніде не перевірялося, тому наступний зріз міг додати
# lowering без жодної перевірки — і ніхто б не помітив.
#
# Перевіряємо саме відповідність імен: src/wsm.<X>.pas  ↔  scripts/test-<X>.sh,
# бо агрегатор test-verified-all.sh бере тести за маскою, і збій імені
# означає тест, якого ніхто не запускає.
#
# Винятки зафіксовані явно з причиною — не «щоб було зелено».
set -uo pipefail
cd "$(dirname "$0")/.."

# Модулі, чиї тести названі інакше ІСТОРИЧНО; їхні тести існують і бігають.
ALLOW="verifiedir verifiedwidecontext"

fail=0
checked=0
for mod in src/wsm.verified*.pas; do
  [ -e "$mod" ] || continue
  name=$(basename "$mod" .pas); name=${name#wsm.}
  checked=$((checked+1))
  case " $ALLOW " in
    *" $name "*)
      echo "VERIFIED-MODULES-ВИНЯТОК $name (історична назва тесту)"
      continue ;;
  esac
  test_sh="scripts/test-${name}.sh"
  if [ ! -f "$test_sh" ]; then
    echo "VERIFIED-MODULES-FAIL немає тесту для $mod: очікували $test_sh" >&2
    fail=1
    continue
  fi
  # Тест мусить справді згадувати свій модуль, інакше він перевіряє щось інше.
  if ! grep -q "$name" "$test_sh"; then
    echo "VERIFIED-MODULES-FAIL $test_sh не згадує модуль $name" >&2
    fail=1
    continue
  fi
  echo "VERIFIED-MODULES-OK   $name ↔ $test_sh"
done

if [ "$fail" -ne 0 ]; then
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error title=verified-модулі::модуль без тесту або тест без модуля — див. список вище" >&2
  fi
  exit 1
fi
echo "VERIFIED-MODULES-PASS перевірено=$checked"
