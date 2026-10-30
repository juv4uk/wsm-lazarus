#!/usr/bin/env bash
# G6.157 — один FPC-процес, 81 виклик exact WideIR та 76 відмов.
# Машинний результат порівнюється з чинними фізичними свідками;
# це не нове незалежне підтвердження семантики SENS.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for tool in git fpc timeout cmp readelf grep chmod mktemp; do
  command -v "$tool" >/dev/null || { echo "КОМПІЛЯТОР-ПОВТОР-БЛОК: немає $tool" >&2; exit 127; }
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'КОМПІЛЯТОР-ПОВТОР-БЛОК: потрібен Linux x86-64' >&2; exit 127;
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
      [[ ! -s "$file" ]] || { echo "--- $file" >&2; tail -n 40 "$file" >&2; }
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
FPC_BIN=${FPC:-fpc}
for row in \
  'scripts/test-irwidefront.pas test-irwidefront' \
  'scripts/test-irwidefront-povtor.pas test-irwidefront-povtor'; do
  read -r source exe <<< "$row"
  timeout 180s "$FPC_BIN" -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$exe" \
    "$ROOT/$source" >"$TMP/$exe.build" 2>"$TMP/$exe.build.err" || {
      cat "$TMP/$exe.build" "$TMP/$exe.build.err" >&2; exit 1;
    }
  test -x "$TMP/bin/$exe"
done
timeout 60s "$TMP/bin/test-irwidefront" "$TMP/physical" \
  >"$TMP/generator.out" 2>"$TMP/generator.err"
grep -Fxq 'G6.97-WIDE-FRONT-FIXTURES-OK cases=16' "$TMP/generator.out"
timeout 240s "$TMP/bin/test-irwidefront-povtor" "$TMP/physical" \
  >"$TMP/repeat.out" 2>"$TMP/repeat.err"
grep -Fxq 'G6.157-WIDEIR-POVTOR-PASS physical=16 good=81 negative=76 recovery=1 byte-identical=65 energy=NOT-MEASURED' "$TMP/repeat.out"
heap_ok() {
  if grep -Fq 'unfreed memory blocks' "$1"; then
    grep -Eq '(^|[[:space:]])0 unfreed memory blocks' "$1"
  fi
}
heap_ok "$TMP/generator.err"
heap_ok "$TMP/repeat.err"
COUNT=0
for ((i=1;i<=16;i++)); do
  printf -v tag '%02d' "$i"
  elf="$TMP/physical/$tag.povtor.elf"
  test -s "$elf"
  readelf -h "$elf" >"$TMP/$tag.header"
  grep -Eq 'Type:[[:space:]]+DYN' "$TMP/$tag.header"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/$tag.header"
  ! readelf -l "$elf" | grep -Eq 'INTERP|DYNAMIC'
  chmod 700 "$elf"
  timeout 5s "$elf" >"$TMP/$tag.actual.sens" 2>"$TMP/$tag.machine.err"
  test ! -s "$TMP/$tag.machine.err"
  cmp "$TMP/physical/$tag.expected.sens" "$TMP/$tag.actual.sens"
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 16
echo "G6.157-WIDEIR-MACHINE-PASS executed=$COUNT exact-T5M=$COUNT compiler-calls=81 failures=76 oracle=NOT-CHECKED energy=NOT-MEASURED"
