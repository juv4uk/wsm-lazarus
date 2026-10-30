#!/usr/bin/env bash
# G1.57 — W24-opaque, 4096-byte T5M/D2 boundary; не SENS oracle.
# Новий незалежний verified-свідок у чинному єдиному FPC job.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'T5M-4096-БЛОК: Free Pascal відсутній' >&2
  exit 127
}
command -v timeout >/dev/null || exit 127
timeout 120s bash scripts/check-pin.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-t5m-4096-mezha "$ROOT/scripts/test-t5m-4096-mezha.pas" \
  >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2
    exit 1
  }
timeout 30s "$TMP/bin/test-t5m-4096-mezha" \
  >"$TMP/result" 2>"$TMP/err" || {
    cat "$TMP/result" "$TMP/err" >&2
    exit 1
  }
grep -Fxq 'VERIFIED-T5M-4096-PASS positive=4 negative=3 byte=4096 trit=20480 word=820 recovery=1 energy=NOT-MEASURED' "$TMP/result"
if grep -Fq 'unfreed memory blocks' "$TMP/err"; then
  grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$TMP/err" || {
    cat "$TMP/err" >&2
    exit 1
  }
fi
cat "$TMP/result"
