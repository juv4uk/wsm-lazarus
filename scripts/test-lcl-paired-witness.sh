#!/usr/bin/env bash
# G1.9: два дійсні pinned кореневі .lisp/.sens свідки, LCL Xvfb.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
command -v lazbuild >/dev/null || { echo 'LCL-ПАРНІ-ПОМИЛКА: немає lazbuild' >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo 'LCL-ПАРНІ-ПОМИЛКА: немає xvfb-run' >&2; exit 127; }
command -v fpc >/dev/null || { echo 'LCL-ПАРНІ-ПОМИЛКА: немає FPC' >&2; exit 127; }
# Збереження вже чинного фізичного D12+ gate, без власного decoder.
bash ./scripts/test-widespan.sh
mkdir -p build/lcl-paired/bin build/lcl-paired/units \
  build/m0.2/paired-units build/m0.2/paired-bin
lazbuild --ws=gtk2 gui/sens-paired-witness.lpi
test -x build/lcl-paired/bin/sens-paired-witness
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/paired-units" \
  -FE"$ROOT/build/m0.2/paired-bin" -osenst5m src/senst5m.lpr
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '(сполучити ні так)\n' >"$TMP/людський.lisp"
printf '0 000000000001 01 0000000000000 10101010101 111111111111\n' >"$TMP/слова.txt"
build/m0.2/paired-bin/senst5m --пакувати-слова "$TMP/слова.txt" >"$TMP/фізичний.sens"
printf '\377' >"$TMP/поганий-utf8.lisp"
printf '\363' >"$TMP/поганий-t5m.sens"

# Звертаємося до ДІЙСНИХ файлів ДЖЕРЕЛЬНОГО pinned кореневого
# SENS за точним gitlink, без змін sparse pin і без нових копій у main.
PIN=$(git -C external/sens rev-parse HEAD)
EXPECTED=$(git ls-tree HEAD external/sens | awk '{print $3}')
test "$PIN" = "$EXPECTED"
for pair in law five; do
  if [[ "$pair" == law ]]; then
    path='tests/semantic/d5-d12-numberp-law'
  else
    path='lib/axioms-d1-principle-five'
  fi
  GIT_TERMINAL_PROMPT=0 timeout 90 git -C external/sens show "$PIN:$path.lisp" >"$TMP/$pair.lisp"
  GIT_TERMINAL_PROMPT=0 timeout 90 git -C external/sens show "$PIN:$path.sens" >"$TMP/$pair.sens"
  test -s "$TMP/$pair.lisp"
  test -s "$TMP/$pair.sens"
done
LC_ALL=C.UTF-8 xvfb-run -a build/lcl-paired/bin/sens-paired-witness \
  --самоперевірка "$TMP/людський.lisp" "$TMP/фізичний.sens" \
  "$TMP/law.lisp" "$TMP/law.sens" "$TMP/five.lisp" "$TMP/five.sens" \
  "$TMP/поганий-utf8.lisp" "$TMP/поганий-t5m.sens" \
  | tee "$TMP/журнал.txt"
grep -Fq 'LCL-ПАРНІ-СВІДКИ-ГАРАЗД' "$TMP/журнал.txt"
echo 'LCL-ПАРНІ-ДОКАЗ-ГАРАЗД Lazarus=GTK2-Xvfb root=.lisp+.sens п’ять-принципів=прочитано D12+=фізично перевірено semantic-parity=НЕ-ДОВЕДЕНО'
