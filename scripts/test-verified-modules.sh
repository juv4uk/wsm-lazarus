#!/usr/bin/env bash
# G6.240 — самоперевірка гейта «модуль ↔ тест» на синтетичному дереві.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CHECKS=0
ok()  { CHECKS=$((CHECKS+1)); echo "VMOD-OK   $*"; }
bad() { echo "VMOD-ЗБІЙ $*" >&2; exit 1; }

mkdir -p "$TMP/src" "$TMP/scripts"
cp "$ROOT/scripts/check-verified-modules.sh" "$TMP/scripts/"

# 1) Модуль із тестом — проходить.
: > "$TMP/src/wsm.verifiedalpha.pas"
printf '#!/usr/bin/env bash\necho verifiedalpha\n' > "$TMP/scripts/test-verifiedalpha.sh"
out=$(cd "$TMP" && bash scripts/check-verified-modules.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "модуль із тестом проходить" || bad "впало на коректному дереві: $out"

# 2) Модуль без тесту — падає і називає очікуваний файл.
: > "$TMP/src/wsm.verifiedbeta.pas"
out=$(cd "$TMP" && bash scripts/check-verified-modules.sh 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "модуль без тесту валить гейт" || bad "не впало (rc=$rc)"
printf '%s' "$out" | grep -q 'немає тесту для src/wsm.verifiedbeta.pas' && ok "названо модуль" || bad "модуль не названо"
printf '%s' "$out" | grep -q 'scripts/test-verifiedbeta.sh' && ok "названо очікуваний тест" || bad "очікуваний тест не названо"

# 3) Тест існує, але не згадує модуль — падає.
printf '#!/usr/bin/env bash\necho щось інше\n' > "$TMP/scripts/test-verifiedbeta.sh"
out=$(cd "$TMP" && bash scripts/check-verified-modules.sh 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "тест без згадки модуля валить гейт" || bad "не впало (rc=$rc)"
printf '%s' "$out" | grep -q 'не згадує модуль verifiedbeta' && ok "названо причину" || bad "причину не названо"

# 4) У CI є ::error-анотація.
out=$(cd "$TMP" && GITHUB_ACTIONS=true bash scripts/check-verified-modules.sh 2>&1)
printf '%s' "$out" | grep -q '::error title=verified-модулі::' && ok "є анотація для UI" || bad "немає анотації"

echo "VMOD-PASS checks=$CHECKS"
