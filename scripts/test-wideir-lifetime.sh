#!/usr/bin/env bash
# RED -> GREEN: FPC heaptrc доводить життєвий цикл RawByteString широкого IR.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
./scripts/check-no-lcl.sh
command -v fpc >/dev/null
command -v git >/dev/null
PIN=$(git -C external/sens rev-parse HEAD)
GITLINK=$(git ls-tree HEAD external/sens | awk '{print $3}')
test "$PIN" = "$GITLINK"
mkdir -p build/m0.2/wideir-lifetime/bin build/m0.2/wideir-lifetime/units
fpc -B -Mobjfpc -gh -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/wideir-lifetime/units" \
  -FE"$ROOT/build/m0.2/wideir-lifetime/bin" \
  -otest-wideir-lifetime "$ROOT/scripts/test-wideir-lifetime.pas"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 70s git -C external/sens cat-file -e \
  "$PIN:tests/semantic/d5-d12-numberp-law.sens"
timeout 70s git -C external/sens show \
  "$PIN:tests/semantic/d5-d12-numberp-law.sens" > "$TMP/корінь.sens"
test -s "$TMP/корінь.sens"
STATUS=0
"$ROOT/build/m0.2/wideir-lifetime/bin/test-wideir-lifetime" \
  "$TMP/корінь.sens" >"$TMP/stdout" 2>"$TMP/stderr" || STATUS=$?
if [[ "$STATUS" -ne 0 ]] ||
   grep -Eiq 'heap dump|unfreed memory blocks|call trace for block|runtime error' \
      "$TMP/stderr" ||
   [[ -s "$TMP/stderr" ]] ||
   ! grep -Fq 'ШИРОКЕ-IR-ПАМ’ЯТЬ-ТЕСТ:' "$TMP/stdout"; then
  echo "ШИРОКЕ-IR-ПАМ’ЯТЬ-ПОМИЛКА: status=$STATUS або heaptrc виявив витік" >&2
  head -70 "$TMP/stderr" >&2
  cat "$TMP/stdout" >&2
  exit 1
fi
cat "$TMP/stdout"
echo 'ШИРОКЕ-IR-ПАМ’ЯТЬ-ГАРАЗД: FPC=реальний heaptrc=без-витоків pinned-SENS=так W12/W192=точні'
