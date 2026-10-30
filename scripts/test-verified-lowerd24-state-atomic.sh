#!/usr/bin/env bash
# G6.264 — checked FPC: W24 відмова не пропускає чужий D7 у наступний ELF.
# Той самий pinned T5M + Linux native ELF, жодного другого evaluator.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'LOWER24-STATE-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in fpc timeout git grep; do
  command -v "$tool" >/dev/null || {
    echo "LOWER24-STATE-БЛОК: немає $tool" >&2; exit 127;
  }
done
timeout 90s bash scripts/check-pin.sh >/dev/null
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-lowerd24-state-atomic "$ROOT/scripts/test-lowerd24-state-atomic.pas" \
  >"$TMP/build.log" 2>&1 || {
    tail -60 "$TMP/build.log" >&2; exit 1;
  }
test -x "$TMP/bin/test-lowerd24-state-atomic"
timeout 50s "$TMP/bin/test-lowerd24-state-atomic" "$ROOT" \
  >"$TMP/stdout" 2>"$TMP/stderr" || {
    cat "$TMP/stdout" >&2; cat "$TMP/stderr" >&2; exit 1;
  }
grep -Eq '^LOWER24-STATE-ATOMIC-PASS checks=[0-9]+ negatives=4 native=7 phantom=blocked energy=NOT-MEASURED oracle=NOT-RUN$' "$TMP/stdout"
if grep -Fq 'unfreed memory blocks' "$TMP/stderr"; then
  grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$TMP/stderr" || {
    cat "$TMP/stderr" >&2; exit 1;
  }
fi
grep -F 'LOWER24-STATE-ATOMIC-PASS' "$TMP/stdout"
