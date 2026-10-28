#!/usr/bin/env bash
# G4.13: збірка реальним FPC; тільки pinned фізичний Core4.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
command -v fpc >/dev/null || { echo 'CORE4-БЛОК: немає FPC' >&2; exit 127; }
./scripts/check-pin.sh
mkdir -p build/m0.2/core4-nested-units build/m0.2/core4-nested-bin
fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/core4-nested-units" \
  -FE"$ROOT/build/m0.2/core4-nested-bin" \
  -otest-core4-nested "$ROOT/scripts/test-core4-nested.pas"
LC_ALL=C.UTF-8 "$ROOT/build/m0.2/core4-nested-bin/test-core4-nested" "$ROOT" |
  tee build/m0.2/core4-nested-bin/core4-nested-result.txt
grep -Fq 'CORE4-NESTED-OK' build/m0.2/core4-nested-bin/core4-nested-result.txt
bash ./scripts/test-core4runtime.sh
