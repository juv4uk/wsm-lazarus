#!/usr/bin/env bash
# Реальний FPC/FCL + Lazarus GTK2/Xvfb: файлова черга фізичного SENS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v fpc >/dev/null || { echo 'Немає FPC' >&2; exit 127; }
command -v lazbuild >/dev/null || { echo 'Немає Lazarus' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'Немає Xvfb' >&2; exit 127; }
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
mkdir -p build/m0.2/fiz-faily-units build/m0.2/fiz-faily-bin \
  build/lcl/bin build/lcl/fiz-faily-units
for executable in senst5m sensfizseans sensfizfaily; do
  fpc -B -Mobjfpc -Cr -Co -Ci -gl \
    -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/fiz-faily-units" \
    -FE"$ROOT/build/m0.2/fiz-faily-bin" -o"$executable" \
    "$ROOT/src/$executable.lpr"
done
lazbuild --widgetset=gtk2 --build-all gui/sens-fiz-faily-ogliad.lpi
GUI="$ROOT/build/lcl/bin/sens-fiz-faily-ogliad"
PACK="$ROOT/build/m0.2/fiz-faily-bin/senst5m"
CLIENT="$ROOT/build/m0.2/fiz-faily-bin/sensfizfaily"
SERVER="$ROOT/build/m0.2/fiz-faily-bin/sensfizseans"
test -x "$GUI"; test -x "$PACK"; test -x "$CLIENT"; test -x "$SERVER"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '1\n' > "$TMP/так.words"
printf '10 001 0010110 01\n' > "$TMP/д7.words"
"$PACK" --пакувати-слова "$TMP/так.words" > "$TMP/так.sens"
"$PACK" --пакувати-слова "$TMP/д7.words" > "$TMP/д7.sens"
printf '\363' > "$TMP/відмова.sens"
printf '(цитувати так)\n' > "$TMP/людський.lisp"
cat > "$TMP/підроблений-клієнт" <<'SH'
#!/bin/sh
# Пошкоджений host stdout НЕ є підтвердженим SENS результатом.
printf '\000\000'
SH
chmod +x "$TMP/підроблений-клієнт"
LC_ALL=C.UTF-8 timeout --signal=TERM --kill-after=5s 120s \
  xvfb-run -a -s '-screen 0 1280x900x24' "$GUI" \
    --самоперевірка "$CLIENT" "$SERVER" \
    "$TMP/так.sens" "$TMP/д7.sens" "$TMP/відмова.sens" \
    "$TMP/відсутній.sens" "$TMP/людський.lisp" \
    "$TMP/підроблений-клієнт" > "$TMP/stdout" 2>"$TMP/stderr"
cat "$TMP/stdout"
test ! -s "$TMP/stderr"
grep -Fq 'ЛКЛ-ФІЗИЧНІ-ФАЙЛИ-ГАРАЗД Lazarus=GTK2' "$TMP/stdout"
grep -Fq 'D7=шість-pinned T5M=точно' "$TMP/stdout"
grep -Fq 'host-розрив=відхилено' "$TMP/stdout"
grep -Fq 'REPL=НЕ-ГОТОВИЙ' "$TMP/stdout"
echo 'ЛКЛ-ФІЗИЧНІ-ФАЙЛИ-ЗБІРКА-ГАРАЗД FPC=3.2.x Lazarus=GTK2 Xvfb=так'
