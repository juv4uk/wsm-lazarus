#!/usr/bin/env bash
# G6.5: реальний FPC, приватний EIR1 + негативні сценарії CLI.
# Вхід у всіх перевірках — ТІЛЬКИ фізичний T5M .sens.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'ТОЧНЕ-EIR1-БЛОК: відсутній компілятор Free Pascal' >&2
  exit 127
}
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
mkdir -p build/m0.2/eir1-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/eir1-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-exactir-wire "$ROOT/scripts/test-exactir-wire.pas"
"$ROOT/build/m0.2/bin/test-exactir-wire"

"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/eir1-units" -FE"$ROOT/build/m0.2/bin" \
  -osensexact "$ROOT/src/sensexact.lpr"
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/eir1-units" -FE"$ROOT/build/m0.2/bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"

TMP=$(mktemp -d "$ROOT/build/m0.2/eir1.XXXXXXXX")
trap 'rm -rf "$TMP"' EXIT
printf '10 111 00 0 000 01\n' > "$TMP/точні.words"
"$ROOT/build/m0.2/bin/senst5m" --пакувати-слова "$TMP/точні.words" \
  > "$TMP/зразок.sens"
"$ROOT/build/m0.2/bin/senst5m" --перевірити-структуру \
  "$TMP/зразок.sens" >/dev/null

"$ROOT/build/m0.2/bin/sensexact" --створити-ір \
  "$TMP/зразок.sens" "$TMP/перший.eir" > "$TMP/створено"
"$ROOT/build/m0.2/bin/sensexact" --створити-ір \
  "$TMP/зразок.sens" "$TMP/другий.eir" > "$TMP/повтор"
cmp "$TMP/перший.eir" "$TMP/другий.eir"
grep -q 'ТОЧНЕ-EIR1-СТВОРЕНО вузлів=4 коренів=1' "$TMP/створено"
"$ROOT/build/m0.2/bin/sensexact" --перевірити-ір \
  "$TMP/зразок.sens" "$TMP/перший.eir" > "$TMP/перевірено"
grep -q 'ТОЧНЕ-EIR1-ПЕРЕВІРЕНО вузлів=4' "$TMP/перевірено"
grep -q 'виконання=ні' "$TMP/перевірено"

reject() {
  local label=$1
  shift
  if "$@" >"$TMP/неприпустимий-вихід" 2>"$TMP/діагностика"; then
    echo "ТОЧНЕ-EIR1-ПРОВАЛ: прийнято $label" >&2
    exit 1
  fi
  [[ ! -s "$TMP/неприпустимий-вихід" ]] || {
    echo "ТОЧНЕ-EIR1-ПРОВАЛ: частковий stdout у $label" >&2
    exit 1
  }
  grep -q 'ТОЧНЕ-EIR1-ВІДХИЛЕНО' "$TMP/діагностика" || {
    echo "ТОЧНЕ-EIR1-ПРОВАЛ: відсутня діагностика $label" >&2
    cat "$TMP/діагностика" >&2
    exit 1
  }
}

# Не допускаємо непомітного перезапису чинного свідчення.
cp "$TMP/перший.eir" "$TMP/захищена-копія"
reject 'наявний вихідний файл' \
  "$ROOT/build/m0.2/bin/sensexact" --створити-ір \
  "$TMP/зразок.sens" "$TMP/перший.eir"
cmp "$TMP/перший.eir" "$TMP/захищена-копія"

printf '\377' > "$TMP/пошкоджений.sens"
reject 'пошкоджений фізичний файл' \
  "$ROOT/build/m0.2/bin/sensexact" --створити-ір \
  "$TMP/пошкоджений.sens" "$TMP/не-існує.eir"
[[ ! -e "$TMP/не-існує.eir" ]] || {
  echo 'ТОЧНЕ-EIR1-ПРОВАЛ: створено partial-output після помилки T5M' >&2
  exit 1
}
printf '10 111 00 1 000 01\n' > "$TMP/інший.words"
"$ROOT/build/m0.2/bin/senst5m" --пакувати-слова "$TMP/інший.words" \
  > "$TMP/інший.sens"
reject 'сторонній фізичний канон' \
  "$ROOT/build/m0.2/bin/sensexact" --перевірити-ір \
  "$TMP/інший.sens" "$TMP/перший.eir"

cp "$TMP/перший.eir" "$TMP/зіпсований.eir"
printf '\000' | dd of="$TMP/зіпсований.eir" bs=1 seek=0 conv=notrunc status=none
reject 'неправильне magic' \
  "$ROOT/build/m0.2/bin/sensexact" --перевірити-ір \
  "$TMP/зразок.sens" "$TMP/зіпсований.eir"
reject 'неіснуючий файл' \
  "$ROOT/build/m0.2/bin/sensexact" --перевірити-ір \
  "$TMP/зразок.sens" "$TMP/відсутній.eir"
reject 'текстова проєкція замість фізичного файлу' \
  "$ROOT/build/m0.2/bin/sensexact" --створити-ір \
  "$TMP/точні.words" "$TMP/ніякий.eir"

echo 'ТОЧНЕ-EIR1-CLI-ГАРАЗД фізичний-T5M=так приватний-IR=так'
echo 'ТОЧНЕ-EIR1-CLI-МЕЖІ семантика=ні викличність=ні Core4=ні'
