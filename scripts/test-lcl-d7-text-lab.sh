#!/usr/bin/env bash
# G1.24 — дві вже наявні pinned D7 проєкції + дійсний Lazarus GTK2/Xvfb.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
command -v lazbuild >/dev/null || { echo 'ЛАБОРАТОРІЯ-Д7-БЛОК: Lazarus відсутній' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'ЛАБОРАТОРІЯ-Д7-БЛОК: Xvfb відсутній' >&2; exit 127; }

# Чинні самостійні два кодеки/CLI не змінюємо й не вимикаємо.
bash scripts/test-d7tekst.sh
bash scripts/test-d7text.sh

mkdir -p build/lcl-d7text/bin build/lcl-d7text/units
lazbuild --ws=gtk2 gui/d7-text-lab.lpi
GUI="$ROOT/build/lcl-d7text/bin/d7-text-lab"
CLI="$ROOT/build/m0.2/d7text/bin/sensd7text"
test -x "$GUI" && test -x "$CLI"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '%s' 'Це 0() №Їґ' > "$TMP/текст.txt"
timeout 10s "$CLI" --кодувати-укр "$ROOT" "$TMP/текст.txt" \
  "$TMP/добрий.sens" > "$TMP/вхід-лог"
test -s "$TMP/добрий.sens"
timeout 10s "$CLI" --читати-укр "$ROOT" "$TMP/добрий.sens" \
  "$TMP/повернений.txt" > "$TMP/вихід-лог"
cmp "$TMP/текст.txt" "$TMP/повернений.txt"

# Вхідним фізичним D7 є ТОЧНІ семибітні слова, не D2 список.
FPC_BIN=${FPC:-fpc}
mkdir -p build/lcl-d7text/physical-units
"$FPC_BIN" -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$ROOT/build/lcl-d7text/physical-units" -FE"$ROOT/build/lcl-d7text/bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"
BIN="$ROOT/build/lcl-d7text/bin/senst5m"
printf '0010110\n' > "$TMP/syn.words"
printf '0110000 0\n' > "$TMP/змішаний.words"
"$BIN" --пакувати-слова "$TMP/syn.words" > "$TMP/syn.sens"
"$BIN" --пакувати-слова "$TMP/змішаний.words" > "$TMP/змішаний.sens"
printf '\363' > "$TMP/неканонічний.sens"

LC_ALL=C.UTF-8 timeout 45s xvfb-run -a "$GUI" --самоперевірка-д7 \
  "$TMP/добрий.sens" "$TMP/syn.sens" \
  "$TMP/змішаний.sens" "$TMP/неканонічний.sens" \
  2>&1 | tee "$TMP/свідчення"
grep -Fq 'LCL-Д7-ТЕКСТ-ГАРАЗД' "$TMP/свідчення"
echo 'ЛАБОРАТОРІЯ-Д7-ФІЗИЧНИЙ-ДОКАЗ-ГАРАЗД FPC=реальний GTK2-Xvfb=реальний D7=128/128'
