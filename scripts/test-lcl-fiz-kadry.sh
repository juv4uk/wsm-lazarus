#!/usr/bin/env bash
# Дійсний LCL+FPC процес/pipe; pinned Contract 12; host ≠ SENS law.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v fpc >/dev/null
command -v lazbuild >/dev/null
command -v xvfb-run >/dev/null
command -v timeout >/dev/null
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
mkdir -p build/m0.2/fizseans-units build/m0.2/fizseans-bin build/lcl/bin build/lcl/fiz-kadry-units
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/fizseans-units" -FE"$ROOT/build/m0.2/fizseans-bin" \
  -osensfizseans "$ROOT/src/sensfizseans.lpr"
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/fizseans-units" -FE"$ROOT/build/m0.2/fizseans-bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"
lazbuild --widgetset=gtk2 --build-all gui/sens-fiz-kadry.lpi
BIN="$ROOT/build/lcl/bin/sens-fiz-kadry"
PACK="$ROOT/build/m0.2/fizseans-bin/senst5m"
SERVER="$ROOT/build/m0.2/fizseans-bin/sensfizseans"
test -x "$BIN"; test -x "$SERVER"; test -x "$PACK"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
printf '10 001 1 01\n' > "$TMP/цитата.words"
"$PACK" --пакувати-слова "$TMP/цитата.words" > "$TMP/цитата.sens"
printf '\363' > "$TMP/помилка.sens"
printf '10 001 0010110 01\n' > "$TMP/d7.words"
"$PACK" --пакувати-слова "$TMP/d7.words" > "$TMP/d7.sens"
printf '(цитувати так)\n' > "$TMP/текст.lisp"
LC_ALL=C.UTF-8 timeout --signal=TERM --kill-after=5s 100s \
  xvfb-run -a -s '-screen 0 1280x900x24' "$BIN" \
  --самоперевірка "$SERVER" "$TMP/цитата.sens" \
  "$TMP/помилка.sens" "$TMP/d7.sens" "$TMP/текст.lisp" \
  > "$TMP/stdout" 2> "$TMP/stderr"
test ! -s "$TMP/stderr"
grep -Fq 'ЛКЛ-ФІЗИЧНІ-КАДРИ-ГАРАЗД PID=той-самий' "$TMP/stdout"
grep -Fq 'D7=SYN pinned-проєкцій=6 byte-exact=так' "$TMP/stdout"
grep -Fq 'REPL=НЕ-ГОТОВИЙ' "$TMP/stdout"
echo 'ЛКЛ-ФІЗИЧНІ-КАДРИ-ЗБІРКА-ГАРАЗД FPC=так Lazarus=GTK2 Xvfb=так'
