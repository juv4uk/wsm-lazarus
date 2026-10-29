#!/usr/bin/env bash
# Живий прогін оракула SENS на Pascal: зібрати й подати справжні форми.
#
# Навіщо: компіляція — не виконання. Цей скрипт перевіряє, що оракул
# ВІДПОВІДАЄ, а не лише збирається. Без Rust і без Zig.
#
# Шаблон збірки взятий із scripts/test-sens-uk-d3.sh — той самий FPC,
# ті самі прапорці, той самий корінь.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh -Fu"$ROOT/src" \
  -FU"$TMP/units" -FE"$TMP/bin" -osens-oracle "$ROOT/src/sens_oracle.lpr"
BIN="$TMP/bin/sens-oracle"
test -x "$BIN"

CHECKS=0

# Позитивний: оракул мусить відповісти OK і надрукувати READY першим рядком.
pereviryty_ok() {
  local nazva="$1" vhid="$2"
  CHECKS=$((CHECKS + 1))
  printf '%s\n' "$vhid" > "$TMP/in"
  if ! timeout 45s "$BIN" < "$TMP/in" > "$TMP/out" 2> "$TMP/err"; then
    echo "ПОМИЛКА-ТЕСТУ: $nazva — виконання впало" >&2
    cat "$TMP/err" >&2
    exit 1
  fi
  if ! head -1 "$TMP/out" | grep -qx 'READY'; then
    echo "ПОМИЛКА-ТЕСТУ: $nazva — немає READY першим рядком" >&2
    cat "$TMP/out" >&2
    exit 1
  fi
  if ! grep -q '^OK' "$TMP/out"; then
    echo "ПОМИЛКА-ТЕСТУ: $nazva — немає OK у відповіді" >&2
    cat "$TMP/out" >&2
    exit 1
  fi
  echo "  ok  $nazva"
}

# Негативний: оракул мусить відмовити з ERR і кодом 2.
pereviryty_vidmovu() {
  local nazva="$1" vhid="$2"
  CHECKS=$((CHECKS + 1))
  printf '%s\n' "$vhid" > "$TMP/in"
  set +e
  timeout 45s "$BIN" < "$TMP/in" > "$TMP/out" 2> "$TMP/err"
  local kod=$?
  set -e
  if [ "$kod" -ne 2 ]; then
    echo "ПОМИЛКА-ТЕСТУ: $nazva — код $kod, очікувано 2" >&2
    cat "$TMP/out" >&2
    exit 1
  fi
  if ! grep -q '^ERR' "$TMP/out"; then
    echo "ПОМИЛКА-ТЕСТУ: $nazva — немає ERR у відповіді" >&2
    cat "$TMP/out" >&2
    exit 1
  fi
  echo "  ok  $nazva (відмова)"
}

# Форми з чинної укр-проєкції; кожна мусить виконатися наявним D3.
pereviryty_ok 'сполучити-так-порожнє' '(сполучити так ())'
pereviryty_ok 'перше-списку'          '(перше (сполучити так ()))'
pereviryty_ok 'решта-списку'          '(решта (сполучити так ()))'
pereviryty_ok 'цитата'                '(як-є так)'
pereviryty_ok 'умова-істинна'         '(за-умовою ((так ні) (так так)))'

# Негативний: селектор на не-парі. Це відмова за кодом:
#   'native selector requires nonempty pair' (wsm.nativeeval).
# Порожній () НЕ є негативом: за законом він повертає D3:000, а не помилку.
pereviryty_vidmovu 'перше-на-не-парі' '(перше так)'

echo "ОРАКУЛ_ВІДПОВІВ перевірок=$CHECKS native=Pascal bez=Rust,Zig"
