#!/usr/bin/env bash
# G6.107 — real checked FPC, GNU-as bytes, 4 real ELF, independent SENS.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export LC_ALL=C.UTF-8 LANG=C.UTF-8
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'CALL-КОДЕР-БЛОК: потрібна Linux x86_64' >&2; exit 127;
}
for cmd in fpc timeout git cmp as objcopy readelf objdump mktemp; do
  command -v "$cmd" >/dev/null || {
    echo "CALL-КОДЕР-БЛОК: немає $cmd" >&2; exit 127;
  }
done
timeout 120s bash scripts/check-pin.sh
test "$(git -C external/sens rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
ORACLE="$ROOT/sens-oracle/target/debug/sens"
test -x "$ORACLE" || {
  echo 'CALL-КОДЕР-БЛОК: потрібен незалежний SENS CLI' >&2; exit 127;
}
test "$(git -C sens-oracle rev-parse HEAD)" = 1f1bf676eeac605e065035d9dd2adaae807f1788
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then
  for log in "$TMP"/*.log "$TMP"/*.err; do
    if [[ -s "$log" ]]; then echo "--- $log" >&2; tail -n 90 "$log" >&2; fi
  done
fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/units" "$TMP/phys"
for entry in 'scripts/test-ircallwriter.pas:test-ircallwriter' \
  'src/sensvykon.lpr:sensvykon'; do
  IFS=: read -r source binary <<<"$entry"
  timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
    -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" "-o$binary" \
    "$ROOT/$source" >"$TMP/build-$binary.log" 2>&1 || {
      cat "$TMP/build-$binary.log" >&2; exit 1;
    }
done
HEAPTRC="log=$TMP/heap.log" timeout 60s "$TMP/bin/test-ircallwriter" \
  "$TMP/phys" >"$TMP/test.log" 2>"$TMP/test.err" || {
    cat "$TMP/test.err" "$TMP/test.log" >&2; exit 1;
  }
grep -Fq 'G6_107_OK ELF=4 PHYS_NEG=13 HOST_NEG=12' "$TMP/test.log"
# Незалежний GNU assembler: обидва знаки CALL rel32 + RET.
timeout 15s as --64 "$TMP/phys/call-matrix.s" -o "$TMP/call.o"
timeout 15s objcopy -O binary --only-section=.text \
  "$TMP/call.o" "$TMP/phys/call-matrix.gnu.bin"
cmp "$TMP/phys/call-matrix.fpc.bin" "$TMP/phys/call-matrix.gnu.bin"
COUNT=0
for name in рівність-00 рівність-01 рівність-10 рівність-11; do
  EXE="$TMP/phys/$name.elf"
  SRC="$TMP/phys/$name.sens"
  test -s "$EXE" && test -s "$SRC"
  chmod 700 "$EXE"
  timeout 5s readelf -h "$EXE" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 5s readelf -l "$EXE" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$EXE" >"$TMP/machine.bin"
  timeout 5s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine.bin" >"$TMP/asm.log"
  for m in call ret cmp sete syscall; do
    grep -Fq "$m" "$TMP/asm.log"
  done
  timeout 5s "$EXE" >"$TMP/current.sens" 2>"$TMP/elf.err"
  test ! -s "$TMP/elf.err"
  cmp "$TMP/phys/$name.expected.sens" "$TMP/current.sens"
  timeout 60s "$ORACLE" "$SRC" >"$TMP/oracle.txt" 2>"$TMP/oracle.err"
  test ! -s "$TMP/oracle.err"
  timeout 10s "$TMP/bin/sensvykon" --виконати "$SRC" \
    >"$TMP/fpc.txt" 2>"$TMP/fpc.err"
  test ! -s "$TMP/fpc.err"
  cmp "$TMP/oracle.txt" "$TMP/fpc.txt"
  COUNT=$((COUNT+1))
done
test "$COUNT" -eq 4
echo 'CALL-КОДЕР-ELF-ПЕРЕВІРЕНО checked-FPC=так GNU-as=byte-exact ELF=4 canonical-T5M=4 independent-SENS=4 fail-closed=25 energy=NOT-MEASURED'
