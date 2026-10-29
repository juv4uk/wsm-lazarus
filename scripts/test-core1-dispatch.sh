#!/usr/bin/env bash
# Core1.4: з'єднання двох вже злитих механізмів без дублювання evaluator.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
./scripts/check-pin.sh
test -s "$ROOT/external/sens/lib/core1.sens"
test -s "$ROOT/external/sens/lib/core4.sens"
FPC_BIN=${FPC:-fpc}
command -v "$FPC_BIN" >/dev/null || {
  echo 'CORE1-МАРШРУТ-БЛОК: Free Pascal відсутній' >&2; exit 127;
}
mkdir -p build/m0.2/core1-dispatch-units build/m0.2/core1-dispatch-bin
timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$ROOT/build/m0.2/core1-dispatch-units" \
  -FE"$ROOT/build/m0.2/core1-dispatch-bin" \
  -otest-core1-dispatch "$ROOT/scripts/test-core1-dispatch.pas"
APP="$ROOT/build/m0.2/core1-dispatch-bin/test-core1-dispatch"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
timeout 90s "$APP" "$ROOT" >"$TMP/перший.stdout" 2>"$TMP/перший.stderr" || {
  cat "$TMP/перший.stderr" >&2
  echo 'CORE1-МАРШРУТ-ПРОВАЛ: не пройшов позитивний фізичний тест' >&2
  exit 1
}
grep -Fq 'CORE1-МАРШРУТ-ГАРАЗД фізичних-визначень=96 відхилено-відомих=95' "$TMP/перший.stdout"
grep -Fq 'D7=точний виконання=перше GC=без-змін' "$TMP/перший.stdout"
grep -Fq '0 unfreed memory blocks' "$TMP/перший.stderr" || {
  cat "$TMP/перший.stderr" >&2; exit 1;
}
timeout 90s "$APP" "$ROOT" >"$TMP/повтор.stdout" 2>"$TMP/повтор.stderr"
cmp "$TMP/перший.stdout" "$TMP/повтор.stdout"
grep -Fq '0 unfreed memory blocks' "$TMP/повтор.stderr"
cat "$TMP/перший.stdout"
echo 'CORE1-МАРШРУТ-ТЕСТ-ГАРАЗД pinned=так FPC=так D7=96 негативні=101 відновлення=так'
