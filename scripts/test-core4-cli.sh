#!/usr/bin/env bash
# Окремий механічний CLI-свідок Core4. Не виконує жодної форми SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null 2>&1 || {
  echo "CORE4-CLI-БЛОКЕР: немає FPC" >&2
  exit 127
}
./scripts/check-pin.sh
mkdir -p build/m0.2/core4-cli-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/core4-cli-units" \
  -FE"$ROOT/build/m0.2/bin" -osenscore4 "$ROOT/src/senscore4.lpr"
CLI="$ROOT/build/m0.2/bin/senscore4"
TMP=$(mktemp -d "$ROOT/build/m0.2/core4-cli.XXXXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/пошкоджений/external/sens/lib"
PATH_BAD="$TMP/пошкоджений/external/sens/lib/core4.lisp"

# Двічі читаємо справжнє pinned джерело; вивід і IR детерміновані.
"$CLI" --check "$ROOT" > "$TMP/перевірка-1"
"$CLI" --check "$ROOT" > "$TMP/перевірка-2"
cmp "$TMP/перевірка-1" "$TMP/перевірка-2"
grep -q 'CORE4-ДОПУСК-ГАРАЗД' "$TMP/перевірка-1"
grep -q 'виконання=ні' "$TMP/перевірка-1"
"$CLI" --emit-ir "$ROOT" "$TMP/перший.sir" > "$TMP/вивід-1"
"$CLI" --emit-ir "$ROOT" "$TMP/другий.sir" > "$TMP/вивід-2"
cmp "$TMP/перший.sir" "$TMP/другий.sir"
cmp "$TMP/вивід-1" "$TMP/вивід-2"
[[ "$(head -c 4 "$TMP/перший.sir")" == "SIR1" ]]
[[ $(wc -c < "$TMP/перший.sir") -gt 9 ]]

reject_case() {
  local case_name="$1"
  shift
  if "$@" > "$TMP/помилковий-stdout" 2> "$TMP/діагностика"; then
    echo "CORE4-CLI-ПРОВАЛ: допущено $case_name" >&2
    exit 1
  fi
  [[ ! -s "$TMP/помилковий-stdout" ]] || {
    echo "CORE4-CLI-ПРОВАЛ: stdout при помилці $case_name" >&2
    exit 1
  }
  grep -q 'CORE4-ДОПУСК-ПОМИЛКА' "$TMP/діагностика" || {
    echo "CORE4-CLI-ПРОВАЛ: немає діагностики $case_name" >&2
    exit 1
  }
}

reject_case 'невідома дія' "$CLI" --помилка "$ROOT"
reject_case 'відсутнє джерело' "$CLI" --check "$TMP/неіснуючий"
reject_case 'відсутній аргумент' "$CLI" --emit-ir "$ROOT"
reject_case 'невизначений вихід' "$CLI" --emit-ir "$ROOT" "$TMP/перший.sir"

printf 'незмінний файл\n' > "$TMP/захищений.sir"
cp "$TMP/захищений.sir" "$TMP/зразок"
printf '(незакритий' > "$PATH_BAD"
reject_case 'незакритий список' "$CLI" --emit-ir "$TMP/пошкоджений" "$TMP/новий.sir"
[[ ! -e "$TMP/новий.sir" && ! -e "$TMP/новий.sir.tmp" ]]
reject_case 'збереження попереднього' "$CLI" --emit-ir "$TMP/пошкоджений" "$TMP/захищений.sir"
cmp "$TMP/захищений.sir" "$TMP/зразок"
printf '(\300\257)' > "$PATH_BAD"
reject_case 'некоректний UTF-8' "$CLI" --emit-ir "$TMP/пошкоджений" "$TMP/новий.sir"
[[ ! -e "$TMP/новий.sir" ]]
: > "$PATH_BAD"
reject_case 'порожнє джерело' "$CLI" --check "$TMP/пошкоджений"
echo 'CORE4-CLI-ГАРАЗД pinned=так strict=так відмови=так IR=лише-структура виконання=ні'
