#!/usr/bin/env bash
# Реальні GUI/GTK2 widgets під Xvfb, кореневий pinned SENS без імітації.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v lazbuild >/dev/null || { echo "LAZARUS-БЛОК: потрібен lazbuild" >&2; exit 127; }
command -v xvfb-run >/dev/null || { echo "LAZARUS-БЛОК: потрібен xvfb-run" >&2; exit 127; }
./scripts/check-pin.sh
bash ./scripts/test-wideir.sh
mkdir -p build/lcl-wide-ir/bin build/lcl-wide-ir/units build/m0.2/wideir/bin
lazbuild --ws=gtk2 gui/wide-exactir.lpi
test -x build/lcl-wide-ir/bin/wide-exactir
fpc -B -Mobjfpc -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/wideir/units" -FE"$ROOT/build/m0.2/wideir/bin" \
  -osenst5m "$ROOT/src/senst5m.lpr"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PIN=$(git -C external/sens rev-parse HEAD)
timeout 70s git -C external/sens cat-file -e "$PIN:tests/semantic/d5-d12-numberp-law.sens"
timeout 70s git -C external/sens show "$PIN:tests/semantic/d5-d12-numberp-law.sens" > "$TMP/root.sens"
python3 - "$TMP/широке.words" <<'PY'
import sys
words=['10']+[('0'*(n-1)+'1') for n in (12,24,48,96,192,13)]+['01']
with open(sys.argv[1],'wb') as handle:
    handle.write((' '.join(words)+'\n').encode('ascii'))
PY
"$ROOT/build/m0.2/wideir/bin/senst5m" --пакувати-слова "$TMP/широке.words" > "$TMP/широке.sens"
printf '\363' > "$TMP/зіпсоване.sens"
LC_ALL=C.UTF-8 xvfb-run -a "$ROOT/build/lcl-wide-ir/bin/wide-exactir" \
  --самоперевірка "$TMP/root.sens" "$TMP/широке.sens" "$TMP/зіпсоване.sens" |
  tee "$TMP/результат.txt"
grep -Fq 'LAZARUS-ШИРОКЕ-IR-ГАРАЗД' "$TMP/результат.txt"
echo 'LAZARUS-ПЕРЕВІРКА-ГАРАЗД: pinned-SENS=так LCL=справжній W12-W192=точні'
