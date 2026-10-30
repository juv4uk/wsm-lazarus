#!/usr/bin/env bash
# G6 — справжній FPC та регресія точного WideIR після host allocation.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc timeout git grep mktemp; do
  command -v "$tool" >/dev/null || { echo "ШИРОКЕ-ЗРОСТАННЯ-БЛОК: $tool" >&2; exit 127; }
done
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-wideir-rost "$ROOT/scripts/test-wideir-rost.pas" \
  >"$TMP/build.log" 2>&1 || { cat "$TMP/build.log" >&2; exit 1; }
timeout 60s "$TMP/bin/test-wideir-rost" >"$TMP/actual" 2>"$TMP/stderr" || {
  cat "$TMP/stderr" >&2; cat "$TMP/actual" >&2; exit 1;
}
grep -Fq 'WIDEIR-ROST-OK' "$TMP/actual" || {
  cat "$TMP/actual" >&2; cat "$TMP/stderr" >&2;
  echo 'ШИРОКЕ-ЗРОСТАННЯ-ВІДМОВА: немає машинного маркера' >&2
  exit 1
}
if grep -Fq 'unfreed memory blocks' "$TMP/stderr"; then
  grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$TMP/stderr" || {
    cat "$TMP/stderr" >&2; exit 1;
  }
fi
cat "$TMP/actual"
# Existing pinned SENS witness and full preexisting negative suite.
timeout 240s bash scripts/test-wideir.sh
