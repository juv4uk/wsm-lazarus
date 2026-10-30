#!/usr/bin/env bash
# G6.233 — регресійна перевірка походження компілятора, не оракул мови.
# Закони фізичних .sens належать pinned SENS. Перевіряємо лише Git та
# декларації документації; жодної іншої мови чи семантичного dispatch.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
fail() { printf 'ПІН-ДОКИ-ПРОВАЛ: %s\n' "$*" >&2; exit 1; }
for tool in git sed grep sort; do
  command -v "$tool" >/dev/null || fail "немає утиліти $tool"
done

entry=$(git ls-tree HEAD external/sens) || fail "не вдається прочитати gitlink у HEAD"
read -r mode kind pin path <<< "$entry"
[[ "$mode" == 160000 && "$kind" == commit && "$path" == external/sens &&
   "$pin" =~ ^[0-9a-f]{40}$ ]] || fail 'немає точного gitlink external/sens у HEAD'

baseline=$(sed -nE 's/^MY_LISP_PIN=([0-9a-f]{40})$/\1/p' refs/tier1-baseline.properties)
[[ "$baseline" == "$pin" ]] ||
  fail 'pin у refs/tier1-baseline.properties не збігається з gitlink'

checked=0
for doc in AGENTS.md README.md docs/native-system-roadmap.uk.md; do
  [[ -f "$doc" ]] || fail "відсутній документ $doc"
  # Рахуємо тільки SHA на рядках явного gitlink. Історичні SHA
  # комітів з таблиць прогресу не повинні ставати мовним авторитетом.
  declared=$( { grep -E 'gitlink' "$doc" || true; } |
    { grep -Eo '[0-9a-f]{40}' || true; } | sort -u)
  [[ "$declared" == "$pin" ]] ||
    fail "неузгоджений gitlink у $doc: ${declared:-<немає>}"
  checked=$((checked+1))
done
printf 'ПІН-ДОКИ-ГАРАЗД gitlink=%s документи=%d базовий-пін=так\n' "$pin" "$checked"
