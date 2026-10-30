#!/usr/bin/env bash
# Core1.3 — справжній нативний пошук pinned фізичних DEFINE за exact D7.
# Тут нема семантичного оракула: перевіряється механічна індексація.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
for exe in fpc timeout cmp grep mktemp cp sed; do
  command -v "$exe" >/dev/null || { echo "CORE1-ІНДЕКС-БЛОК: немає $exe" >&2; exit 127; }
done
mkdir -p build/m0.2/core1-index-units build/m0.2/core1-index-bin
FPC_BIN=${FPC:-fpc}
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/core1-index-units" \
  -FE"$ROOT/build/m0.2/core1-index-bin" \
  -osenscore1indeks "$ROOT/src/senscore1indeks.lpr"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/core1-index-units" \
  -FE"$ROOT/build/m0.2/core1-index-bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"
CLI="$ROOT/build/m0.2/core1-index-bin/senscore1indeks"
PACK="$ROOT/build/m0.2/core1-index-bin/senst5m"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$CLI" --опис "$ROOT" >"$TMP/опис" 2>"$TMP/опис.err"
grep -Fxq 'CORE1-ІНДЕКС-ГАРАЗД визначень=129 унікальних=129 перше-слово=1 пошук=D7 виконання=ні' "$TMP/опис"
test ! -s "$TMP/опис.err"

# Фізичні форми беруться НЕ із .lisp, а з реального pinned Core1.
for i in 1 129; do
  "$CLI" --форма "$ROOT" "$i" >"$TMP/форма-$i.sens"
  "$CLI" --ключ "$ROOT" "$i" >"$TMP/ключ-$i.sens"
  "$CLI" --знайти "$ROOT" "$TMP/ключ-$i.sens" >"$TMP/знайдено-$i.sens"
  cmp "$TMP/форма-$i.sens" "$TMP/знайдено-$i.sens"
  "$PACK" --перегляд "$TMP/форма-$i.sens" >"$TMP/форма-$i.words"
  "$PACK" --пакувати-слова "$TMP/форма-$i.words" >"$TMP/повтор-$i.sens"
  cmp "$TMP/форма-$i.sens" "$TMP/повтор-$i.sens"
  grep -Eq '^10 0011 ' "$TMP/форма-$i.words"
  "$PACK" --перегляд "$TMP/ключ-$i.sens" >"$TMP/ключ-$i.words"
  grep -Eq '^10 ([01]{7} )+01$' "$TMP/ключ-$i.words"
done

reject() {
  if "$CLI" "$@" >"$TMP/частковий.stdout" 2>"$TMP/помилка.stderr"; then
    echo 'CORE1-ІНДЕКС-ПРОВАЛ: хибний фізичний запит прийнято' >&2
    exit 1
  fi
  test ! -s "$TMP/частковий.stdout" || {
    echo 'CORE1-ІНДЕКС-ПРОВАЛ: частковий stdout' >&2; exit 1;
  }
  grep -Fq 'CORE1-ІНДЕКС-ВІДМОВА:' "$TMP/помилка.stderr" || {
    cat "$TMP/помилка.stderr" >&2; exit 1;
  }
}
reject --опис "$TMP/немає"
reject --форма "$ROOT" 0
reject --ключ "$ROOT" 130
reject --знайти "$ROOT" "$TMP/немає.sens"

mkdir -p "$TMP/підміна/external/sens/lib"
printf '\377' >"$TMP/підміна/external/sens/lib/core1.sens"
reject --опис "$TMP/підміна"

# Два повтори СПРАВЖНЬОГО визначення: однаковий exact D7 ключ.
W=$(cat "$TMP/форма-1.words")
printf '%s 00 %s\n' "$W" "$W" >"$TMP/дублікат.words"
"$PACK" --пакувати-слова "$TMP/дублікат.words" >"$TMP/підміна/external/sens/lib/core1.sens"
reject --опис "$TMP/підміна"

# Форма з чужою точною D4 головою — не DEFINE.
sed 's/^10 0011 /10 0010 /' "$TMP/форма-1.words" >"$TMP/чужа-голова.words"
"$PACK" --пакувати-слова "$TMP/чужа-голова.words" >"$TMP/підміна/external/sens/lib/core1.sens"
reject --опис "$TMP/підміна"

# Коректний фізичний D7-ключ, відсутній серед 129 визначень.
printf '10 0000000 01\n' >"$TMP/чужий-ключ.words"
"$PACK" --пакувати-слова "$TMP/чужий-ключ.words" >"$TMP/чужий-ключ.sens"
reject --знайти "$ROOT" "$TMP/чужий-ключ.sens"
printf '\377' >"$TMP/хибний-ключ.sens"
reject --знайти "$ROOT" "$TMP/хибний-ключ.sens"

# Після пізніх відмов індекс правильно відкриває реальний pinned Core1.
"$CLI" --знайти "$ROOT" "$TMP/ключ-129.sens" >"$TMP/відновлений.sens"
cmp "$TMP/відновлений.sens" "$TMP/форма-129.sens"
echo 'CORE1-ІНДЕКС-ТЕСТ-ГАРАЗД pinned=129 exact-D7=так пошук=байтовий негативні=9 відновлення=так виконання=ні'
