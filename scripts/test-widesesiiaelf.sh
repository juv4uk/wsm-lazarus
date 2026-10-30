#!/usr/bin/env bash
# G6.163 — real-time FPC→WideIR→ELF session з відновленням host-кадрів.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in git timeout fpc python3 readelf mktemp; do
  command -v "$tool" >/dev/null || {
    echo "СЕАНС-ELF-БЛОК: немає $tool" >&2; exit 127;
  }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "СЕАНС-ELF-БЛОК: потрібен Linux x86-64" >&2; exit 127;
}
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
TMP=$(mktemp -d)
cleanup() {
  local rc=$?
  if (( rc )); then
    for f in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 35 "$f" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidefrontelf.lpr senswidefrontelf' \
  'src/senswidesesiiaelf.lpr senswidesesiiaelf'; do
  read -r source name <<< "$row"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
      cat "$TMP/$name.build" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 45s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/gen.out" 2>"$TMP/gen.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/gen.out"
timeout 600s python3 "$ROOT/scripts/test-widesesiiaelf.py" \
  "$TMP/bin/senswidesesiiaelf" "$TMP/bin/senswidefrontelf" \
  "$TMP/physical" "$(command -v readelf)" \
  >"$TMP/test.out" 2>"$TMP/test.err" || {
    cat "$TMP/test.err" >&2; exit 1;
  }
if [[ -n "${SENS_ORACLE_BIN:-}" ]]; then
  grep -Fxq 'G6.163-СЕАНС-ELF-OK machine=17 recoverable=13 terminal=6 oracle=16' "$TMP/test.out"
else
  grep -Fxq 'G6.163-СЕАНС-ELF-OK machine=17 recoverable=13 terminal=6 oracle=0' "$TMP/test.out"
fi
if grep -Fq 'unfreed memory blocks' "$TMP/gen.err"; then
  grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$TMP/gen.err"
fi
echo 'G6.163-СЕАНС-МАШИННИЙ-ТЕСТ-ГОТОВО'
