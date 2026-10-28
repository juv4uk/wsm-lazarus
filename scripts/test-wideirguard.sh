#!/usr/bin/env bash
# G6.17: справжній FPC і pinned фізичний свідок SENS 12.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
command -v fpc >/dev/null || { echo 'СТОРОЖ-БЛОК: відсутній FPC' >&2; exit 127; }
mkdir -p build/m0.2/wideirguard/units build/m0.2/wideirguard/bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl -Fu"$ROOT/src" \
  -FU"$ROOT/build/m0.2/wideirguard/units" \
  -FE"$ROOT/build/m0.2/wideirguard/bin" \
  -otest-wideirguard "$ROOT/scripts/test-wideirguard.pas"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PIN=$(git -C external/sens rev-parse HEAD)
GITLINK=$(git ls-tree HEAD external/sens | awk '{print $3}')
test "$PIN" = "$GITLINK"
timeout 70s git -C external/sens show \
  "$PIN:tests/semantic/d5-d12-numberp-law.sens" > "$TMP/pinned.sens"
test -s "$TMP/pinned.sens"
"$ROOT/build/m0.2/wideirguard/bin/test-wideirguard" "$TMP/pinned.sens" \
  | tee "$TMP/свідчення.txt"
grep -Fq 'ШИРОКИЙ-СТОРОЖ-ГАРАЗД' "$TMP/свідчення.txt"
