#!/usr/bin/env bash
# Однаково перевіряє нативний CLI та справжнє вікно Lazarus.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
command -v fpc >/dev/null || { echo 'Т5М-РІЗНИЦЯ-ПОМИЛКА: немає FPC' >&2; exit 127; }
mkdir -p build/t5mdiff/units build/t5mdiff/bin \
  build/lcl-physdiff/bin build/lcl-physdiff/units
for source in scripts/test-t5mdiff.pas src/senst5m.lpr src/sensporivnia.lpr; do
  fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
    -FU"$ROOT/build/t5mdiff/units" \
    -FE"$ROOT/build/t5mdiff/bin" "$source"
done
build/t5mdiff/bin/test-t5mdiff
TMP=$(mktemp -d)
# Вказівники етапів: збій не губиться за grep або редиректом.
echo 'ПЕРЕВІРКА-CLI: побудова фізичних свідків'
trap 'rm -rf "$TMP"' EXIT
printf '0 000000000001 111\n' > "$TMP/a.words"
printf '0 000000000001 110\n' > "$TMP/b.words"
printf '0 0000000000001 111\n' > "$TMP/width.words"
printf '0 000000000001\n' > "$TMP/short.words"
for stem in a b width short; do
  build/t5mdiff/bin/senst5m --пакувати-слова "$TMP/$stem.words" > "$TMP/$stem.sens"
done
cp "$TMP/a.sens" "$TMP/bad.sens"
printf '\363' >> "$TMP/bad.sens"
build/t5mdiff/bin/sensporivnia "$TMP/a.sens" "$TMP/a.sens" > "$TMP/same.out"
grep -q 'ФІЗИЧНІ-СВІДКИ-ТОТОЖНІ слів=3' "$TMP/same.out"
set +e
build/t5mdiff/bin/sensporivnia "$TMP/a.sens" "$TMP/b.sens" > "$TMP/bit.out" 2> "$TMP/bit.err"
RC=$?
set -e
test "$RC" -eq 1
test ! -s "$TMP/bit.err"
grep -q 'вид=біти слово=3 біт=3' "$TMP/bit.out"
grep -Fq 'трити=[15,18) байти=[3,4)' "$TMP/bit.out"
set +e
build/t5mdiff/bin/sensporivnia "$TMP/a.sens" "$TMP/width.sens" > "$TMP/width.out"
RC=$?
set -e
test "$RC" -eq 1
grep -q 'вид=ширина слово=2 біт=0 ліва-ширина=12 права-ширина=13' "$TMP/width.out"
set +e
build/t5mdiff/bin/sensporivnia "$TMP/a.sens" "$TMP/short.sens" > "$TMP/count.out"
RC=$?
set -e
test "$RC" -eq 1
grep -q 'вид=кількість-слів слово=3' "$TMP/count.out"
grep -q 'праве=EOF' "$TMP/count.out"
set +e
build/t5mdiff/bin/sensporivnia "$TMP/a.sens" "$TMP/bad.sens" > "$TMP/fail.out" 2>"$TMP/fail.err"
RC=$?
set -e
test "$RC" -eq 2
test ! -s "$TMP/fail.out"
grep -q 'ФІЗИЧНЕ-ПОРІВНЯННЯ-ПОМИЛКА' "$TMP/fail.err"
set +e
build/t5mdiff/bin/sensporivnia > "$TMP/usage.out" 2>"$TMP/usage.err"
RC=$?
set -e
test "$RC" -eq 64
test ! -s "$TMP/usage.out"
if [[ "$(printenv WITH_LAZARUS || true)" == "1" ]]; then
  command -v lazbuild >/dev/null || { echo 'LCL-ПОМИЛКА: немає lazbuild' >&2; exit 127; }
  command -v xvfb-run >/dev/null || { echo 'LCL-ПОМИЛКА: немає xvfb-run' >&2; exit 127; }
  lazbuild --ws=gtk2 gui/sens-physdiff.lpi
  test -x build/lcl-physdiff/bin/sens-physdiff
  LC_ALL=C.UTF-8 xvfb-run -a build/lcl-physdiff/bin/sens-physdiff \
    --самоперевірка "$TMP/a.sens" "$TMP/b.sens" \
    "$TMP/width.sens" "$TMP/short.sens" "$TMP/bad.sens" \
    | tee "$TMP/lcl.out"
  grep -q 'LCL-ФІЗИЧНА-РІЗНИЦЯ-ГАРАЗД' "$TMP/lcl.out"
fi
echo 'Т5М-РІЗНИЦЯ-CLI-ГАРАЗД FPC=дійсний двійкові-слова=точні семантика=НЕ-ПЕРЕВІРЕНО'
