#!/usr/bin/env bash
# G6.119 — actual checked FPC, 16 genuine ELF64 + independent SENS oracle.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'G6_119_BLOCK need Linux x86_64' >&2; exit 127;
}
for tool in fpc timeout cmp readelf objdump git mktemp; do
  command -v "$tool" >/dev/null || {
    echo "G6_119_BLOCK missing $tool" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE"
test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for f in "$TMP"/*.log "$TMP"/*.err; do
    [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 75 "$f" >&2; }
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/phys"
for entry in 'scripts/test-irnestedeqcall.pas:test-irnestedeqcall' \
  'src/sensvykon.lpr:sensvykon'; do
  IFS=: read -r source binary <<< "$entry"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/build-$binary.log" 2>&1 || {
      cat "$TMP/build-$binary.log" >&2; exit 1;
    }
done
HEAPTRC="log=$TMP/heap.log" timeout 120s \
  "$TMP/bin/test-irnestedeqcall" "$TMP/phys" >"$TMP/test.log" \
  2>"$TMP/test.err" || {
    cat "$TMP/test.err" "$TMP/test.log" >&2; exit 1;
  }
grep -Fq 'G6_119_OK ELF=16 NEG=18 CALLS=3 RET=1' "$TMP/test.log"
grep -Fq '0 unfreed memory blocks' "$TMP/heap.log"
N=0
for source in "$TMP"/phys/d3-????.sens; do
  prefix="${source%.sens}"
  exe="$prefix.elf"
  expected="$prefix.expected.sens"
  test -s "$source" && test -s "$exe" && test -s "$expected"
  chmod 700 "$exe"
  timeout 8s readelf -h "$exe" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 8s readelf -l "$exe" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$exe" >"$TMP/asm.bin"
  timeout 8s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/asm.bin" >"$TMP/disassembly.log"
  test "$(grep -Ec '^[[:space:]]*[[:xdigit:]]+:[[:space:]]+[[:xdigit:] ]+[[:space:]]+call[[:space:]]' "$TMP/disassembly.log")" -eq 3
  test "$(grep -Ec '^[[:space:]]*[[:xdigit:]]+:[[:space:]]+[[:xdigit:] ]+[[:space:]]+ret' "$TMP/disassembly.log")" -eq 1
  timeout 8s "$exe" >"$TMP/current.sens" 2>"$TMP/elf.err"
  test ! -s "$TMP/elf.err"
  cmp "$TMP/current.sens" "$expected"
  timeout 60s "$ORACLE" "$source" >"$TMP/oracle.txt" \
    2>"$TMP/oracle.err"
  test ! -s "$TMP/oracle.err"
  timeout 10s "$TMP/bin/sensvykon" --виконати "$source" \
    >"$TMP/fpc.txt" 2>"$TMP/fpc.err"
  test ! -s "$TMP/fpc.err"
  cmp "$TMP/oracle.txt" "$TMP/fpc.txt"
  N=$((N+1))
done
test "$N" -eq 16
echo 'G6_119_ELF_OK PHYSICAL=16 NATIVE=16 PINNED_SENS=16 FPC_EVAL=16 NEGATIVE=18 CALLS=3 RET=1 HEAP=ZERO ENERGY=NOT_MEASURED'
