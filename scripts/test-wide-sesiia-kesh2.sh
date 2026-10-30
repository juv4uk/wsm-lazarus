#!/usr/bin/env bash
# G6.177 — двомісний LRU кеш pinned WideIR→ELF64 у тому самому FPC процесі.
# Тільки легкий FPC+Python механічний тест; no Rust/Zig on push.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc git timeout python3 mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "КЕШ-2-БЛОК: відсутній $tool" >&2; exit 127;
  }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "КЕШ-2-БЛОК: потрібен Linux x86-64" >&2; exit 127;
}
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
timeout 30s bash scripts/check-no-lcl.sh
PIN=1f1bf676eeac605e065035d9dd2adaae807f1788
test "$(git -C external/sens rev-parse HEAD)" = "$PIN"
TMP=$(mktemp -d)
cleanup() {
  local rc=$? f
  if ((rc)); then
    for f in "$TMP"/*.build "$TMP"/*.err; do
      [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 35 "$f" >&2; }
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
    "$ROOT/$source" >"$TMP/$name.build" 2>"$TMP/$name.err" || {
      cat "$TMP/$name.build" "$TMP/$name.err" >&2; exit 1;
    }
  test -x "$TMP/bin/$name"
done
timeout 45s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixtures.out"
timeout 480s python3 scripts/test-wide-sesiia-kesh2.py \
  "$TMP/bin/senswidesesiiaelf" "$TMP/physical" \
  >"$TMP/result.out" 2>"$TMP/result.err" || {
    cat "$TMP/result.err" >&2; exit 1;
  }
grep -Fxq 'G6.177-КЕШ-2-ПРОЙДЕНО frames=64 good=62 negative=2 one-hits=0 one-misses=62 two-hits=60 two-misses=2 evict-hits=2 evict-misses=5 executed=2 terminal=4 oracle=NOT-CHECKED energy=NOT-MEASURED' "$TMP/result.out"
if grep -Fq 'unfreed memory blocks' "$TMP/fixtures.err"; then
  grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$TMP/fixtures.err"
fi
echo 'G6.177-КЕШ-2-МАШИННИЙ-ГОТОВО'
