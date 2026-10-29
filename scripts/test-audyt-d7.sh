#!/usr/bin/env bash
# G2.31 — реальний FPC і негативні підміни pinned каталогу D7.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null
command -v timeout >/dev/null
mkdir -p build/m0.2/d7audit/bin build/m0.2/d7audit/units
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/d7audit/units" \
  -FE"$ROOT/build/m0.2/d7audit/bin" -osensaudytd7 \
  src/sensaudytd7.lpr
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/d7audit/units" \
  -FE"$ROOT/build/m0.2/d7audit/bin" -otest-audyt-d7 \
  scripts/test-audyt-d7.pas
BIN="$ROOT/build/m0.2/d7audit/bin/sensaudytd7"
TEST="$ROOT/build/m0.2/d7audit/bin/test-audyt-d7"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 45s "$TEST" "$ROOT/external/sens" > "$TMP/mechanical"
cat "$TMP/mechanical"
grep -F 'Д7-АУДИТ-МЕХАНІКА-ГАРАЗД 128/95/33' "$TMP/mechanical" >/dev/null
timeout 45s "$BIN" "$ROOT/external/sens" > "$TMP/first"
timeout 45s "$BIN" "$ROOT/external/sens" > "$TMP/second"
cat "$TMP/first"
cmp "$TMP/first" "$TMP/second"
grep -Fx 'Д7-КАНОН-ГАРАЗД координат=128 друкованих=95 керувальних=33' "$TMP/first" >/dev/null
grep -Fx 'LISP: знаків=0 міждоменних-омонімів=0' "$TMP/first" >/dev/null
grep -Fx 'D7 LISP: 128 порожніх проєкцій; викличність не визначено' "$TMP/first" >/dev/null
test "$(grep -Ec ': знаків=95 міждоменних-омонімів=[0-9]+$' "$TMP/first")" -eq 5
for surface in ук укр san en sym; do
  grep -E "^$surface: знаків=95 міждоменних-омонімів=[0-9]+$" "$TMP/first" >/dev/null
done
for mode in no-root extra-argument; do
  if [[ "$mode" == no-root ]]; then
    timeout 45s "$BIN" "$TMP/відсутній" > "$TMP/badout" 2> "$TMP/baderr" && {
      echo 'Неправильний каталог допущено' >&2; exit 1;
    }
  else
    timeout 45s "$BIN" "$ROOT/external/sens" зайве > "$TMP/badout" 2> "$TMP/baderr" && {
      echo 'Зайвий аргумент допущено' >&2; exit 1;
    }
  fi
  test ! -s "$TMP/badout"
  grep -F 'АУДИТ-Д7-ПОМИЛКА:' "$TMP/baderr" >/dev/null
done
echo 'Д7-АУДИТ-CI-ГАРАЗД FPC=справжній координати=128 проєкцій=шість негативи=8'
