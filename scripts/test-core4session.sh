#!/usr/bin/env bash
# G5.16: перевірка FPC і реального постійного сеансу вузького pinned Core4.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'CORE4-СЕАНС-БЛОКЕР: немає FPC' >&2; exit 127; }
./scripts/check-pin.sh
mkdir -p build/m0.2/core4-session-units build/m0.2/bin
for SOURCE in test-core4session sensseanscore4; do
  case "$SOURCE" in
    test-core4session) FILE="$ROOT/scripts/test-core4session.pas" ;;
    sensseanscore4) FILE="$ROOT/src/sensseanscore4.lpr" ;;
  esac
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
    -FU"$ROOT/build/m0.2/core4-session-units" -FE"$ROOT/build/m0.2/bin" \
    -o"$SOURCE" "$FILE"
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$ROOT/build/m0.2/bin/test-core4session" "$ROOT" "$TMP"
BIN="$ROOT/build/m0.2/bin/sensseanscore4"
{
  printf '%s\n' "$TMP/01-tak.sens" "$TMP/02-nevidome.sens" \
    "$TMP/03-ni.sens" "$TMP/04-d24-argument.sens" \
    "$TMP/05-global-d24-0.sens" "$TMP/06-poshkodzhenyi.sens" \
    "$TMP/07-global-d24-1.sens" "$TMP/08-vidsutnii.sens" \
    "$TMP/09-povtornyi.sens" ':вихід'
} > "$TMP/session.in"
set +e
"$BIN" --сеанс "$ROOT" < "$TMP/session.in" > "$TMP/out" 2> "$TMP/err"
RC=$?
set -e
test "$RC" -eq 2 || { echo "очікувався код 2 за трьох відмов; отримано $RC" >&2; exit 1; }
cat > "$TMP/expected" <<'EOF'
РЕЗУЛЬТАТ 1 1:1
РЕЗУЛЬТАТ 3 1:0
РЕЗУЛЬТАТ 4 24:000000000000000000000001
РЕЗУЛЬТАТ 5 24:000000000000000000000000
РЕЗУЛЬТАТ 7 24:000000000000000000000001
РЕЗУЛЬТАТ 9 1:1
EOF
diff -u "$TMP/expected" "$TMP/out"
test "$(grep -c '^ПОМИЛКА ' "$TMP/err")" -eq 3
grep -q '^ПОМИЛКА 2 ' "$TMP/err"
grep -q '^ПОМИЛКА 6 ' "$TMP/err"
grep -q '^ПОМИЛКА 8 ' "$TMP/err"
! grep -q '^РЕЗУЛЬТАТ 2 ' "$TMP/out"
! grep -q '^РЕЗУЛЬТАТ 6 ' "$TMP/out"
! grep -q '^РЕЗУЛЬТАТ 8 ' "$TMP/out"
{
  printf '%s\n' "$TMP/01-tak.sens" ':вихід' "$TMP/03-ni.sens"
} > "$TMP/early-exit.in"
"$BIN" --сеанс "$ROOT" < "$TMP/early-exit.in" > "$TMP/early-exit.out" 2> "$TMP/early-exit.err"
printf 'РЕЗУЛЬТАТ 1 1:1\n' > "$TMP/early-exit.expected"
diff -u "$TMP/early-exit.expected" "$TMP/early-exit.out"
test ! -s "$TMP/early-exit.err"
set +e
"$BIN" --невідомо "$ROOT" > "$TMP/invalid.out" 2> "$TMP/invalid.err"
INVALID_RC=$?
"$BIN" --сеанс "$TMP/non-existent-authority" < /dev/null > "$TMP/no-root.out" 2> "$TMP/no-root.err"
ROOT_RC=$?
set -e
test "$INVALID_RC" -eq 64
test "$ROOT_RC" -eq 2
test ! -s "$TMP/invalid.out"
test ! -s "$TMP/no-root.out"
echo 'CORE4-СЕАНС-ГАРАЗД успішних=6 негативних=5 відновлення=так середовище=один-процес'
