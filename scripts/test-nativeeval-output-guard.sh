#!/usr/bin/env bash
# G3 / #803 — fail-closed writer для host ncClosure/ncName, FPC only.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in git fpc timeout mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "NATIVEEVAL-OUTPUT-GUARD-BLOCK: немає $tool" >&2; exit 127;
  }
done
if [[ -n "${EXPECTED_HEAD_SHA:-}" ]]; then
  [[ "$(git rev-parse HEAD)" == "$EXPECTED_HEAD_SHA" ]] || {
    echo 'NATIVEEVAL-OUTPUT-GUARD-BLOCK: невідповідний PR HEAD' >&2; exit 1;
  }
fi
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" =   "1f1bf676eeac605e065035d9dd2adaae807f1788"
TMP=$(mktemp -d)
cleanup() {
  local code=$?
  if ((code)); then
    for f in "$TMP"/*.log; do
      [[ ! -f "$f" ]] || { echo "--- $f" >&2; tail -n 60 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-nativeeval-output-guard \
  "$ROOT/scripts/test-nativeeval-output-guard.pas" \
  >"$TMP/new.build.log" 2>&1 || {
    cat "$TMP/new.build.log" >&2; exit 1;
  }
test -x "$TMP/bin/test-nativeeval-output-guard"
timeout 30s "$TMP/bin/test-nativeeval-output-guard" >"$TMP/guard.log" 2>&1 || {
  cat "$TMP/guard.log" >&2; exit 1;
}
grep -q '^NATIVEEVAL-OUTPUT-GUARD-PASS checks=' "$TMP/guard.log"
cat "$TMP/guard.log"
# Той самий вузький evaluator, його існуючі позитиви й негативи.
timeout 180s bash scripts/test-nativeeval.sh >"$TMP/original.log" 2>&1 || {
  cat "$TMP/original.log" >&2; exit 1;
}
grep -q '^NATIVEEVAL-OK checks=' "$TMP/original.log"
grep '^NATIVEEVAL-OK checks=' "$TMP/original.log"
echo 'NATIVEEVAL-OUTPUT-GUARD-CI-PASS native=YES physical=YES oracle=NOT_RUN'
