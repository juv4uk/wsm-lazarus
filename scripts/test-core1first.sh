#!/usr/bin/env bash
# Core1.2 — pinned фізичний виклик першої бібліотечної функції; без SID8.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || { echo 'CORE1-FIRST-БЛОК: немає FPC' >&2; exit 127; }
command -v git >/dev/null || { echo 'CORE1-FIRST-БЛОК: немає git' >&2; exit 127; }
mkdir -p build/m0.2/core1first/units build/m0.2/core1first/bin
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
# git blob — єдиний pinned Core1 .sens. Не міняємо чужий sparse authority.
timeout 180s git -C external/sens show HEAD:lib/core1.sens > "$TMP/core1.sens"
test -s "$TMP/core1.sens"
"$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/core1first/units" \
  -FE"$ROOT/build/m0.2/core1first/bin" -otestcore1first \
  scripts/test-core1first.pas
timeout 120s "$ROOT/build/m0.2/core1first/bin/testcore1first" \
  "$ROOT" "$TMP/core1.sens" "$TMP" > "$TMP/output" 2> "$TMP/stderr"
grep -Fq 'CORE1-FIRST-PASS' "$TMP/output"
grep -Fq 'GC=not-integrated' "$TMP/output"
! grep -Fq 'unfreed memory blocks :' "$TMP/stderr" || \
  ! grep -E '[1-9][0-9]* unfreed memory blocks' "$TMP/stderr"
echo 'CORE1-ПЕРШИЙ-ВИКЛИК-ГАРАЗД FPC=реальний джерело=pinned-T5M замикання=перше D4=існуючий-runtime'
