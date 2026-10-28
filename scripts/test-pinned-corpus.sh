#!/usr/bin/env bash
# G2.14: реальні .lisp/.sens/видимі біти із ТОГО САМОГО pinned SENS.
# Перевірка механіки та доказу походження; ніякої нової мовної семантики.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
command -v git >/dev/null
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'КОРЕНЕВІ-СВІДКИ-БЛОК: потрібен Free Pascal' >&2
  exit 127
}

UPSTREAM="$ROOT/external/sens"
PIN=$(git -C "$UPSTREAM" rev-parse HEAD)
GITLINK=$(git ls-tree HEAD external/sens | awk '{print $3}')
[[ "$PIN" == "$GITLINK" ]] || { echo 'КОРЕНЕВІ-СВІДКИ-ПОМИЛКА: pin drift' >&2; exit 1; }

BIN="$ROOT/build/m0.2/pinned-corpus/bin"
UNITS="$ROOT/build/m0.2/pinned-corpus/units"
mkdir -p "$BIN" "$UNITS"
for program in senst5m sensbind sensholovy sensshyryna; do
  "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$UNITS" -FE"$BIN" -o"$program" "$ROOT/src/$program.lpr" > /dev/null
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Істинні Git-об'єкти pinned upstream, навіть якщо вони поза sparse checkout.
# Принцип: не копіювати/не модифікувати бібліотечні програми, не підмінювати pin.
pinned_file() {
  local source_path=$1 dest=$2
  timeout 70s git -C "$UPSTREAM" cat-file -e "$PIN:$source_path"
  timeout 70s git -C "$UPSTREAM" show "$PIN:$source_path" > "$dest"
  test -s "$dest"
}

# Реальний бінарний T5M має бути тотожним власному похідному бітовому
# перегляду кореневого SENS, а пакування має відновити ТІ САМІ байти.
physical_triple() {
  local stem=$1 label=$2
  pinned_file "$stem.sens" "$TMP/$label.sens"
  pinned_file "$stem" "$TMP/$label.еталон"
  "$BIN/senst5m" --перегляд "$TMP/$label.sens" > "$TMP/$label.біти"
  cmp "$TMP/$label.еталон" "$TMP/$label.біти"
  "$BIN/senst5m" --пакувати-слова "$TMP/$label.біти" > "$TMP/$label.відновлено.sens"
  cmp "$TMP/$label.sens" "$TMP/$label.відновлено.sens"
  "$BIN/sensholovy" --голови "$TMP/$label.sens" "$UPSTREAM" > "$TMP/$label.голови"
  grep -F 'викличність=не-доведено' "$TMP/$label.голови" >/dev/null
}

physical_triple 'examples/migrated/smoke-quote' 'цитата'
physical_triple 'examples/migrated/smoke-cond' 'умова'
physical_triple 'tests/oracles/d1-cond-law/proof' 'доказ-д1'

# .lisp у кореневому проєкті — САМОСТІЙНЕ українське джерело.
# Воно структурно читається через наявний reader, але аналіз голів
# НІКОЛИ не підмінює semantic parity або фізичну тотожність.
for row in 'smoke-quote:цитата' 'smoke-cond:умова'; do
  source_name=${row%%:*}
  label=${row#*:}
  pinned_file "examples/migrated/$source_name.lisp" "$TMP/$label.lisp"
  "$BIN/sensbind" --analyze "$TMP/$label.lisp" "$UPSTREAM" > "$TMP/$label.людський-звіт"
  grep -F 'SENSBIND-SUMMARY' "$TMP/$label.людський-звіт" |
    grep -F 'callable=unverified' > /dev/null
done

# Реальний ратифікований свідок із назвою d12 містить саме D24
# exact-width фізичні слова. Назва файла або десяткові токени у .lisp
# НЕ надають ані числової ідентичності, ані callability FPC binder.
numeric_stem='tests/semantic/d5-d12-numberp-law'
pinned_file "$numeric_stem.sens" "$TMP/число.sens"
pinned_file "$numeric_stem" "$TMP/число.еталон"
pinned_file "$numeric_stem.lisp" "$TMP/число.lisp"
"$BIN/senst5m" --перегляд "$TMP/число.sens" > "$TMP/число.біти"
cmp "$TMP/число.еталон" "$TMP/число.біти"
"$BIN/senst5m" --пакувати-слова "$TMP/число.біти" > "$TMP/число.повтор.sens"
cmp "$TMP/число.sens" "$TMP/число.повтор.sens"
"$BIN/sensshyryna" --широкі-слова "$TMP/число.sens" > "$TMP/число.tsv"
awk -F '\t' 'NR>1 {if($2!="D24" || length($3)!=24) exit 1; n++}
             END {if(n!=2) exit 1}' "$TMP/число.tsv"
grep -F $'D24\t000000000000000000000001' "$TMP/число.tsv" > /dev/null
grep -F $'D24\t000000000000000000000011' "$TMP/число.tsv" > /dev/null
"$BIN/sensbind" --analyze "$TMP/число.lisp" "$UPSTREAM" > "$TMP/число.український"
grep -F 'callable=unverified' "$TMP/число.український" > /dev/null
# Нинішній D2 binder дозволяє W1 і W3–W9, тож W24 має
# явно відхилятися, не перетворюватись на D1..D10 чи host integer.
if "$BIN/sensholovy" --голови "$TMP/число.sens" "$UPSTREAM" \
      >"$TMP/число.хибний-stdout" 2>"$TMP/число.діагностика"; then
  echo 'КОРЕНЕВІ-СВІДКИ-ПОМИЛКА: W24 помилково прийнято binder' >&2; exit 1
fi
test ! -s "$TMP/число.хибний-stdout"
grep -F 'ДВІЙКОВІ-ГОЛОВИ-ПОМИЛКА:' "$TMP/число.діагностика" >/dev/null

# Негативний байт 243: транспорт повністю відхиляє потік, не друкує
# часткових бітів, навіть якщо спочатку містяться правильні фізичні байти.
cp "$TMP/цитата.sens" "$TMP/зіпсований.sens"
printf '\363' >> "$TMP/зіпсований.sens"
if "$BIN/senst5m" --перегляд "$TMP/зіпсований.sens" \
      > "$TMP/хибний-stdout" 2>"$TMP/відмова"; then
  echo 'КОРЕНЕВІ-СВІДКИ-ПОМИЛКА: пошкоджений фізичний T5M прийнято' >&2; exit 1
fi
test ! -s "$TMP/хибний-stdout"

# Жодних довільних оцінок енергії, продуктивності чи виконання законів.
echo "КОРЕНЕВІ-СВІДКИ-ГАРАЗД: pin=$PIN фізичні=4 трійки=3 ukr=структурно D24=2 fail-closed=так семантика=не-доведено ENERGY_NOT_MEASURED"
