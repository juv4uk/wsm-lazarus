#!/usr/bin/env bash
# G6.256 — самоперевірка діагностики середовища (без fpc, без мережі).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CHECKS=0
ok()  { CHECKS=$((CHECKS+1)); echo "TOOLCHAIN-OK   $*"; }
bad() { echo "TOOLCHAIN-ЗБІЙ $*" >&2; exit 1; }

# 1) Скрипт існує, виконуваний, і в цьому середовищі дає ГОТОВО або НЕГОТОВО
#    (обидва — коректні відповіді; головне, що він не падає мовчки).
[ -x "$ROOT/scripts/check-local-toolchain.sh" ] && ok "скрипт виконуваний" || bad "немає біта виконання"

out=$(cd "$ROOT" && bash scripts/check-local-toolchain.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] && ok "код 0 або 2, не інший (rc=$rc)" || bad "несподіваний код $rc"
printf '%s' "$out" | grep -qE 'LOCAL-TOOLCHAIN-(ГОТОВО|НЕГОТОВО)' && ok "вердикт названо" || bad "немає вердикту"

# 2) НЕГОТОВО мусить перелічувати, чого бракує — інакше діагностика марна.
if printf '%s' "$out" | grep -q 'LOCAL-TOOLCHAIN-НЕГОТОВО'; then
  printf '%s' "$out" | grep -q 'бракує:.' && ok "перелічено, чого бракує" || bad "НЕГОТОВО без переліку"
else
  ok "середовище готове — перелік не потрібен"
fi

# 3) Скрипт не змінює репозиторій (жодного git-стану після прогону).
before=$(cd "$ROOT" && git status --porcelain | sort)
(cd "$ROOT" && bash scripts/check-local-toolchain.sh >/dev/null 2>&1) || true
after=$(cd "$ROOT" && git status --porcelain | sort)
[ "$before" = "$after" ] && ok "репозиторій не змінюється" || bad "скрипт лишив зміни в дереві"

echo "TOOLCHAIN-PASS checks=$CHECKS"
