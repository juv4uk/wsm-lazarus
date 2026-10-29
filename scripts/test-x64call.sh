#!/usr/bin/env bash
# G6.107 — справжній checked FPC, GNU as і два вкладені CALL/RET ELF64.
# Тільки x86-64 host-механіка; не загальний SENS-компілятор.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export LC_ALL=C.UTF-8 LANG=C.UTF-8
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'ЛОКАЛЬНИЙ-CALL-БЛОК: потрібен Linux x86-64' >&2; exit 127;
}
for bin in fpc timeout as objcopy readelf objdump cmp mktemp; do
  command -v "$bin" >/dev/null || {
    echo "ЛОКАЛЬНИЙ-CALL-БЛОК: немає $bin" >&2; exit 127;
  }
done
timeout 180s bash scripts/sync-authority.sh
timeout 120s bash scripts/check-pin.sh
TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then for f in "$TMP"/*.log; do
  [[ ! -s "$f" ]] || { echo "--- $f" >&2; tail -n 65 "$f" >&2; }
done; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/units" "$TMP/bin" "$TMP/data"
timeout 180s fpc -B -Mobjfpc -Cr -Co -Ci -gl -gh \
  -Fu"$ROOT/src" -FU"$TMP/units" -FE"$TMP/bin" -otest-x64call \
  "$ROOT/scripts/test-x64call.pas" >"$TMP/build.log" 2>&1 || {
    cat "$TMP/build.log" >&2; exit 1;
  }
HEAPTRC="log=$TMP/heap.log" timeout 30s \
  "$TMP/bin/test-x64call" "$TMP/data" >"$TMP/test.log" 2>"$TMP/err.log" || {
    cat "$TMP/test.log" "$TMP/err.log" >&2; exit 1;
  }
grep -Fq 'X64-ЛОКАЛЬНІ-ВИКЛИКИ-ГОТОВО golden=2 GNU-as=1 negative=13 nested-calls=2 elf=2' "$TMP/test.log"

# Незалежний GNU assembler як machine-encoding oracle.
timeout 15s as --64 "$TMP/data/call-matrix.s" -o "$TMP/fixture.o"
timeout 15s objcopy -O binary --only-section=.text \
  "$TMP/fixture.o" "$TMP/data/call-matrix.gnu.bin"
cmp "$TMP/data/call-matrix.fpc.bin" "$TMP/data/call-matrix.gnu.bin"

for bit in 0 1; do
  elf="$TMP/data/call-$bit.elf"
  test -s "$elf"
  chmod 700 "$elf"
  timeout 10s readelf -h "$elf" >"$TMP/header.log"
  grep -Eq 'Type:.*DYN' "$TMP/header.log"
  grep -Fq 'Advanced Micro Devices X86-64' "$TMP/header.log"
  timeout 10s readelf -l "$elf" >"$TMP/segments.log"
  ! grep -Eq 'INTERP|DYNAMIC' "$TMP/segments.log"
  tail -c +121 "$elf" >"$TMP/machine"
  timeout 10s objdump -D -b binary -m i386:x86-64 -M intel \
    "$TMP/machine" >"$TMP/asm.log"
  test "$(grep -Ec '^[[:space:]]*[0-9a-f]+:.*call[[:space:]]+' "$TMP/asm.log")" -eq 2
  test "$(grep -Ec '^[[:space:]]*[0-9a-f]+:.*ret' "$TMP/asm.log")" -eq 2
  grep -Eq 'push[[:space:]]+rbp' "$TMP/asm.log"
  grep -Eq 'pop[[:space:]]+rbp' "$TMP/asm.log"
  timeout 5s "$elf" >"$TMP/actual-$bit.sens"
  cmp "$TMP/actual-$bit.sens" "$TMP/data/call-$bit.expected.sens"
done
echo 'X64-ЛОКАЛЬНИЙ-CALL-ELF-ПЕРЕВІРЕНО GNU-as=байтово negative=13 nested-CALL/RET=2 ELF=2 T5M=точно energy=NOT-MEASURED'
