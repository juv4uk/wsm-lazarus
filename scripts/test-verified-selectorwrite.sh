#!/usr/bin/env bash
# G6 — механічний доказ повного Linux write(1,rsp,1) для D3:100/011.
# Один FPC PR runner через чинний verified-all; без Rust/Zig/RAPL.
# Закони — виключно pinned external/sens, не цей Linux errno-тест.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == "x86_64" ]] || {
  echo 'СЕЛЕКТОР-WRITE-БЛОК: потрібен Linux x86_64' >&2; exit 127;
}
for tool in fpc timeout readelf objdump cmp git mktemp tail; do
  command -v "$tool" >/dev/null || {
    echo "СЕЛЕКТОР-WRITE-БЛОК: бракує $tool" >&2; exit 127;
  }
done
timeout 90s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = \
  1f1bf676eeac605e065035d9dd2adaae807f1788

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/physical"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" \
  -otest-elfselectort5m "$ROOT/scripts/test-elfselectort5m.pas" \
  >"$TMP/compile.log" 2>&1 || {
    tail -n 70 "$TMP/compile.log" >&2; exit 1;
  }
timeout 45s "$TMP/bin/test-elfselectort5m" \
  "$ROOT/external/sens" "$TMP/physical" \
  >"$TMP/fixtures.log" 2>"$TMP/fixtures.err" || {
    cat "$TMP/fixtures.log" "$TMP/fixtures.err" >&2; exit 1;
  }
grep -Fq 'МАШИННИЙ-СЕЛЕКТОР-T5M-ГАРАЗД позитивні=8 негативні=11' \
  "$TMP/fixtures.log"

printf '\\x39\\xd0\\x40\\x0f\\x95\\xc7\\x6a\\x3c\\x58\\x0f\\x05' \
  >"$TMP/checked-exit.bin"
PASS=0
CLOSED=0
FULL=0
RECOVERY=0
for name in перше-00 перше-01 перше-10 перше-11 \
            решта-00 решта-01 решта-10 решта-11; do
  ELF="$TMP/physical/$name.elf"
  EXPECT="$TMP/physical/$name.expected.sens"
  test -s "$ELF" && test -s "$EXPECT"
  test "$(wc -c < "$ELF")" -eq 204
  chmod 700 "$ELF"
  timeout 5s readelf -h "$ELF" >"$TMP/header"
  grep -Eq 'Type:.*DYN' "$TMP/header"
  timeout 5s readelf -l "$ELF" >"$TMP/segments"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments"
  tail -c 11 "$ELF" | cmp - "$TMP/checked-exit.bin"
  tail -c +121 "$ELF" >"$TMP/code"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/code" >"$TMP/disasm"
  for opcode in 'syscall' 'cmp' 'setne' 'imul'; do
    grep -Fq "$opcode" "$TMP/disasm"
  done
  timeout 5s "$ELF" >"$TMP/actual.sens" 2>"$TMP/actual.err"
  cmp "$EXPECT" "$TMP/actual.sens"
  test "$(wc -c <"$TMP/actual.sens")" -eq 1
  test ! -s "$TMP/actual.err"
  PASS=$((PASS+1))

  code=0
  timeout 5s bash -c 'exec 1>&-; exec "$1"' _ "$ELF" \
    2>"$TMP/closed.err" || code=$?
  test "$code" -eq 1 && test ! -s "$TMP/closed.err"
  CLOSED=$((CLOSED+1))

  code=0
  timeout 5s "$ELF" >/dev/full 2>"$TMP/full.err" || code=$?
  test "$code" -eq 1 && test ! -s "$TMP/full.err"
  FULL=$((FULL+1))

  timeout 5s "$ELF" >"$TMP/recovery.sens" 2>"$TMP/recovery.err"
  cmp "$EXPECT" "$TMP/recovery.sens"
  test ! -s "$TMP/recovery.err"
  RECOVERY=$((RECOVERY+1))
done
test "$PASS" -eq 8 && test "$CLOSED" -eq 8 && \
  test "$FULL" -eq 8 && test "$RECOVERY" -eq 8
echo 'D3-SELECTOR-WRITE-PASS fpc=checked elf=8 t5m=8 pinned-negatives=11 closed=8 full=8 recovery=8 independent-oracle=NOT-RUN energy=NOT-MEASURED'
