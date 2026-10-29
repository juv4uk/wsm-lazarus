#!/usr/bin/env bash
# Тільки справжні Free Pascal/Lazarus і pinned .sens/EIR1; не текстовий oracle.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
./scripts/check-no-lcl.sh
./scripts/check-pin.sh
command -v fpc >/dev/null
command -v lazbuild >/dev/null
command -v xvfb-run >/dev/null
command -v timeout >/dev/null
mkdir -p build/m0.2/lcl-ir-units build/m0.2/bin build/lcl-ir/bin build/lcl-ir/units
for entry in 'sensirvykon src/sensirvykon.lpr' 'sensexact src/sensexact.lpr' 'senst5m src/senst5m.lpr'; do
  read -r name file <<< "$entry"
  fpc -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/lcl-ir-units" \
    -FE"$ROOT/build/m0.2/bin" -o"$name" "$ROOT/$file" >/dev/null
done
lazbuild --widgetset=gtk2 --build-all gui/sens-ir-vykonannia.lpi
GUI="$ROOT/build/lcl-ir/bin/sens-ir-vykonannia"
RUN="$ROOT/build/m0.2/bin/sensirvykon"
MINT="$ROOT/build/m0.2/bin/sensexact"
PACK="$ROOT/build/m0.2/bin/senst5m"
test -x "$GUI"; test -x "$RUN"; test -x "$MINT"
TMP=$(mktemp -d "$ROOT/build/m0.2/lcl-ir.XXXXXXXX")
trap 'rm -rf "$TMP"' EXIT
printf '1\n' > "$TMP/добрий.words"
"$PACK" --пакувати-слова "$TMP/добрий.words" > "$TMP/добрий.sens"
"$MINT" --створити-ір "$TMP/добрий.sens" "$TMP/добрий.eir" >/dev/null
printf '0\n' > "$TMP/ні.words"
"$PACK" --пакувати-слова "$TMP/ні.words" > "$TMP/ні.sens"
"$MINT" --створити-ір "$TMP/ні.sens" "$TMP/чужий.eir" >/dev/null
printf '10 001 0010110 01\n' > "$TMP/d7.words"
"$PACK" --пакувати-слова "$TMP/d7.words" > "$TMP/d7.sens"
"$MINT" --створити-ір "$TMP/d7.sens" "$TMP/d7.eir" >/dev/null
printf '0010110\n' > "$TMP/d7-result.words"
"$PACK" --пакувати-слова "$TMP/d7-result.words" > "$TMP/d7-result.sens"
printf '\363' > "$TMP/зіпсовано.sens"
cp "$TMP/добрий.eir" "$TMP/зіпсовано.eir"
printf '\000' | dd of="$TMP/зіпсовано.eir" bs=1 seek=0 conv=notrunc status=none
printf '(цитувати так)\n' > "$TMP/текст.lisp"
LC_ALL=C.UTF-8 timeout --signal=TERM --kill-after=5s 100s \
  xvfb-run -a -s '-screen 0 1280x900x24' "$GUI" \
  --самоперевірка "$RUN" "$TMP/добрий.sens" "$TMP/добрий.eir" \
  "$TMP/добрий.sens" "$TMP/d7.sens" "$TMP/d7.eir" \
  "$TMP/d7-result.sens" "$TMP/чужий.eir" \
  "$TMP/зіпсовано.sens" "$TMP/зіпсовано.eir" \
  "$TMP/текст.lisp" "$TMP/відсутній.eir" \
  >"$TMP/stdout" 2>"$TMP/stderr"
test ! -s "$TMP/stderr"
grep -Fq 'ЛКЛ-ПЕРЕВІРЕНИЙ-IR-ГАРАЗД Lazarus=GTK2' "$TMP/stdout"
grep -Fq 'кліків=7 виконано=3 відхилено=4' "$TMP/stdout"
grep -Fq 'проєкцій=6 IR-compiler=НЕ-ГОТОВИЙ' "$TMP/stdout"
echo 'ЛКЛ-ПЕРЕВІРЕНИЙ-IR-ЗБІРКА-ГАРАЗД FPC=так Lazarus=GTK2 Xvfb=так'
