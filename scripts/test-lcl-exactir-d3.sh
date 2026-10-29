#!/usr/bin/env bash
# G3.14 — справжній Lazarus D3:001 / D3:111 з двійковою T5M відповіддю.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
command -v xvfb-run >/dev/null || {
  echo 'LCL-D3-ПОМИЛКА: відсутній Xvfb' >&2; exit 127;
}
# Спершу всі попередні незалежні ворота GUI і фізичного evaluator.
bash ./scripts/test-lcl-exactir.sh
bash ./scripts/test-native-physical-answer.sh
ROOT_BIN="$ROOT/build/m0.2/bin/senst5m"
GUI="$ROOT/build/lcl-exactir/bin/exactir-inspector"
test -x "$GUI"
test -x "$ROOT_BIN"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf '10 001 000 01\n' > "$TMP/цитата.words"
printf '000\n' > "$TMP/цитата-очікування.words"
printf '10 111 1 0 01\n' > "$TMP/сполучення.words"
printf '10 1 11 0 01\n' > "$TMP/сполучення-очікування.words"
for item in цитата цитата-очікування сполучення сполучення-очікування; do
  "$ROOT_BIN" --пакувати-слова "$TMP/$item.words" > "$TMP/$item.sens"
done
# Це граматично допустима вхідна D2 пара, але вузький native
# evaluator НЕ приймає крапковий список як виконуваний D3 виклик.
cp "$TMP/сполучення-очікування.sens" "$TMP/вхідна-пара.sens"
printf '\363' > "$TMP/зіпсовано.sens"
LC_ALL=C.UTF-8 xvfb-run -a "$GUI" --самоперевірка-виконання \
  "$TMP/цитата.sens" "$TMP/цитата-очікування.sens" \
  "$TMP/сполучення.sens" "$TMP/сполучення-очікування.sens" \
  "$TMP/вхідна-пара.sens" "$TMP/зіпсовано.sens" \
  | tee "$TMP/свідчення"
grep -Fq 'LCL-D3-ВИКОНАННЯ-ГАРАЗД' "$TMP/свідчення"
echo 'LCL-D3-ФІЗИЧНИЙ-ДОКАЗ-ГАРАЗД Lazarus=GTK2-Xvfb T5M=точний oracle=окрема-SENS-REPL-робота'
