#!/usr/bin/env bash
# G3.40: реальна GTK2/Xvfb взаємодія з чинним pinned D3 evaluator.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
command -v lazbuild >/dev/null || { echo 'LCL-БЛОК: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-БЛОК: немає Xvfb' >&2; exit 127; }
mkdir -p build/lcl-fizychnyi-vykon/bin build/lcl-fizychnyi-vykon/units
timeout 150 lazbuild --ws=gtk2 --build-all gui/sens-fizychnyi-vykon.lpi
BIN="$ROOT/build/lcl-fizychnyi-vykon/bin/sens-fizychnyi-vykon"
test -x "$BIN" || { echo 'LCL-БЛОК: бінарник не створено' >&2; exit 1; }
mkdir -p build/m0.2/lcl-vykon/bin build/m0.2/lcl-vykon/units
timeout 90 "${FPC:-fpc}" -B -Mobjfpc -Cr -Co -Ci -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/lcl-vykon/units" \
  -FE"$ROOT/build/m0.2/lcl-vykon/bin" -osenst5m "$ROOT/src/senst5m.lpr"
PACK="$ROOT/build/m0.2/lcl-vykon/bin/senst5m"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '1\n' > "$TMP/атом.words"
printf '10 001 1 01\n' > "$TMP/цитата.words"
printf '1 1\n' > "$TMP/два.words"
"$PACK" --пакувати-слова "$TMP/атом.words" > "$TMP/атом.sens"
"$PACK" --пакувати-слова "$TMP/цитата.words" > "$TMP/цитата.sens"
"$PACK" --пакувати-слова "$TMP/два.words" > "$TMP/два.sens"
printf '\363' > "$TMP/зіпсовано.sens"
: > "$TMP/порожньо.sens"
printf '(цитата 1)\n' > "$TMP/не-двійковий.lisp"
LC_ALL=C.UTF-8 timeout 50 xvfb-run -a -s '-screen 0 1280x800x24' \
  "$BIN" --самоперевірка "$TMP/атом.sens" "$TMP/цитата.sens" \
  "$TMP/зіпсовано.sens" "$TMP/порожньо.sens" \
  "$TMP/два.sens" "$TMP/не-двійковий.lisp" \
  > "$TMP/звіт" 2> "$TMP/помилки" || {
    cat "$TMP/помилки" >&2
    cat "$TMP/звіт" >&2
    exit 1
  }
test ! -s "$TMP/помилки" || { cat "$TMP/помилки" >&2; exit 1; }
grep -Fq 'LCL-ФІЗИЧНЕ-ВИКОНАННЯ-ГАРАЗД FPC=реальний D1=так D3=так T5M=побайтово негативи=4 відновлення=так' "$TMP/звіт"
grep -Fq 'LCL-ФІЗИЧНИЙ-D7-ГАРАЗД шість=pinned ук-укр-san-en-LISP-sym значення=тільки-дані callable=ні' "$TMP/звіт"
echo 'LCL-ФІЗИЧНЕ-ВІКНО-ЗБІРКА-ГАРАЗД Lazarus=GTK2-Xvfb виконавець=pinned'
