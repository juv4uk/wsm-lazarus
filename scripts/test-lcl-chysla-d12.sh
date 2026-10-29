#!/usr/bin/env bash
# G3.31: справжній LCL/GTK2 перегляд фізичних числових пакетів D12–D192.
# Canonical .sens створюють чинні FPC T5M CLI, не графічний parser.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo 'LCL-ЧИСЛА-БЛОК: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ЧИСЛА-БЛОК: немає xvfb-run' >&2; exit 127; }
./scripts/check-no-lcl.sh
./scripts/check-pin.sh
# 4096/4096 D12 та інші домени + попередні FPC-пакетні негативи.
bash ./scripts/test-chyslopaket.sh
mkdir -p build/lcl-chysla-d12/bin build/lcl-chysla-d12/units
lazbuild --widgetset=gtk2 --build-all gui/sens-chysla-d12.lpi
BIN="$ROOT/build/lcl-chysla-d12/bin/sens-chysla-d12"
CLI="$ROOT/build/m0.2/bin/senschyslo"
PACK="$ROOT/build/m0.2/bin/senst5m"
BATCH="$ROOT/build/m0.2/bin/senschyslopaket"
for exe in "$BIN" "$CLI" "$PACK" "$BATCH"; do
  test -x "$exe" || { echo "LCL-ЧИСЛА-БЛОК: немає $exe" >&2; exit 1; }
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' '-2048' > "$TMP/дванадцять.lisp"
printf '%s\n' '-3138550867693340381917894711603833208051177722232017256448' > "$TMP/сто-девяносто-два.lisp"
"$CLI" --з-укр D12 "$TMP/дванадцять.lisp" "$TMP/дванадцять.sens"
"$CLI" --з-укр D192 "$TMP/сто-девяносто-два.lisp" "$TMP/сто-девяносто-два.sens"
test "$(stat -c '%a' "$TMP/дванадцять.sens")" = '600'
test "$(stat -c '%a' "$TMP/сто-девяносто-два.sens")" = '600'
printf '\363' > "$TMP/зіпсовано.sens"

# Зовнішній від GUI FPC CLI пакує фізичні W12, а чинний пакетний CLI
# доводить точні десяткові значення та напіввідкриті trit/byte адреси.
printf '100000000000 111111111111 000000000000\n' > "$TMP/три.words"
"$PACK" --пакувати-слова "$TMP/три.words" > "$TMP/три.sens"
"$BATCH" --перегляд-пакета D12 "$TMP/три.sens" > "$TMP/три.tsv"
grep -Fq "$(printf '1\tD12\t-2048\t100000000000\t[0,12)\t[0,3)')" "$TMP/три.tsv"
grep -Fq "$(printf '2\tD12\t-1\t111111111111\t[13,25)\t[2,5)')" "$TMP/три.tsv"
grep -Fq "$(printf '3\tD12\t0\t000000000000\t[26,38)\t[5,8)')" "$TMP/три.tsv"

# Вхід із пізньою невідповідною шириною, змішаний і завеликий пакет.
printf '100000000000 111111111111 0000000000000\n' > "$TMP/пізнє.words"
"$PACK" --пакувати-слова "$TMP/пізнє.words" > "$TMP/пізнє.sens"
printf '100000000000 0\n' > "$TMP/змішані.words"
"$PACK" --пакувати-слова "$TMP/змішані.words" > "$TMP/змішані.sens"
for ((i=0;i<1025;i++)); do
  if ((i>0)); then printf ' '; fi
  printf '000000000000'
done > "$TMP/надлишок.words"
printf '\n' >> "$TMP/надлишок.words"
"$PACK" --пакувати-слова "$TMP/надлишок.words" > "$TMP/надлишок.sens"

LC_ALL=C.UTF-8 xvfb-run -a -s '-screen 0 1280x900x24' "$BIN" \
  --самоперевірка "$TMP/дванадцять.sens" \
  "$TMP/сто-девяносто-два.sens" "$TMP/зіпсовано.sens" \
  "$TMP/дванадцять.lisp" "$TMP/три.sens" \
  "$TMP/пізнє.sens" "$TMP/змішані.sens" "$TMP/надлишок.sens" \
  > "$TMP/stdout" 2> "$TMP/stderr"
test ! -s "$TMP/stderr" || { cat "$TMP/stderr" >&2; exit 1; }
grep -Fq 'LCL-ЧИСЛА-D12-ГАРАЗД' "$TMP/stdout"
grep -Fq 'LCL-ЧИСЛА-ПАКЕТ-ГАРАЗД' "$TMP/stdout"
grep -Fq 'арифметика=НЕ-ДОВЕДЕНА' "$TMP/stdout"
echo 'LAZARUS-ЧИСЛА-ПАКЕТ-ЗБІРКА-ГАРАЗД FPC=реальний LCL=GTK2/Xvfb T5M=фізичний D12-D192=явний'
