#!/usr/bin/env bash
# G6 — реальний FPC+Python тест чотиримісного кешу; без Rust/Zig.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in fpc timeout git python3 mktemp grep; do
  command -v "$tool" >/dev/null || {
    echo "КЕШ-4-БЛОК: відсутній $tool" >&2
    exit 127
  }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'КЕШ-4-БЛОК: потрібен Linux x86-64' >&2
  exit 127
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
      [[ ! -s "$file" ]] || {
        echo "--- $file" >&2
        tail -n 30 "$file" >&2
      }
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
      cat "$TMP/$name.build" "$TMP/$name.err" >&2
      exit 1
    }
  test -x "$TMP/bin/$name"
done
timeout 45s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/fixtures.out" 2>"$TMP/fixtures.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/fixtures.out"
timeout 570s python3 scripts/test-wide-sesiia-kesh4.py \
  "$TMP/bin/senswidesesiiaelf" "$TMP/physical" \
  >"$TMP/test.out" 2>"$TMP/test.err" || {
    cat "$TMP/test.err" >&2
    exit 1
  }
grep -Fqx 'G6-КЕШ-4-ПРОЙДЕНО frames=64 good=62 negative=2 two-hits=0 two-misses=62 four-hits=58 four-misses=4 evict-hits=3 evict-misses=8 executed=4 terminal=5 oracle=NOT-CHECKED energy=NOT-MEASURED' "$TMP/test.out"
grep -Fq 'HOST-МЕДІАНА-НС без-кешу=' "$TMP/test.out"
echo 'G6-КЕШ-4-МАШИННИЙ-ГОТОВО'
