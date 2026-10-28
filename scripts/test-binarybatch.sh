#!/usr/bin/env bash
# Фізичні багатоформові свідки через FPC та наявний sensvykon.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
FPC_BIN=$(printenv FPC || echo fpc)
command -v "$FPC_BIN" >/dev/null || { echo 'ПАКЕТ-ПОМИЛКА: немає Free Pascal' >&2; exit 127; }
mkdir -p build/m0.2/binarybatch-units build/m0.2/bin
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/binarybatch-units" -FE"$ROOT/build/m0.2/bin" \
  -otest-binarybatch "$ROOT/scripts/test-binarybatch.pas"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/binarybatch-units" -FE"$ROOT/build/m0.2/bin" \
  -osenspaket "$ROOT/src/senspaket.lpr"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/binarybatch-units" -FE"$ROOT/build/m0.2/bin" \
  -osensvykon "$ROOT/src/sensvykon.lpr"
"$ROOT/build/m0.2/bin/test-binarybatch"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
{
  "$ROOT/build/m0.2/bin/sensvykon" --виконати build/m0.2/binarybatch-root1.sens
  "$ROOT/build/m0.2/bin/sensvykon" --виконати build/m0.2/binarybatch-root2.sens
  "$ROOT/build/m0.2/bin/sensvykon" --виконати build/m0.2/binarybatch-root3.sens
} > "$TMP/очікувано.txt"
"$ROOT/build/m0.2/bin/senspaket" --пакет build/m0.2/binarybatch-positive.sens > "$TMP/фактично.txt"
cmp "$TMP/очікувано.txt" "$TMP/фактично.txt"
printf '1\n(1)\n0\n' > "$TMP/точно.txt"
cmp "$TMP/точно.txt" "$TMP/фактично.txt"
for bad in binarybatch-unsupported binarybatch-unclosed binarybatch-corrupt; do
  if "$ROOT/build/m0.2/bin/senspaket" --пакет "build/m0.2/$bad.sens" \
    >"$TMP/$bad.out" 2>"$TMP/$bad.err"; then
    echo "ПАКЕТ-ПОМИЛКА: неприпустимий $bad прийнято" >&2; exit 1
  fi
  test ! -s "$TMP/$bad.out"
  grep -F 'ПАКЕТ-SENS-ПОМИЛКА' "$TMP/$bad.err" >/dev/null
done
grep -F 'форма=2 слово=3' "$TMP/binarybatch-unsupported.err" >/dev/null
grep -F 'слово=4' "$TMP/binarybatch-unclosed.err" >/dev/null
if "$ROOT/build/m0.2/bin/senspaket" --пакет відсутній.sens \
  >"$TMP/missing.out" 2>"$TMP/missing.err"; then exit 1; fi
test ! -s "$TMP/missing.out"
if "$ROOT/build/m0.2/bin/senspaket" --пакет будь-що.lisp \
  >"$TMP/wrong.out" 2>"$TMP/wrong.err"; then exit 1; fi
test ! -s "$TMP/wrong.out"
if "$ROOT/build/m0.2/bin/senspaket" --невідомо build/m0.2/binarybatch-positive.sens \
  >"$TMP/arg.out" 2>"$TMP/arg.err"; then exit 1; fi
test ! -s "$TMP/arg.out"
echo 'ДВІЙКОВИЙ-ПАКЕТ-КЛІ-ГАРАЗД FPC=реальний SENS=фізичний корені=3 вивід=атомарний'
