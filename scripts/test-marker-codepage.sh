#!/usr/bin/env bash
# G6.251 — самоперевірка гейта «кириличний маркер потребує codepage utf8».
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CHECKS=0
ok()  { CHECKS=$((CHECKS+1)); echo "MCODEPAGE-OK   $*"; }
bad() { echo "MCODEPAGE-ЗБІЙ $*" >&2; exit 1; }

mkdir -p "$TMP/scripts" "$TMP/src"
cp "$ROOT/scripts/check-marker-codepage.sh" "$TMP/scripts/"

# 1) Кириличний маркер БЕЗ директиви — падає (саме випадок PR #1032).
cat > "$TMP/scripts/test-a.pas" <<'PAS'
program t;
begin
  WriteLn('G6.249-SHLD-ГОТОВО-PASS matrix=64');
end.
PAS
out=$(cd "$TMP" && bash scripts/check-marker-codepage.sh 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "без директиви валить гейт" || bad "не впало (rc=$rc)"
printf '%s' "$out" | grep -q 'MARKER-CODEPAGE-FAIL scripts/test-a.pas' && ok "названо файл" || bad "файл не названо"
printf '%s' "$out" | grep -q 'codepage utf8' && ok "названо виправлення" || bad "виправлення не названо"

# 2) З директивою — проходить.
cat > "$TMP/scripts/test-a.pas" <<'PAS'
program t;
{$codepage utf8}
begin
  WriteLn('G6.249-SHLD-ГОТОВО-PASS matrix=64');
end.
PAS
out=$(cd "$TMP" && bash scripts/check-marker-codepage.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "з директивою проходить" || bad "впало з директивою: $out"

# 3) Кирилиця в поясненні для людини (без PASS/FAIL) — НЕ валить.
cat > "$TMP/scripts/test-b.pas" <<'PAS'
program t;
begin
  WriteLn('просто пояснення українською');
end.
PAS
out=$(cd "$TMP" && bash scripts/check-marker-codepage.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "пояснення без маркера не заважає" || bad "пояснення помилково заважає: $out"

# 4) ASCII-маркер — проходить без директиви.
cat > "$TMP/scripts/test-c.pas" <<'PAS'
program t;
begin
  WriteLn('SHLD-PASS matrix=64');
end.
PAS
out=$(cd "$TMP" && bash scripts/check-marker-codepage.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "ASCII-маркер не вимагає директиви" || bad "ASCII помилково заважає: $out"

# 5) У CI є ::error-анотація.
cat > "$TMP/scripts/test-a.pas" <<'PAS'
program t;
begin
  WriteLn('G6.249-SHLD-ГОТОВО-PASS matrix=64');
end.
PAS
out=$(cd "$TMP" && GITHUB_ACTIONS=true bash scripts/check-marker-codepage.sh 2>&1)
printf '%s' "$out" | grep -q '::error title=маркери::' && ok "є анотація для UI" || bad "немає анотації"

# 6) Гейт ЧЕСНО описує власну межу: директива — необхідна, не достатня.
grep -q 'НЕ ДОСТАТНЯ умова' "$ROOT/scripts/check-marker-codepage.sh" \
  && ok "шапка гейта визнає межу (необхідна, не достатня)" \
  || bad "шапка гейта не описує межу — легко переоцінити захист"

echo "MCODEPAGE-PASS checks=$CHECKS"
