#!/usr/bin/env bash
# G6.168 — тільки легкий FPC/native для opt-in фізичного кешу.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc timeout git python3 mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "КЕШ-СЕАНС-БЛОК: немає $tool" >&2
    exit 127
  }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "КЕШ-СЕАНС-БЛОК: потрібен Linux x86-64" >&2; exit 127;
}
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 30s bash scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
cleanup() {
  local rc=$? file
  if ((rc)); then
    for file in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$file" ]] || { echo "--- $file" >&2; tail -n 35 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'src/senswidesesiiaelf.lpr senswidesesiiaelf'; do
  read -r source name <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$name" \
    "$ROOT/$source" >"$TMP/$name.build" 2>&1 || {
      cat "$TMP/$name.build" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 45s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/gen.out" 2>"$TMP/gen.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/gen.out"
timeout 250s python3 scripts/test-wide-sesiia-kesh.py \
  "$TMP/bin/senswidesesiiaelf" "$TMP/physical" \
  >"$TMP/cache.out" 2>"$TMP/cache.err"
grep -Fxq 'G6.168-КЕШ-СЕАНС-PASS frames=13 successful=11 negative=2 hits=7 misses=4 executed=3 terminal=8 oracle=NOT-CHECKED energy=NOT-MEASURED' "$TMP/cache.out"
if grep -Fq 'unfreed memory blocks' "$TMP/gen.err"; then
  grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$TMP/gen.err"
fi
echo 'G6.168-КЕШ-СЕАНС-МАШИННИЙ-ГОТОВО'
