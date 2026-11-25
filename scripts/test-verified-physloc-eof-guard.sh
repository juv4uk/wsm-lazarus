#!/usr/bin/env bash
# G1.59 — EOF координата зобов'язана перевірити останній фізичний span.
# Автоматично працює всередині чинного fpc-headless/test-verified-all.sh.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'PHYSLOC-EOF-БЛОК: Free Pascal відсутній' >&2
  exit 127
}
command -v timeout >/dev/null || exit 127
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-physloc-eof-guard "$ROOT/scripts/test-physloc-eof-guard.pas" \
  >"$TMP/fpc.log" 2>&1 || {
    cat "$TMP/fpc.log" >&2
    exit 1
  }
timeout 30s "$TMP/bin/test-physloc-eof-guard" >"$TMP/rezultat" 2>"$TMP/stderr" || {
  cat "$TMP/rezultat" "$TMP/stderr" >&2
  exit 1
}
grep -Fxq 'VERIFIED-PHYSLOC-EOF-PASS FPC=checked wide=192 negative=5 recovery=5 energy=NOT-MEASURED' "$TMP/rezultat"
if grep -Fq 'unfreed memory blocks' "$TMP/stderr"; then
  grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$TMP/stderr" || {
    cat "$TMP/stderr" >&2
    exit 1
  }
fi
cat "$TMP/rezultat"
