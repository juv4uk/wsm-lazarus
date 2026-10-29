#!/usr/bin/env bash
# G3.50 — реальна FPC-збірка + фізична діагностика D7-голови Core1.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
for cmd in fpc timeout git grep mktemp; do
  command -v "$cmd" >/dev/null || { echo "CORE1-ГОЛОВА-БЛОК: немає $cmd" >&2; exit 127; }
done
timeout 90s bash scripts/check-pin.sh
test -s external/sens/lib/core1.sens
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-core1-head-spans "$ROOT/scripts/test-core1-head-spans.pas" \
  >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2
    exit 1
  }
timeout 90s "$TMP/bin/test-core1-head-spans" "$ROOT" \
  >"$TMP/test.out" 2>"$TMP/test.err" || {
    cat "$TMP/test.err" >&2
    cat "$TMP/test.out" >&2
    exit 1
  }
grep -Fq 'CORE1-ФІЗИЧНІ-ГОЛОВИ-ГАРАЗД FPC=так' "$TMP/test.out"
grep -Fq 'голова=слово/трити/байти відновлення=так' "$TMP/test.out"
# heaptrc за відсутності витоків іноді мовчить. Ненульові блоки — провал.
if grep -q 'unfreed memory blocks' "$TMP/test.err" &&
   grep 'unfreed memory blocks' "$TMP/test.err" |
     grep -Eq '(^|[^0-9])[1-9][0-9]* unfreed memory blocks'; then
  cat "$TMP/test.err" >&2
  exit 1
fi
# Чинна повна перевірка indexed Core1, жодного ослаблення негативів.
timeout 240s bash scripts/test-core1-dispatch.sh >"$TMP/old.out" \
  2>"$TMP/old.err" || {
    cat "$TMP/old.out" >&2
    cat "$TMP/old.err" >&2
    exit 1
  }
grep -Fq 'CORE1-МАРШРУТ-ТЕСТ-ГАРАЗД' "$TMP/old.out"
cat "$TMP/test.out"
echo 'CORE1-ГОЛОВА-ІНТЕГРАЦІЯ-ГАРАЗД existing-dispatch=так'
