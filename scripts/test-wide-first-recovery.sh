#!/usr/bin/env bash
# G6.188 — FPC checked + справжні ELF64 після відхиленого фізичного кадру.
# Жодного редагування production-коду, pinned законів чи чужого CI.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'G6.188-БЛОК: потрібен Linux x86-64' >&2
  exit 127
}
for program in timeout fpc git python3 grep mktemp; do
  command -v "$program" >/dev/null || {
    echo "G6.188-БЛОК: відсутній $program" >&2
    exit 127
  }
done
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 120s bash scripts/check-no-lcl.sh
[[ "$(git -C external/sens rev-parse HEAD)" == "$PIN" ]]
TMP="$(mktemp -d)"
cleanup() {
  local rc=$?
  if ((rc)); then
    echo "G6.188-RED rc=$rc" >&2
    for file in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$file" ]] || { echo "---- $file" >&2; tail -n 25 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
for pair in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidesesiiaelf.lpr senswidesesiiaelf'; do
  read -r source binary <<<"$pair"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/$binary.build" 2>"$TMP/$binary.err" || {
      cat "$TMP/$binary.build" "$TMP/$binary.err" >&2; exit 1;
    }
  test -x "$TMP/bin/$binary"
done
timeout 45s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixtures.log"
timeout 120s python3 scripts/test-wide-first-recovery.py \
  "$TMP/bin/senswidesesiiaelf" "$TMP/physical" \
  >"$TMP/result.log" 2>"$TMP/result.err" || {
    cat "$TMP/result.err" >&2; exit 1;
  }
test ! -s "$TMP/result.err"
grep -Fxq 'ШВИДКИЙ-ПЕРШИЙ-ВІДНОВЛЕННЯ-PASS sessions=4 frames=44 success=28 negatives=16 machine=28 parity=byte-exact invalid-to-valid=yes oracle=NOT-CHECKED energy=NOT-MEASURED' "$TMP/result.log"
cat "$TMP/result.log"
